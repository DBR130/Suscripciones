// Análisis: cálculo puro y GET /api/analisis.
import assert from 'node:assert/strict';
import { after, before, describe, it } from 'node:test';

import request from 'supertest';

import { prepararBdPruebas } from './helpers/bd.js';
import { calcularAnalisis, cobrosEnVentana, masCaras } from '../src/services/analisis.js';
import { hoyColombia, sumarDias } from '../src/utils/fechas.js';

const HOY = '2026-11-10';

let siguienteId = 1;
function sus(datos) {
  return {
    id: siguienteId++,
    nombre_servicio: 'Servicio',
    categoria: null,
    monto: 10000,
    moneda: 'COP',
    frecuencia: 'mensual',
    fecha_proximo_cobro: '2026-12-01',
    es_prueba_gratis: false,
    fecha_fin_prueba: null,
    estado: 'activa',
    ...datos,
  };
}

describe('cobrosEnVentana', () => {
  it('ordena por fecha y deja fuera lo que pasa de 30 días', () => {
    const cobros = cobrosEnVentana([
      sus({ nombre_servicio: 'Lejos', fecha_proximo_cobro: '2026-12-11' }), // 31 días
      sus({ nombre_servicio: 'B', fecha_proximo_cobro: '2026-11-20' }),
      sus({ nombre_servicio: 'Hoy', fecha_proximo_cobro: HOY }),
      sus({ nombre_servicio: 'Borde', fecha_proximo_cobro: '2026-12-10' }), // 30 días
    ], HOY);
    assert.deepEqual(cobros.map((c) => [c.nombre_servicio, c.dias_restantes]), [
      // "Hoy" es mensual: vuelve a cobrarse el 10 de diciembre (día 30).
      ['Hoy', 0], ['B', 10], ['Borde', 30], ['Hoy', 30],
    ]);
  });

  it('repite las semanales y adelanta las fechas vencidas', () => {
    const cobros = cobrosEnVentana([
      sus({ nombre_servicio: 'Gym', frecuencia: 'semanal', fecha_proximo_cobro: '2026-11-08' }),
    ], HOY);
    assert.deepEqual(cobros.map((c) => c.fecha), ['2026-11-15', '2026-11-22', '2026-11-29', '2026-12-06']);
  });

  it('la prueba gratis aparece el día que pasa a pago, con su monto', () => {
    const cobros = cobrosEnVentana([
      sus({ nombre_servicio: 'Max', monto: 19900, es_prueba_gratis: true, fecha_fin_prueba: '2026-11-12' }),
      sus({ nombre_servicio: 'Vencida', es_prueba_gratis: true, fecha_fin_prueba: '2026-11-01' }),
    ], HOY);
    assert.deepEqual(cobros, [{
      suscripcion_id: cobros[0].suscripcion_id,
      nombre_servicio: 'Max',
      monto: 19900,
      moneda: 'COP',
      fecha: '2026-11-12',
      dias_restantes: 2,
      fin_de_prueba: true,
    }]);
  });
});

describe('masCaras', () => {
  it('por gasto mensual equivalente, COP primero y sin pruebas gratis', () => {
    const r = masCaras([
      sus({ nombre_servicio: 'Anual', monto: 600000, frecuencia: 'anual' }), // 50.000/mes
      sus({ nombre_servicio: 'Semanal', monto: 15000, frecuencia: 'semanal' }), // 65.000/mes
      sus({ nombre_servicio: 'USD', monto: 20, moneda: 'USD' }),
      sus({ nombre_servicio: 'Prueba', monto: 999999, es_prueba_gratis: true, fecha_fin_prueba: '2026-11-20' }),
      sus({ nombre_servicio: 'Barata', monto: 5000 }),
    ]);
    assert.deepEqual(r.map((s) => [s.nombre_servicio, s.gasto_mensual]), [
      ['Semanal', 65000], ['Anual', 50000], ['Barata', 5000],
    ]);
  });
});

