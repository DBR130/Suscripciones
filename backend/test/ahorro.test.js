// Ahorro: cálculo puro, GET /api/ahorro y el usuario de demostración.
import assert from 'node:assert/strict';
import { after, before, describe, it } from 'node:test';

import request from 'supertest';

import { prepararBdPruebas } from './helpers/bd.js';
import { CORREO_DEMO, PASSWORD_DEMO, crearDemo } from '../db/demo.js';
import { calcularAhorro, ultimosMeses } from '../src/services/ahorro.js';
import { hoyColombia, sumarDias } from '../src/utils/fechas.js';

describe('calcularAhorro', () => {
  const HOY = '2026-10-15';

  it('ultimosMeses devuelve 6 meses hasta el actual, cruzando el año', () => {
    assert.deepEqual(ultimosMeses(HOY), ['2026-05', '2026-06', '2026-07', '2026-08', '2026-09', '2026-10']);
    assert.deepEqual(ultimosMeses('2026-02-28'), ['2025-09', '2025-10', '2025-11', '2025-12', '2026-01', '2026-02']);
  });

  it('totales por moneda, lista de la más reciente a la más antigua', () => {
    const r = calcularAhorro([
      { id: 1, nombre_servicio: 'A', moneda: 'COP', fecha_cancelacion: '2026-08-01', ahorro_proyectado_anual: 262800 },
      { id: 2, nombre_servicio: 'B', moneda: 'USD', fecha_cancelacion: '2026-10-01', ahorro_proyectado_anual: 119.88 },
      { id: 3, nombre_servicio: 'C', moneda: 'COP', fecha_cancelacion: '2026-09-10', ahorro_proyectado_anual: 202800 },
    ], [], HOY);

    assert.deepEqual(r.totales, [
      { moneda: 'COP', ahorro_anual: 465600, ahorro_mensual: 38800, cantidad: 2 },
      { moneda: 'USD', ahorro_anual: 119.88, ahorro_mensual: 9.99, cantidad: 1 },
    ]);
    assert.equal(r.cantidad_canceladas, 3);
    assert.deepEqual(r.canceladas.map((c) => c.id), [2, 3, 1]);
  });

  it('evolución de 6 meses con 0 en los meses sin pagos, por moneda', () => {
    const r = calcularAhorro([], [
      { mes: '2026-06', moneda: 'COP', total: 100000 },
      { mes: '2026-10', moneda: 'COP', total: '58800' }, // SUM puede llegar como texto
      { mes: '2026-09', moneda: 'USD', total: 20 },
    ], HOY);

    assert.deepEqual(r.evolucion.map((e) => e.moneda), ['COP', 'USD']);
    assert.deepEqual(r.evolucion[0].meses.map((m) => m.total), [0, 100000, 0, 0, 0, 58800]);
    assert.deepEqual(r.evolucion[1].meses.map((m) => m.total), [0, 0, 0, 0, 20, 0]);
  });

  it('sin datos: sin totales y la gráfica COP en ceros', () => {
    const r = calcularAhorro([], [], HOY);
    assert.deepEqual(r.totales, []);
    assert.equal(r.evolucion.length, 1);
    assert.ok(r.evolucion[0].meses.every((m) => m.total === 0));
  });
});

