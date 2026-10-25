// Pruebas de la API contra una base de datos de pruebas (subtrack_test).
// Ver test/helpers/bd.js: la base "subtrack" real nunca se toca.
import assert from 'node:assert/strict';
import { after, before, describe, it } from 'node:test';

import request from 'supertest';

import { prepararBdPruebas } from './helpers/bd.js';
import { hoyLocal } from '../src/utils/fechas.js';

// app.js y db.js se importan DESPUÉS de preparar la base, porque db.js lee
// DATABASE_URL en el momento de importarse.
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

// Fecha "AAAA-MM-DD" a `dias` de hoy.
function enDias(dias) {
  const d = new Date();
  d.setDate(d.getDate() + dias);
  return hoyLocal(d);
}

let contador = 0;
async function crearUsuario() {
  contador += 1;
  const res = await request(app).post('/api/auth/registro').send({
    nombre: `Usuario ${contador}`,
    correo: `usuario${contador}@prueba.com`,
    password: 'secreta123',
  });
  assert.equal(res.status, 201);
  return { token: res.body.token, auth: { Authorization: `Bearer ${res.body.token}` } };
}

const NETFLIX = {
  nombre_servicio: 'Netflix',
  monto: 38900,
  frecuencia: 'mensual',
  fecha_proximo_cobro: '2026-12-20',
};

async function crearSuscripcion(usuario, datos = NETFLIX) {
  const res = await request(app).post('/api/suscripciones').set(usuario.auth).send(datos);
  assert.equal(res.status, 201, JSON.stringify(res.body));
  return res.body.suscripcion;
}

