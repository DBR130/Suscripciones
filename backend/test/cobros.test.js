// Pruebas del registro automático de cobros, cambios de precio y avisos,
// contra la base de pruebas (subtrack_test).
import assert from 'node:assert/strict';
import { after, before, describe, it } from 'node:test';

import request from 'supertest';

import { prepararBdPruebas } from './helpers/bd.js';
import { hoyColombia, sumarDias } from '../src/utils/fechas.js';

let app;
let pool;
let procesarCobros;

before(async () => {
  await prepararBdPruebas();
  ({ app } = await import('../src/app.js'));
  ({ pool } = await import('../src/db.js'));
  ({ procesarCobros } = await import('../src/services/cobros.js'));
});

after(async () => {
  await pool?.end();
});

let contador = 0;
async function crearUsuario() {
  contador += 1;
  const res = await request(app).post('/api/auth/registro').send({
    nombre: `Cobros ${contador}`, correo: `cobros${contador}@prueba.com`, password: 'secreta123',
  });
  return { Authorization: `Bearer ${res.body.token}` };
}

async function crear(auth, datos) {
  const res = await request(app).post('/api/suscripciones').set(auth).send({
    nombre_servicio: 'Servicio', monto: 10000, frecuencia: 'mensual', ...datos,
  });
  assert.equal(res.status, 201, JSON.stringify(res.body));
  return res.body.suscripcion;
}

async function estado(id) {
  const s = (await pool.query(
    'SELECT fecha_proximo_cobro, es_prueba_gratis FROM suscripciones WHERE id = $1', [id],
  )).rows[0];
  const pagos = (await pool.query(
    'SELECT fecha_pago, monto FROM historial_pagos WHERE suscripcion_id = $1 ORDER BY fecha_pago', [id],
  )).rows;
  return { ...s, pagos };
}

describe('procesarCobros', () => {
  const HOY = '2026-03-15';

  it('registra el pago y avanza un ciclo (semanal, mensual, anual)', async () => {
    const auth = await crearUsuario();
    const semanal = await crear(auth, { frecuencia: 'semanal', fecha_proximo_cobro: '2026-03-15' });
    const mensual = await crear(auth, { frecuencia: 'mensual', fecha_proximo_cobro: '2026-03-10', monto: 38900 });
    const anual = await crear(auth, { frecuencia: 'anual', fecha_proximo_cobro: '2026-03-01' });
    const futura = await crear(auth, { fecha_proximo_cobro: '2026-03-16' });

    await procesarCobros(HOY);

    assert.equal((await estado(semanal.id)).fecha_proximo_cobro, '2026-03-22');
    const m = await estado(mensual.id);
    assert.equal(m.fecha_proximo_cobro, '2026-04-10');
    assert.deepEqual(m.pagos, [{ fecha_pago: '2026-03-10', monto: 38900 }]);
    assert.equal((await estado(anual.id)).fecha_proximo_cobro, '2027-03-01');
    const f = await estado(futura.id);
    assert.equal(f.fecha_proximo_cobro, '2026-03-16');
    assert.deepEqual(f.pagos, []);
  });

  it('registra todos los ciclos atrasados y respeta el fin de mes', async () => {
    const auth = await crearUsuario();
    const s = await crear(auth, { frecuencia: 'mensual', fecha_proximo_cobro: '2025-12-31' });

    await procesarCobros(HOY);

    const e = await estado(s.id);
    assert.deepEqual(e.pagos.map((p) => p.fecha_pago), ['2025-12-31', '2026-01-31', '2026-02-28']);
    assert.equal(e.fecha_proximo_cobro, '2026-03-28');
  });

  it('es idempotente: correrlo dos veces no duplica pagos', async () => {
    const auth = await crearUsuario();
    const s = await crear(auth, { frecuencia: 'semanal', fecha_proximo_cobro: '2026-02-20' });

    await procesarCobros(HOY);
    const primera = await estado(s.id);
    await procesarCobros(HOY);
    const segunda = await estado(s.id);

    assert.equal(primera.pagos.length, 4); // 20 feb, 27 feb, 6 mar, 13 mar
    assert.deepEqual(segunda, primera);
  });

  it('convierte la prueba gratis vencida y cobra; la vigente no se toca', async () => {
    const auth = await crearUsuario();
    const vencida = await crear(auth, {
      monto: 89900, es_prueba_gratis: true, fecha_fin_prueba: '2026-03-12', fecha_proximo_cobro: '2026-03-12',
    });
    const vigente = await crear(auth, {
      es_prueba_gratis: true, fecha_fin_prueba: '2026-03-20', fecha_proximo_cobro: '2026-03-10',
    });

    await procesarCobros(HOY);

    const v = await estado(vencida.id);
    assert.equal(v.es_prueba_gratis, false);
    assert.deepEqual(v.pagos, [{ fecha_pago: '2026-03-12', monto: 89900 }]);
    assert.equal(v.fecha_proximo_cobro, '2026-04-12');

    const g = await estado(vigente.id);
    assert.equal(g.es_prueba_gratis, true);
    assert.deepEqual(g.pagos, []);
  });

  it('no procesa las canceladas pero sí las marcadas para cancelar', async () => {
    const auth = await crearUsuario();
    const cancelada = await crear(auth, { fecha_proximo_cobro: '2026-03-01' });
    const marcada = await crear(auth, { fecha_proximo_cobro: '2026-03-01' });
    await request(app).patch(`/api/suscripciones/${cancelada.id}/estado`).set(auth).send({ estado: 'cancelada' });
    await request(app).patch(`/api/suscripciones/${marcada.id}/estado`).set(auth).send({ estado: 'marcada_para_cancelar' });

    await procesarCobros(HOY);

    assert.deepEqual((await estado(cancelada.id)).pagos, []);
    assert.equal((await estado(marcada.id)).pagos.length, 1);
  });

  it('el detalle muestra los pagos registrados y el total', async () => {
    const auth = await crearUsuario();
    const s = await crear(auth, { monto: 20000, fecha_proximo_cobro: '2026-01-15' });
    await procesarCobros(HOY);

    const { body } = await request(app).get(`/api/suscripciones/${s.id}`).set(auth).expect(200);
    assert.deepEqual(body.pagos.map((p) => p.fecha_pago), ['2026-03-15', '2026-02-15', '2026-01-15']);
    assert.equal(body.pagado_total, 60000);
  });
});