describe('GET /api/ahorro y usuario demo', () => {
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
      nombre: `Ahorro ${contador}`, correo: `ahorro${contador}@prueba.com`, password: 'secreta123',
    });
    return { Authorization: `Bearer ${res.body.token}` };
  }

  async function crear(auth, datos) {
    const res = await request(app).post('/api/suscripciones').set(auth).send({
      frecuencia: 'mensual', fecha_proximo_cobro: '2026-12-01', ...datos,
    });
    return res.body.suscripcion;
  }

  it('suma las canceladas del usuario y arma la evolución con sus pagos', async () => {
    const ana = await crearUsuario();
    const beto = await crearUsuario();
    const hoy = hoyColombia();

    const netflix = await crear(ana, { nombre_servicio: 'Netflix', categoria: 'Streaming', monto: 38900 });
    const anual = await crear(ana, { nombre_servicio: 'Canva', monto: 120000, frecuencia: 'anual' });
    await crear(ana, { nombre_servicio: 'Activa', monto: 10000 });
    const deBeto = await crear(beto, { nombre_servicio: 'De Beto', monto: 99999 });

    for (const [auth, s] of [[ana, netflix], [ana, anual], [beto, deBeto]]) {
      await request(app).patch(`/api/suscripciones/${s.id}/estado`).set(auth).send({ estado: 'cancelada' }).expect(200);
    }
    // Pagos: uno este mes y otro hace más de 6 meses (no cuenta).
    await pool.query(
      `INSERT INTO historial_pagos (suscripcion_id, monto, fecha_pago) VALUES ($1, 38900, $2), ($1, 38900, $3)`,
      [netflix.id, hoy, sumarDias(hoy, -400)],
    );

    await request(app).get('/api/ahorro').expect(401);
    const { body } = await request(app).get('/api/ahorro').set(ana).expect(200);

    assert.deepEqual(body.totales, [
      { moneda: 'COP', ahorro_anual: 38900 * 12 + 120000, ahorro_mensual: 38900 + 10000, cantidad: 2 },
    ]);
    assert.equal(body.cantidad_canceladas, 2);
    assert.deepEqual(body.canceladas.map((c) => c.nombre_servicio).sort(), ['Canva', 'Netflix']);
    const n = body.canceladas.find((c) => c.nombre_servicio === 'Netflix');
    assert.equal(n.categoria, 'Streaming');
    assert.equal(n.fecha_cancelacion, hoy);

    const cop = body.evolucion[0];
    assert.equal(cop.moneda, 'COP');
    assert.equal(cop.meses.length, 6);
    assert.equal(cop.meses[5].mes, hoy.slice(0, 7));
    assert.equal(cop.meses[5].total, 38900);
    assert.equal(cop.meses.reduce((t, m) => t + m.total, 0), 38900);

    // Al reactivar, sale del ahorro.
    await request(app).patch(`/api/suscripciones/${anual.id}/estado`).set(ana).send({ estado: 'activa' }).expect(200);
    const despues = await request(app).get('/api/ahorro').set(ana).expect(200);
    assert.equal(despues.body.cantidad_canceladas, 1);
  });

  it('db:demo crea solo al usuario demo, es repetible y no toca a otros', async () => {
    const otro = await crearUsuario();
    const suyo = await crear(otro, { nombre_servicio: 'Mía', monto: 5000 });

    await crearDemo(process.env.DATABASE_URL);
    await crearDemo(process.env.DATABASE_URL); // reiniciar no duplica

    const { rows } = await pool.query('SELECT count(*)::int AS n FROM usuarios WHERE correo = $1', [CORREO_DEMO]);
    assert.equal(rows[0].n, 1);
    const intacta = await request(app).get(`/api/suscripciones/${suyo.id}`).set(otro).expect(200);
    assert.equal(intacta.body.suscripcion.nombre_servicio, 'Mía');

    // El demo entra con su contraseña y tiene datos para todas las pantallas.
    const login = await request(app).post('/api/auth/login').send({ correo: CORREO_DEMO, password: PASSWORD_DEMO }).expect(200);
    const demo = { Authorization: `Bearer ${login.body.token}` };

    const lista = (await request(app).get('/api/suscripciones').set(demo).expect(200)).body.suscripciones;
    assert.equal(lista.filter((s) => s.estado !== 'cancelada').length, 8);
    assert.ok(lista.some((s) => s.moneda === 'USD'));
    assert.ok(lista.some((s) => s.estado === 'marcada_para_cancelar'));
    const prueba = lista.find((s) => s.es_prueba_gratis);
    assert.equal(prueba.fecha_fin_prueba, sumarDias(hoyColombia(), 2));
    assert.ok(lista.some((s) => s.fecha_proximo_cobro === sumarDias(hoyColombia(), 1)));

    const ahorro = (await request(app).get('/api/ahorro').set(demo).expect(200)).body;
    assert.equal(ahorro.cantidad_canceladas, 2);
    assert.ok(ahorro.evolucion[0].meses.filter((m) => m.total > 0).length >= 5, 'la gráfica debe tener datos');

    const avisos = (await request(app).get('/api/avisos').set(demo).expect(200)).body.avisos;
    assert.ok(avisos.some((a) => a.tipo === 'cambio_precio'));

    // Pantalla 05: dos candidatos pendientes, con sus pagos detectados.
    const candidatos = (await request(app).get('/api/detecciones/candidatos').set(demo).expect(200)).body.candidatos;
    assert.deepEqual(candidatos.map((c) => [c.comercio_normalizado, c.num_pagos]).sort(), [['Bodytech', 3], ['Claude', 2]]);
    assert.equal(candidatos.find((c) => c.comercio_normalizado === 'Claude').fecha_ultimo_pago, sumarDias(hoyColombia(), -3));
  });
});