describe('suscripciones', () => {
  it('exige token', async () => {
    const res = await request(app).get('/api/suscripciones');
    assert.equal(res.status, 401);
  });

  it('crea con valores por defecto y devuelve tipos correctos', async () => {
    const ana = await crearUsuario();
    const s = await crearSuscripcion(ana);

    assert.equal(s.nombre_servicio, 'Netflix');
    assert.equal(s.monto, 38900); // número, no "38900.00"
    assert.equal(s.moneda, 'COP');
    assert.equal(s.fecha_proximo_cobro, '2026-12-20'); // sin hora ni zona horaria
    assert.equal(s.estado, 'activa');
    assert.equal(s.origen, 'manual');
    assert.equal(s.dias_aviso, null);
    assert.equal(s.categoria, null);
    assert.equal(s.usuario_id, undefined);
  });

  it('valida los campos en el servidor', async () => {
    const ana = await crearUsuario();
    const casos = [
      { nombre_servicio: '' },
      { nombre_servicio: 'x'.repeat(101) },
      { monto: -1 },
      { monto: 10.123 },
      { monto: '12abc' },
      { monto: 12345678901 },
      { moneda: 'EUR' },
      { frecuencia: 'diaria' },
      { fecha_proximo_cobro: '2026-02-30' },
      { fecha_proximo_cobro: '20/12/2026' },
      { es_prueba_gratis: true }, // falta fecha_fin_prueba
      { es_prueba_gratis: 'si' },
      { dias_aviso: 31 },
      { dias_aviso: 2.5 },
      { origen: 'otro' },
      { categoria: 'Videojuegos' },
      { categoria: 'streaming' }, // distingue mayúsculas
    ];
    for (const cambio of casos) {
      const res = await request(app).post('/api/suscripciones').set(ana.auth).send({ ...NETFLIX, ...cambio });
      assert.equal(res.status, 400, `debió rechazar ${JSON.stringify(cambio)}`);
      assert.ok(res.body.error);
    }
  });

  it('guarda, edita y quita la categoría', async () => {
    const ana = await crearUsuario();
    const s = await crearSuscripcion(ana, { ...NETFLIX, categoria: 'Streaming' });
    assert.equal(s.categoria, 'Streaming');

    const musica = await request(app).put(`/api/suscripciones/${s.id}`).set(ana.auth)
      .send({ ...NETFLIX, categoria: 'Música' }).expect(200);
    assert.equal(musica.body.suscripcion.categoria, 'Música');

    // "" o ausente = sin categoría.
    const sin = await request(app).put(`/api/suscripciones/${s.id}`).set(ana.auth)
      .send({ ...NETFLIX, categoria: '' }).expect(200);
    assert.equal(sin.body.suscripcion.categoria, null);
  });

  it('el detalle incluye los 3 últimos pagos y el total pagado', async () => {
    const ana = await crearUsuario();
    const s = await crearSuscripcion(ana);
    const vacia = await request(app).get(`/api/suscripciones/${s.id}`).set(ana.auth).expect(200);
    assert.deepEqual(vacia.body.pagos, []);
    assert.equal(vacia.body.pagado_total, 0);

    await pool.query(
      `INSERT INTO historial_pagos (suscripcion_id, monto, fecha_pago) VALUES
       ($1, 35900, '2026-07-20'), ($1, 38900, '2026-08-20'), ($1, 38900, '2026-09-20'), ($1, 38900, '2026-10-20')`,
      [s.id],
    );
    const { body } = await request(app).get(`/api/suscripciones/${s.id}`).set(ana.auth).expect(200);
    assert.deepEqual(body.pagos, [
      { fecha_pago: '2026-10-20', monto: 38900 },
      { fecha_pago: '2026-09-20', monto: 38900 },
      { fecha_pago: '2026-08-20', monto: 38900 },
    ]);
    assert.equal(body.pagado_total, 35900 + 38900 * 3);
  });

  it('acepta montos con 2 decimales y pruebas gratis', async () => {
    const ana = await crearUsuario();
    const s = await crearSuscripcion(ana, {
      ...NETFLIX, monto: '12.99', moneda: 'USD', es_prueba_gratis: true,
      fecha_fin_prueba: '2026-12-01', dias_aviso: 7,
    });
    assert.equal(s.monto, 12.99);
    assert.equal(s.fecha_fin_prueba, '2026-12-01');
    assert.equal(s.dias_aviso, 7);
  });

  it('lista, filtra por estado y ordena por próximo cobro', async () => {
    const ana = await crearUsuario();
    const tarde = await crearSuscripcion(ana, { ...NETFLIX, nombre_servicio: 'B', fecha_proximo_cobro: '2026-12-30' });
    const pronto = await crearSuscripcion(ana, { ...NETFLIX, nombre_servicio: 'A', fecha_proximo_cobro: '2026-12-01' });
    await request(app).patch(`/api/suscripciones/${tarde.id}/estado`).set(ana.auth)
      .send({ estado: 'cancelada' }).expect(200);

    const todas = await request(app).get('/api/suscripciones').set(ana.auth).expect(200);
    assert.deepEqual(todas.body.suscripciones.map((s) => s.id), [pronto.id, tarde.id]);

    const activas = await request(app).get('/api/suscripciones?estado=activa').set(ana.auth).expect(200);
    assert.deepEqual(activas.body.suscripciones.map((s) => s.id), [pronto.id]);

    await request(app).get('/api/suscripciones?estado=borrada').set(ana.auth).expect(400);
  });

  it('edita, cambia de estado y elimina', async () => {
    const ana = await crearUsuario();
    const s = await crearSuscripcion(ana);

    const editada = await request(app).put(`/api/suscripciones/${s.id}`).set(ana.auth)
      .send({ ...NETFLIX, monto: 44900, frecuencia: 'anual' }).expect(200);
    assert.equal(editada.body.suscripcion.monto, 44900);
    assert.equal(editada.body.suscripcion.frecuencia, 'anual');

    const marcada = await request(app).patch(`/api/suscripciones/${s.id}/estado`).set(ana.auth)
      .send({ estado: 'marcada_para_cancelar' }).expect(200);
    assert.equal(marcada.body.suscripcion.estado, 'marcada_para_cancelar');
    await request(app).patch(`/api/suscripciones/${s.id}/estado`).set(ana.auth)
      .send({ estado: 'pausada' }).expect(400);

    await request(app).delete(`/api/suscripciones/${s.id}`).set(ana.auth).expect(204);
    await request(app).get(`/api/suscripciones/${s.id}`).set(ana.auth).expect(404);
  });

  it('al cancelar guarda el ahorro anual y al reactivar lo borra', async () => {
    const ana = await crearUsuario();
    const s = await crearSuscripcion(ana);

    await request(app).patch(`/api/suscripciones/${s.id}/estado`).set(ana.auth).send({ estado: 'cancelada' }).expect(200);
    let { rows } = await pool.query('SELECT ahorro_proyectado_anual FROM cancelaciones WHERE suscripcion_id = $1', [s.id]);
    assert.deepEqual(rows, [{ ahorro_proyectado_anual: 38900 * 12 }]);

    await request(app).patch(`/api/suscripciones/${s.id}/estado`).set(ana.auth).send({ estado: 'activa' }).expect(200);
    ({ rows } = await pool.query('SELECT 1 FROM cancelaciones WHERE suscripcion_id = $1', [s.id]));
    assert.equal(rows.length, 0);
  });

  it('ids inválidos responden 404', async () => {
    const ana = await crearUsuario();
    for (const id of ['abc', '0', '-1', '1.5', '99999999999']) {
      await request(app).get(`/api/suscripciones/${id}`).set(ana.auth).expect(404);
    }
  });
});