describe('calcularAnalisis', () => {
  it('sin datos devuelve todo vacío y la gráfica COP en ceros', () => {
    const r = calcularAnalisis([], [], [], HOY);
    assert.deepEqual(r.totales, []);
    assert.equal(r.cantidad_activas, 0);
    assert.deepEqual(r.por_categoria, []);
    assert.deepEqual(r.proximos_cobros, []);
    assert.deepEqual(r.mas_caras, []);
    assert.deepEqual(r.ahorro, { totales: [], cantidad_canceladas: 0, canceladas: [] });
    assert.equal(r.gasto_mensual.length, 1);
    assert.equal(r.gasto_mensual[0].meses.length, 6);
  });

  it('ignora las canceladas en totales, categorías y calendario', () => {
    const r = calcularAnalisis([
      sus({ categoria: 'Streaming', monto: 38900, fecha_proximo_cobro: '2026-11-15' }),
      sus({ estado: 'cancelada', monto: 99999, fecha_proximo_cobro: '2026-11-15' }),
    ], [], [], HOY);
    assert.equal(r.totales[0].gasto_mensual, 38900);
    assert.equal(r.totales[0].proyeccion_anual, 38900 * 12);
    assert.deepEqual(r.por_categoria.map((c) => c.categoria), ['Streaming']);
    assert.equal(r.proximos_cobros.length, 1);
  });
});

describe('GET /api/analisis', () => {
  let app;
  let pool;

  before(async () => {
    await prepararBdPruebas();
    ({ app } = await import('../src/app.js'));
    ({ pool } = await import('../src/db.js'));
  });

  after(async () => {
    await pool?.end();
  });

  let contador = 0;
  async function crearUsuario() {
    contador += 1;
    const res = await request(app).post('/api/auth/registro').send({
      nombre: `Analisis ${contador}`, correo: `analisis${contador}@prueba.com`, password: 'secreta123',
    });
    return { Authorization: `Bearer ${res.body.token}` };
  }

  async function crear(auth, datos) {
    const res = await request(app).post('/api/suscripciones').set(auth).send({
      frecuencia: 'mensual', fecha_proximo_cobro: sumarDias(hoyColombia(), 5), ...datos,
    });
    assert.equal(res.status, 201, JSON.stringify(res.body));
    return res.body.suscripcion;
  }

  it('pide token', async () => {
    await request(app).get('/api/analisis').expect(401);
  });

  it('reúne los datos del usuario del token y nada de otros', async () => {
    const ana = await crearUsuario();
    const beto = await crearUsuario();
    const hoy = hoyColombia();

    const netflix = await crear(ana, { nombre_servicio: 'Netflix', categoria: 'Streaming', monto: 38900 });
    await crear(ana, { nombre_servicio: 'Spotify', categoria: 'Música', monto: 16900, fecha_proximo_cobro: sumarDias(hoy, 40) });
    await crear(ana, {
      nombre_servicio: 'Max', monto: 19900, es_prueba_gratis: true, fecha_fin_prueba: sumarDias(hoy, 3),
    });
    const canva = await crear(ana, { nombre_servicio: 'Canva', monto: 120000, frecuencia: 'anual' });
    await request(app).patch(`/api/suscripciones/${canva.id}/estado`).set(ana).send({ estado: 'cancelada' }).expect(200);
    await crear(beto, { nombre_servicio: 'De Beto', monto: 99999 });
    await pool.query('INSERT INTO historial_pagos (suscripcion_id, monto, fecha_pago) VALUES ($1, 38900, $2)', [netflix.id, hoy]);

    const { body } = await request(app).get('/api/analisis').set(ana).expect(200);

    assert.equal(body.cantidad_activas, 3);
    assert.deepEqual(body.totales, [{
      moneda: 'COP', gasto_mensual: 38900 + 16900, proyeccion_anual: (38900 + 16900) * 12, cantidad: 3,
    }]);
    assert.equal(body.gasto_mensual[0].meses[5].mes, hoy.slice(0, 7));
    assert.equal(body.gasto_mensual[0].meses[5].total, 38900);
    assert.deepEqual(body.por_categoria.map((c) => c.categoria).filter(Boolean).sort(), ['Música', 'Streaming']);
    // Spotify cobra en 40 días: fuera del calendario. Max pasa a pago en 3.
    assert.deepEqual(body.proximos_cobros.map((c) => [c.nombre_servicio, c.dias_restantes, c.fin_de_prueba]), [
      ['Max', 3, true], ['Netflix', 5, false],
    ]);
    assert.deepEqual(body.mas_caras.map((s) => s.nombre_servicio), ['Netflix', 'Spotify']);
    assert.equal(body.ahorro.cantidad_canceladas, 1);
    assert.deepEqual(body.ahorro.totales, [{ moneda: 'COP', ahorro_anual: 120000, ahorro_mensual: 10000, cantidad: 1 }]);
    assert.equal(body.ahorro.canceladas[0].nombre_servicio, 'Canva');

    const deBeto = (await request(app).get('/api/analisis').set(beto).expect(200)).body;
    assert.deepEqual(deBeto.mas_caras.map((s) => s.nombre_servicio), ['De Beto']);
    assert.equal(deBeto.ahorro.cantidad_canceladas, 0);
  });
});