describe('cambios de precio', () => {
  it('PUT registra el cambio si el monto cambia y el detalle devuelve el último', async () => {
    const auth = await crearUsuario();
    const s = await crear(auth, { nombre_servicio: 'Adobe', monto: 41900, fecha_proximo_cobro: '2026-12-02' });
    const base = { nombre_servicio: 'Adobe', frecuencia: 'mensual', fecha_proximo_cobro: '2026-12-02' };

    const sinCambio = await request(app).get(`/api/suscripciones/${s.id}`).set(auth).expect(200);
    assert.equal(sinCambio.body.ultimo_cambio_precio, null);

    // Cambiar otro campo no es cambio de precio.
    await request(app).put(`/api/suscripciones/${s.id}`).set(auth).send({ ...base, monto: 41900, categoria: 'Software' }).expect(200);
    await request(app).put(`/api/suscripciones/${s.id}`).set(auth).send({ ...base, monto: '47900.00' }).expect(200);
    await request(app).put(`/api/suscripciones/${s.id}`).set(auth).send({ ...base, monto: 49900 }).expect(200);

    const { rows } = await pool.query(
      'SELECT monto_anterior, monto_nuevo FROM cambios_precio WHERE suscripcion_id = $1 ORDER BY id', [s.id],
    );
    assert.deepEqual(rows, [
      { monto_anterior: 41900, monto_nuevo: 47900 },
      { monto_anterior: 47900, monto_nuevo: 49900 },
    ]);

    const { body } = await request(app).get(`/api/suscripciones/${s.id}`).set(auth).expect(200);
    assert.equal(body.ultimo_cambio_precio.monto_anterior, 47900);
    assert.equal(body.ultimo_cambio_precio.monto_nuevo, 49900);
  });

  it('otro usuario no puede cambiar el precio (404) y no queda registro', async () => {
    const ana = await crearUsuario();
    const beto = await crearUsuario();
    const s = await crear(ana, { monto: 10000, fecha_proximo_cobro: '2026-12-02' });
    await request(app).put(`/api/suscripciones/${s.id}`).set(beto)
      .send({ nombre_servicio: 'X', monto: 1, frecuencia: 'mensual', fecha_proximo_cobro: '2026-12-02' })
      .expect(404);
    const { rows } = await pool.query('SELECT 1 FROM cambios_precio WHERE suscripcion_id = $1', [s.id]);
    assert.equal(rows.length, 0);
  });
});

describe('GET /api/avisos', () => {
  it('devuelve próximos cobros, fines de prueba y cambios de precio del usuario', async () => {
    const auth = await crearUsuario();
    const otro = await crearUsuario();
    const hoy = hoyColombia();
    await crear(auth, { nombre_servicio: 'Netflix', fecha_proximo_cobro: sumarDias(hoy, 2) });
    await crear(auth, { nombre_servicio: 'Lejana', fecha_proximo_cobro: sumarDias(hoy, 20) });
    await crear(auth, {
      nombre_servicio: 'GeForce', es_prueba_gratis: true,
      fecha_fin_prueba: sumarDias(hoy, 1), fecha_proximo_cobro: sumarDias(hoy, 1),
    });
    const adobe = await crear(auth, { nombre_servicio: 'Adobe', monto: 41900, fecha_proximo_cobro: sumarDias(hoy, 25) });
    await request(app).put(`/api/suscripciones/${adobe.id}`).set(auth)
      .send({ nombre_servicio: 'Adobe', monto: 47900, frecuencia: 'mensual', fecha_proximo_cobro: sumarDias(hoy, 25) });
    await crear(otro, { nombre_servicio: 'De otro', fecha_proximo_cobro: sumarDias(hoy, 1) });

    await request(app).get('/api/avisos').expect(401);
    const { body } = await request(app).get('/api/avisos').set(auth).expect(200);

    assert.equal(body.dias_anticipacion_recordatorio, 3);
    const porTipo = Object.fromEntries(body.avisos.map((a) => [a.nombre_servicio, a.tipo]));
    assert.deepEqual(porTipo, { Netflix: 'proximo_cobro', GeForce: 'fin_prueba_gratis', Adobe: 'cambio_precio' });
    const cambio = body.avisos.find((a) => a.tipo === 'cambio_precio');
    assert.equal(cambio.monto_anterior, 41900);
    assert.equal(cambio.monto, 47900);
    assert.equal(cambio.fecha, hoy);
  });
});