describe('aislamiento entre usuarios', () => {
  it('un usuario no puede ver, editar, cambiar ni borrar suscripciones de otro', async () => {
    const ana = await crearUsuario();
    const beto = await crearUsuario();
    const deAna = await crearSuscripcion(ana);
    const ruta = `/api/suscripciones/${deAna.id}`;

    // 404 (no 403): Beto no debe saber que la suscripción existe.
    const ver = await request(app).get(ruta).set(beto.auth);
    assert.equal(ver.status, 404);
    assert.equal(ver.body.error, 'Suscripción no encontrada');
    await request(app).put(ruta).set(beto.auth).send({ ...NETFLIX, monto: 1 }).expect(404);
    await request(app).patch(`${ruta}/estado`).set(beto.auth).send({ estado: 'cancelada' }).expect(404);
    await request(app).delete(ruta).set(beto.auth).expect(404);

    const lista = await request(app).get('/api/suscripciones').set(beto.auth).expect(200);
    assert.deepEqual(lista.body.suscripciones, []);
    const resumen = await request(app).get('/api/resumen').set(beto.auth).expect(200);
    assert.equal(resumen.body.cantidad_activas, 0);

    // La de Ana sigue intacta.
    const intacta = await request(app).get(ruta).set(ana.auth).expect(200);
    assert.equal(intacta.body.suscripcion.monto, 38900);
    assert.equal(intacta.body.suscripcion.estado, 'activa');
  });
});

describe('resumen', () => {
  it('calcula totales por moneda, próximos cobros y pruebas por terminar', async () => {
    const ana = await crearUsuario();
    await crearSuscripcion(ana, { ...NETFLIX, categoria: 'Streaming', monto: 38900, fecha_proximo_cobro: enDias(2) });
    await crearSuscripcion(ana, { ...NETFLIX, nombre_servicio: 'Canva', categoria: 'Diseño', monto: 240000, frecuencia: 'anual', fecha_proximo_cobro: enDias(90) });
    await crearSuscripcion(ana, { ...NETFLIX, nombre_servicio: 'ChatGPT', monto: 20, moneda: 'USD', fecha_proximo_cobro: enDias(20) });
    await crearSuscripcion(ana, { ...NETFLIX, nombre_servicio: 'GeForce', monto: 89900, es_prueba_gratis: true,
      fecha_fin_prueba: enDias(3), fecha_proximo_cobro: enDias(3) });
    const cancelada = await crearSuscripcion(ana, { ...NETFLIX, nombre_servicio: 'Vieja', monto: 50000, fecha_proximo_cobro: enDias(1) });
    await request(app).patch(`/api/suscripciones/${cancelada.id}/estado`).set(ana.auth).send({ estado: 'cancelada' });

    const { body } = await request(app).get('/api/resumen').set(ana.auth).expect(200);

    assert.deepEqual(body.totales, [
      { moneda: 'COP', gasto_mensual: 38900 + 20000, proyeccion_anual: 38900 * 12 + 240000, cantidad: 3 },
      { moneda: 'USD', gasto_mensual: 20, proyeccion_anual: 240, cantidad: 1 },
    ]);
    assert.deepEqual(body.por_categoria, [
      { categoria: 'Streaming', moneda: 'COP', gasto_mensual: 38900, cantidad: 1 },
      { categoria: 'Diseño', moneda: 'COP', gasto_mensual: 20000, cantidad: 1 },
      { categoria: null, moneda: 'COP', gasto_mensual: 0, cantidad: 1 },
      { categoria: null, moneda: 'USD', gasto_mensual: 20, cantidad: 1 },
    ]);
    assert.equal(body.cantidad_activas, 4);
    assert.deepEqual(body.proximos_cobros.map((s) => [s.nombre_servicio, s.dias_restantes]), [['Netflix', 2]]);
    assert.deepEqual(body.pruebas_por_terminar.map((s) => [s.nombre_servicio, s.dias_restantes]), [['GeForce', 3]]);
    assert.equal(body.dias_anticipacion_recordatorio, 3);
  });
});

describe('usuario', () => {
  it('lee y cambia los días de anticipación', async () => {
    const ana = await crearUsuario();
    const antes = await request(app).get('/api/usuarios/me/preferencias').set(ana.auth).expect(200);
    assert.deepEqual(antes.body.preferencias, { dias_anticipacion_recordatorio: 3 });

    await request(app).put('/api/usuarios/me/preferencias').set(ana.auth)
      .send({ dias_anticipacion_recordatorio: 31 }).expect(400);
    const despues = await request(app).put('/api/usuarios/me/preferencias').set(ana.auth)
      .send({ dias_anticipacion_recordatorio: 7 }).expect(200);
    assert.deepEqual(despues.body.preferencias, { dias_anticipacion_recordatorio: 7 });
  });

  it('eliminar la cuenta exige la contraseña y borra todos sus datos', async () => {
    const ana = await crearUsuario();
    const beto = await crearUsuario();
    const s = await crearSuscripcion(ana);
    await crearSuscripcion(beto);
    await request(app).patch(`/api/suscripciones/${s.id}/estado`).set(ana.auth).send({ estado: 'cancelada' });

    await request(app).delete('/api/usuarios/me').set(ana.auth).send({}).expect(400);
    const mala = await request(app).delete('/api/usuarios/me').set(ana.auth).send({ password: 'otra-clave' });
    assert.equal(mala.status, 403);
    assert.equal(mala.body.error, 'Contraseña incorrecta');

    await request(app).delete('/api/usuarios/me').set(ana.auth).send({ password: 'secreta123' }).expect(204);

    // El token ya no sirve y no quedan datos de Ana.
    await request(app).get('/api/auth/me').set(ana.auth).expect(401);
    const { rows } = await pool.query(
      `SELECT (SELECT count(*) FROM suscripciones WHERE id = $1)::int AS suscripciones,
              (SELECT count(*) FROM cancelaciones WHERE suscripcion_id = $1)::int AS cancelaciones`,
      [s.id],
    );
    assert.deepEqual(rows[0], { suscripciones: 0, cancelaciones: 0 });

    // Los datos de Beto siguen ahí.
    const deBeto = await request(app).get('/api/suscripciones').set(beto.auth).expect(200);
    assert.equal(deBeto.body.suscripciones.length, 1);
  });
});
