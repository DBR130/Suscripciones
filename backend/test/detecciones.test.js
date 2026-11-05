// Detección automática: reglas puras y endpoints /api/detecciones, contra la
// base de pruebas (subtrack_test).
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { after, before, describe, it } from 'node:test';

import request from 'supertest';

import { prepararBdPruebas } from './helpers/bd.js';
import { cargarGuias } from '../db/cargar-guias.js';
import { hoyColombia } from '../src/utils/fechas.js';

const GUIAS = JSON.parse(fs.readFileSync(path.join(import.meta.dirname, '../db/guias.json'), 'utf8'));

// IMPORTANTE: nada que importe src/db.js (app, servicios) puede importarse
// arriba con "import": se cargaría antes de prepararBdPruebas() y se
// conectaría a la base real. Se importa después, en este before().
let app;
let pool;
let estimarFrecuencia;
let hayCambioDePrecio;
let mismoServicio;
let montosSimilares;
let siguienteCobro;

before(async () => {
  await prepararBdPruebas();
  ({ app } = await import('../src/app.js'));
  ({ pool } = await import('../src/db.js'));
  ({
    estimarFrecuencia, hayCambioDePrecio, mismoServicio, montosSimilares, siguienteCobro,
  } = await import('../src/services/detecciones.js'));
  await cargarGuias(process.env.DATABASE_URL, GUIAS);
});

after(async () => {
  await pool?.end();
});

describe('reglas de detección', () => {
  it('estima la frecuencia solo si todos los intervalos coinciden', () => {
    assert.equal(estimarFrecuencia(['2026-08-23', '2026-09-23', '2026-10-23']), 'mensual');
    assert.equal(estimarFrecuencia(['2026-01-31', '2026-02-28', '2026-03-31']), 'mensual');
    assert.equal(estimarFrecuencia(['2026-10-01', '2026-10-08', '2026-10-15']), 'semanal');
    assert.equal(estimarFrecuencia(['2025-10-20', '2026-10-20']), 'anual');
    // Irregular, mezcla de frecuencias, el mismo día o un solo pago: no.
    assert.equal(estimarFrecuencia(['2026-10-01', '2026-10-13']), null);
    assert.equal(estimarFrecuencia(['2026-09-01', '2026-10-01', '2026-10-08']), null);
    assert.equal(estimarFrecuencia(['2026-10-30', '2026-10-30']), null);
    assert.equal(estimarFrecuencia(['2026-10-30']), null);
  });

  it('montos similares (±10 %) y cambio de precio (más de 5 %)', () => {
    assert.ok(montosSimilares(99900, 95000));
    assert.ok(!montosSimilares(18900, 32000));
    // Cobro en USD convertido a COP: varía un poco cada mes, no es cambio de precio.
    assert.ok(!hayCambioDePrecio(68139.27, 69850.5));
    assert.ok(hayCambioDePrecio(26900, 29900));
  });

  it('reconoce el mismo servicio por nombre o por la guía del catálogo', () => {
    assert.ok(mismoServicio('Netflix Estándar', 'Netflix', GUIAS));
    assert.ok(mismoServicio('HBO Max', 'Max', GUIAS));
    assert.ok(mismoServicio('Claude Pro', 'Claude', GUIAS));
    assert.ok(!mismoServicio('Netflix', 'Spotify', GUIAS));
    assert.ok(!mismoServicio('Revista Maxima', 'Max', GUIAS));
  });

  it('el próximo cobro queda después de hoy', () => {
    assert.equal(siguienteCobro('2026-10-23', 'mensual', '2026-11-01'), '2026-11-23');
    assert.equal(siguienteCobro('2026-08-23', 'mensual', '2026-11-01'), '2026-11-23');
    assert.equal(siguienteCobro('2026-10-30', 'semanal', '2026-11-06'), '2026-11-13');
  });
});

describe('endpoints de detecciones', () => {
  let contador = 0;
  async function crearUsuario() {
    contador += 1;
    const res = await request(app).post('/api/auth/registro').send({
      nombre: `Detecta ${contador}`, correo: `detecta${contador}@prueba.com`, password: 'secreta123',
    });
    return { Authorization: `Bearer ${res.body.token}` };
  }

  let huellas = 0;
  function pago(datos = {}) {
    huellas += 1;
    return {
      huella: crypto.createHash('sha256').update(`prueba-${huellas}`).digest('hex'),
      comercio: 'GOOGLE *Crunchyroll',
      comercio_normalizado: 'Crunchyroll',
      monto: 19900,
      moneda: 'COP',
      fecha: '2026-10-23T07:20:00',
      banco: 'Bancolombia',
      ...datos,
    };
  }

  async function enviar(auth, pagos, estado = 200) {
    const res = await request(app).post('/api/detecciones/pagos').set(auth).send({ pagos }).expect(estado);
    return res.body;
  }

  async function candidatos(auth, query = '') {
    const res = await request(app).get(`/api/detecciones/candidatos${query}`).set(auth).expect(200);
    return res.body.candidatos;
  }

  async function crearSuscripcion(auth, datos) {
    const res = await request(app).post('/api/suscripciones').set(auth).send({
      monto: 26900, frecuencia: 'mensual', fecha_proximo_cobro: '2026-12-01', ...datos,
    }).expect(201);
    return res.body.suscripcion;
  }

  describe('validación', () => {
    it('pide sesión y un lote de pagos válido', async () => {
      await request(app).post('/api/detecciones/pagos').send({ pagos: [pago()] }).expect(401);
      const auth = await crearUsuario();
      await enviar(auth, [], 400);
      await enviar(auth, [pago({ huella: 'abc' })], 400);
      await enviar(auth, [pago({ monto: 0 })], 400);
      await enviar(auth, [pago({ moneda: 'EUR' })], 400);
      await enviar(auth, [pago({ fecha: '2026-02-30T10:00' })], 400);
      await enviar(auth, [pago({ fecha: '2026-10-23T07:20:00Z' })], 400);
      await enviar(auth, [pago({ comercio_normalizado: '  ' })], 400);
      await enviar(auth, [pago(), pago({ banco: '' })], 400);
      // Si un pago no es válido, no se guarda ninguno del lote.
      const { rows } = await pool.query('SELECT count(*)::int AS n FROM pagos_detectados');
      assert.equal(rows[0].n, 0);
    });

    it('rechaza el texto de la notificación (nunca debe llegar al servidor)', async () => {
      const auth = await crearUsuario();
      const { error } = await enviar(auth, [pago({ texto: 'Bancolombia: Compraste $19.900,00...' })], 400);
      assert.match(error, /texto/);
    });

    it('acepta la fecha como la manda Dart (con milisegundos)', async () => {
      const auth = await crearUsuario();
      const { resultados } = await enviar(auth, [pago({ fecha: '2026-10-23T07:20:00.000' })]);
      assert.equal(resultados[0].resultado, 'candidato_nuevo');
    });
  });

  describe('caso b: servicio conocido', () => {
    it('crea un candidato pendiente desde el primer pago', async () => {
      const auth = await crearUsuario();
      const { resultados, candidatos_nuevos: nuevos } = await enviar(auth, [pago()]);
      assert.equal(resultados[0].resultado, 'candidato_nuevo');
      assert.equal(nuevos.length, 1);
      assert.equal(nuevos[0].comercio_normalizado, 'Crunchyroll');
      assert.equal(nuevos[0].frecuencia_estimada, 'mensual');
      assert.equal(nuevos[0].es_servicio_conocido, true);

      const lista = await candidatos(auth);
      assert.equal(lista.length, 1);
      assert.equal(lista[0].num_pagos, 1);
      assert.equal(lista[0].fecha_ultimo_pago, '2026-10-23');
    });

    it('Claude (Nequi, con centavos) también es un servicio conocido', async () => {
      const auth = await crearUsuario();
      const { candidatos_nuevos: [c] } = await enviar(auth, [pago({
        comercio: 'ANTHROPIC* CLAUDE SUB', comercio_normalizado: 'Claude', monto: 68139.27,
        banco: 'Nequi', fecha: '2026-10-28T10:15:00',
      })]);
      assert.equal(c.comercio_normalizado, 'Claude');
      assert.equal(c.monto, 68139.27);
    });

    it('reconoce nombres pegados: YouTubePremium es YouTube Premium (T1)', async () => {
      const auth = await crearUsuario();
      const { candidatos_nuevos: [c] } = await enviar(auth, [pago({
        comercio: 'GOOGLE *YouTubePremium', comercio_normalizado: 'YouTubePremium', monto: 26900,
      })]);
      assert.equal(c?.comercio_normalizado, 'YouTube Premium');
      assert.equal(c.es_servicio_conocido, true);
    });

    it('servicios ambiguos (T2): sin señal, solo con patrón', async () => {
      const auth = await crearUsuario();
      // Pedido suelto de comida por Rappi: compra normal.
      const rappi = { comercio: 'RAPPI', comercio_normalizado: 'Rappi Pro' };
      let r = await enviar(auth, [pago({ ...rappi, monto: 32500, fecha: '2026-10-05T20:00:00' })]);
      assert.equal(r.resultados[0].resultado, 'compra_normal');

      // Un juego suelto de PlayStation: compra normal.
      r = await enviar(auth, [pago({
        comercio: 'PLAYSTATION NETWORK', comercio_normalizado: 'PlayStation Plus', monto: 259900,
      })]);
      assert.equal(r.resultados[0].resultado, 'compra_normal');

      // Dos cobros mensuales iguales de Rappi: candidato "Rappi Pro".
      r = await enviar(auth, [
        pago({ ...rappi, monto: 24900, fecha: '2026-09-05T06:00:00' }),
        pago({ ...rappi, monto: 24900, fecha: '2026-10-05T06:00:00' }),
      ]);
      assert.equal(r.candidatos_nuevos[0]?.comercio_normalizado, 'Rappi Pro');
      assert.equal(r.candidatos_nuevos[0].es_servicio_conocido, true);
    });

    it('un servicio ambiguo con señal se propone desde el primer pago (T2)', async () => {
      const auth = await crearUsuario();
      const r = await enviar(auth, [pago({ comercio: 'RAPPI PRO', comercio_normalizado: 'Rappi Pro', monto: 24900 })]);
      assert.equal(r.resultados[0].resultado, 'candidato_nuevo');
    });

    it('usa el nombre del catálogo aunque llegue una variante', async () => {
      const auth = await crearUsuario();
      const { candidatos_nuevos: [c] } = await enviar(auth, [pago({ comercio: 'HBO MAX', comercio_normalizado: 'HBO Max' })]);
      assert.equal(c.comercio_normalizado, 'Max');
    });
  });

  describe('no duplicar', () => {
    it('la misma huella se ignora y un nuevo cobro actualiza el mismo candidato', async () => {
      const auth = await crearUsuario();
      const primero = pago();
      await enviar(auth, [primero]);
      const repetido = await enviar(auth, [primero]);
      assert.equal(repetido.resultados[0].resultado, 'repetido');
      assert.equal(repetido.candidatos_nuevos.length, 0);

      // Mismo lote con la huella dos veces: la segunda es repetida.
      const otro = pago({ fecha: '2026-11-23T07:20:00', monto: 21900 });
      const lote = await enviar(auth, [otro, otro]);
      assert.deepEqual(lote.resultados.map((r) => r.resultado), ['candidato_actualizado', 'repetido']);

      const lista = await candidatos(auth);
      assert.equal(lista.length, 1);
      assert.equal(lista[0].num_pagos, 2);
      assert.equal(lista[0].monto, 21900); // el del último pago
      assert.equal(lista[0].fecha_ultimo_pago, '2026-11-23');
    });
  });

  describe('caso c: comercio desconocido', () => {
    it('DiDi Food con un solo pago (o pagos irregulares) es una compra normal', async () => {
      const auth = await crearUsuario();
      const didi = { comercio: 'DIDI FOOD', comercio_normalizado: 'Didi Food', monto: 18900 };
      let r = await enviar(auth, [pago({ ...didi, fecha: '2026-10-30T13:10:00' })]);
      assert.equal(r.resultados[0].resultado, 'compra_normal');
      r = await enviar(auth, [pago({ ...didi, fecha: '2026-11-02T20:00:00', monto: 17500 })]);
      assert.equal(r.resultados[0].resultado, 'compra_normal');
      assert.equal((await candidatos(auth)).length, 0);
    });

    it('con 2 pagos mensuales de monto similar crea el candidato', async () => {
      const auth = await crearUsuario();
      const gym = { comercio: 'BODYTECH*CHAPINERO', comercio_normalizado: 'Bodytech', banco: 'Davivienda' };
      // Llegan en desorden en el mismo lote: se procesan por fecha.
      const r = await enviar(auth, [
        pago({ ...gym, monto: 99900, fecha: '2026-10-05T06:00:00' }),
        pago({ ...gym, monto: 95000, fecha: '2026-09-05T06:00:00' }),
      ]);
      assert.deepEqual(r.resultados.map((x) => x.resultado), ['compra_normal', 'candidato_nuevo']);
      const [c] = r.candidatos_nuevos;
      assert.equal(c.comercio_normalizado, 'Bodytech');
      assert.equal(c.frecuencia_estimada, 'mensual');
      assert.equal(c.monto, 99900);
      assert.equal(c.es_servicio_conocido, false);
    });

    it('detecta la frecuencia semanal', async () => {
      const auth = await crearUsuario();
      const lavado = { comercio: 'LAVASECO EL SOL', comercio_normalizado: 'Lavaseco El Sol', monto: 15000 };
      const r = await enviar(auth, [
        pago({ ...lavado, fecha: '2026-10-03T09:00:00' }),
        pago({ ...lavado, fecha: '2026-10-10T09:00:00' }),
      ]);
      assert.equal(r.candidatos_nuevos[0].frecuencia_estimada, 'semanal');
    });

    it('montos muy distintos no cuentan como el mismo cobro', async () => {
      const auth = await crearUsuario();
      const tienda = { comercio: 'TIENDA X', comercio_normalizado: 'Tienda X' };
      const r = await enviar(auth, [
        pago({ ...tienda, monto: 20000, fecha: '2026-09-10T12:00:00' }),
        pago({ ...tienda, monto: 85000, fecha: '2026-10-10T12:00:00' }),
      ]);
      assert.equal(r.candidatos_nuevos.length, 0);
    });
  });

  describe('procesadores de pago (T3)', () => {
    // Formato del SMS real de Nequi: "Pagaste 19.900,00 en SERVICIOS WEB EBANX CO".
    const ebanx = {
      comercio: 'SERVICIOS WEB EBANX CO', comercio_normalizado: 'Servicios Web Ebanx Co', banco: 'Nequi',
      fecha_del_mensaje: false,
    };

    it('GET /api/guias entrega la lista de procesadores', async () => {
      const auth = await crearUsuario();
      const { body } = await request(app).get('/api/guias').set(auth).expect(200);
      const nombres = body.procesadores.map((p) => p.nombre);
      assert.ok(nombres.includes('EBANX') && nombres.includes('dLocal'));
      assert.ok(body.procesadores.find((p) => p.nombre === 'dLocal').alias.includes('dlo'));
    });

    it('un cobro suelto de un procesador es compra normal', async () => {
      const auth = await crearUsuario();
      const r = await enviar(auth, [pago({ ...ebanx, monto: 19900, fecha: '2026-09-16T12:43:00' })]);
      assert.equal(r.resultados[0].resultado, 'compra_normal');
    });

    it('dos series mensuales del mismo procesador con montos distintos son dos candidatos', async () => {
      const auth = await crearUsuario();
      const r = await enviar(auth, [
        pago({ ...ebanx, monto: 19900, fecha: '2026-09-16T12:43:00' }),
        pago({ ...ebanx, monto: 19900, fecha: '2026-10-16T12:44:00' }),
        pago({ ...ebanx, monto: 34900, fecha: '2026-09-20T09:10:00' }),
        pago({ ...ebanx, monto: 34900, fecha: '2026-10-20T09:11:00' }),
      ]);
      assert.equal(r.candidatos_nuevos.length, 2);
      const lista = (await candidatos(auth)).sort((a, b) => a.monto - b.monto);
      assert.deepEqual(
        lista.map((c) => [c.comercio_normalizado, c.procesador, c.monto, c.num_pagos, c.es_servicio_conocido]),
        [['EBANX', 'EBANX', 19900, 2, false], ['EBANX', 'EBANX', 34900, 2, false]],
      );
    });

    it('confirmado con su nombre real, los cobros siguientes del procesador se registran ahí (T4)', async () => {
      const auth = await crearUsuario();
      await enviar(auth, [
        pago({ ...ebanx, monto: 19900, fecha: '2026-09-16T12:43:00' }),
        pago({ ...ebanx, monto: 19900, fecha: '2026-10-16T12:44:00' }),
        pago({ ...ebanx, monto: 34900, fecha: '2026-09-20T09:10:00' }),
        pago({ ...ebanx, monto: 34900, fecha: '2026-10-20T09:11:00' }),
      ]);
      const c = (await candidatos(auth)).find((x) => x.monto === 19900);
      const { body } = await request(app).post(`/api/detecciones/candidatos/${c.id}/confirmar`).set(auth)
        .send({ nombre_servicio: 'Crunchyroll' }).expect(201);
      assert.equal(body.suscripcion.nombre_servicio, 'Crunchyroll');
      assert.equal(body.pagos_enlazados, 2); // solo los de $19.900

      let r = await enviar(auth, [pago({ ...ebanx, monto: 19900, fecha: '2026-11-16T12:40:00' })]);
      assert.equal(r.resultados[0].resultado, 'suscripcion_existente');
      assert.equal(r.resultados[0].suscripcion_id, body.suscripcion.id);

      r = await enviar(auth, [pago({ ...ebanx, monto: 34900, fecha: '2026-11-20T09:10:00' })]);
      assert.notEqual(r.resultados[0].resultado, 'suscripcion_existente');
    });
  });

  describe('caso a: suscripción existente', () => {
    it('registra el pago en el historial y el cambio de precio (RF08)', async () => {
      const auth = await crearUsuario();
      const s = await crearSuscripcion(auth, { nombre_servicio: 'Netflix Estándar', monto: 26900 });
      const netflix = { comercio: 'NETFLIX.COM', comercio_normalizado: 'Netflix' };

      let r = await enviar(auth, [pago({ ...netflix, monto: 26900, fecha: '2026-10-15T08:00:00' })]);
      assert.equal(r.resultados[0].resultado, 'suscripcion_existente');
      assert.equal(r.resultados[0].suscripcion_id, s.id);
      assert.equal(r.resultados[0].cambio_precio, false);
      assert.equal(r.candidatos_nuevos.length, 0);

      r = await enviar(auth, [pago({ ...netflix, monto: 29900, fecha: '2026-11-15T08:00:00' })]);
      assert.equal(r.resultados[0].cambio_precio, true);

      const detalle = (await request(app).get(`/api/suscripciones/${s.id}`).set(auth).expect(200)).body;
      assert.equal(detalle.suscripcion.monto, 29900);
      assert.deepEqual(detalle.pagos.map((p) => [p.fecha_pago, p.monto]), [
        ['2026-11-15', 29900], ['2026-10-15', 26900],
      ]);
      assert.equal(detalle.ultimo_cambio_precio.monto_anterior, 26900);
      assert.equal(detalle.ultimo_cambio_precio.monto_nuevo, 29900);
      // Ya es una suscripción: no se propone como candidato.
      assert.equal((await candidatos(auth)).length, 0);
    });

    it('una variación pequeña por tasa de cambio no es cambio de precio', async () => {
      const auth = await crearUsuario();
      const s = await crearSuscripcion(auth, { nombre_servicio: 'Claude Pro', monto: 68139.27 });
      const r = await enviar(auth, [pago({
        comercio: 'ANTHROPIC* CLAUDE SUB', comercio_normalizado: 'Claude', monto: 69850.5,
        fecha: '2026-11-28T10:00:00',
      })]);
      assert.equal(r.resultados[0].suscripcion_id, s.id);
      assert.equal(r.resultados[0].cambio_precio, false);
      const { rows } = await pool.query('SELECT monto FROM suscripciones WHERE id = $1', [s.id]);
      assert.equal(rows[0].monto, 68139.27);
    });

    it('no repite un cobro que el proceso automático ya registró (±3 días)', async () => {
      const auth = await crearUsuario();
      const s = await crearSuscripcion(auth, { nombre_servicio: 'Spotify', monto: 16900 });
      await pool.query('INSERT INTO historial_pagos (suscripcion_id, monto, fecha_pago) VALUES ($1, 16900, $2)', [s.id, '2026-10-10']);
      await enviar(auth, [pago({ comercio: 'PAYPAL *SPOTIFY', comercio_normalizado: 'Spotify', monto: 16900, fecha: '2026-10-11T03:00:00' })]);
      const { rows } = await pool.query('SELECT fecha_pago FROM historial_pagos WHERE suscripcion_id = $1', [s.id]);
      assert.deepEqual(rows.map((r) => r.fecha_pago), ['2026-10-10']);
    });

    it('un pago en otra moneda se enlaza sin tocar historial ni precio', async () => {
      const auth = await crearUsuario();
      const s = await crearSuscripcion(auth, { nombre_servicio: 'ChatGPT Plus', monto: 20, moneda: 'USD' });
      const r = await enviar(auth, [pago({ comercio: 'OPENAI *CHATGPT', comercio_normalizado: 'ChatGPT Plus', monto: 84000 })]);
      assert.equal(r.resultados[0].suscripcion_id, s.id);
      const historial = await pool.query('SELECT 1 FROM historial_pagos WHERE suscripcion_id = $1', [s.id]);
      assert.equal(historial.rowCount, 0);
      const { rows } = await pool.query('SELECT monto FROM suscripciones WHERE id = $1', [s.id]);
      assert.equal(rows[0].monto, 20);
    });
  });

  describe('confirmar y descartar', () => {
    it('confirmar crea la suscripción con origen notificacion y enlaza los pagos', async () => {
      const auth = await crearUsuario();
      await enviar(auth, [pago({ fecha: '2026-09-23T07:20:00' }), pago({ fecha: '2026-10-23T07:20:00' })]);
      const [c] = await candidatos(auth);

      // Datos corregidos: categoría y un monto distinto.
      const res = await request(app).post(`/api/detecciones/candidatos/${c.id}/confirmar`).set(auth)
        .send({ monto: 21900, categoria: 'Streaming' }).expect(201);
      const { suscripcion, candidato, pagos_enlazados: enlazados } = res.body;
      assert.equal(suscripcion.nombre_servicio, 'Crunchyroll');
      assert.equal(suscripcion.monto, 21900);
      assert.equal(suscripcion.frecuencia, 'mensual');
      assert.equal(suscripcion.categoria, 'Streaming');
      assert.equal(suscripcion.origen, 'notificacion');
      assert.ok(suscripcion.fecha_deteccion);
      assert.equal(suscripcion.fecha_proximo_cobro, siguienteCobro('2026-10-23', 'mensual', hoyColombia()));
      assert.equal(candidato.estado, 'confirmada');
      assert.equal(candidato.suscripcion_id, suscripcion.id);
      assert.equal(enlazados, 2);

      const detalle = (await request(app).get(`/api/suscripciones/${suscripcion.id}`).set(auth)).body;
      assert.equal(detalle.pagos.length, 2);

      // Ya confirmado: no se puede confirmar ni descartar otra vez.
      await request(app).post(`/api/detecciones/candidatos/${c.id}/confirmar`).set(auth).expect(409);
      await request(app).post(`/api/detecciones/candidatos/${c.id}/descartar`).set(auth).expect(409);

      // El siguiente cobro ya va a la suscripción (caso a).
      const r = await enviar(auth, [pago({ fecha: '2026-11-23T07:20:00', monto: 21900 })]);
      assert.equal(r.resultados[0].resultado, 'suscripcion_existente');
      assert.equal(r.resultados[0].suscripcion_id, suscripcion.id);
    });

    it('datos corregidos inválidos: 400 y el candidato sigue pendiente', async () => {
      const auth = await crearUsuario();
      const { candidatos_nuevos: [c] } = await enviar(auth, [pago()]);
      await request(app).post(`/api/detecciones/candidatos/${c.id}/confirmar`).set(auth)
        .send({ frecuencia: 'diaria' }).expect(400);
      await request(app).post(`/api/detecciones/candidatos/${c.id}/confirmar`).set(auth)
        .send({ monto: -5 }).expect(400);
      assert.equal((await candidatos(auth))[0].estado, 'pendiente');
      // Ninguna suscripción creada para este usuario.
      const { rows } = await pool.query(
        `SELECT count(*)::int AS n FROM suscripciones s JOIN usuarios u ON u.id = s.usuario_id
         WHERE u.correo = $1`,
        [`detecta${contador}@prueba.com`],
      );
      assert.equal(rows[0].n, 0);
    });

    it('cambiar la frecuencia recalcula el próximo cobro', async () => {
      const auth = await crearUsuario();
      const { candidatos_nuevos: [c] } = await enviar(auth, [pago({ fecha: '2026-10-23T07:20:00' })]);
      const res = await request(app).post(`/api/detecciones/candidatos/${c.id}/confirmar`).set(auth)
        .send({ frecuencia: 'anual' }).expect(201);
      assert.equal(res.body.suscripcion.fecha_proximo_cobro, siguienteCobro('2026-10-23', 'anual', hoyColombia()));
    });

    it('un comercio descartado no se vuelve a proponer', async () => {
      const auth = await crearUsuario();
      const { candidatos_nuevos: [c] } = await enviar(auth, [pago()]);
      const res = await request(app).post(`/api/detecciones/candidatos/${c.id}/descartar`).set(auth).expect(200);
      assert.equal(res.body.candidato.estado, 'descartada');
      assert.equal((await candidatos(auth)).length, 0);
      assert.equal((await candidatos(auth, '?estado=descartada')).length, 1);

      const r = await enviar(auth, [pago({ fecha: '2026-11-23T07:20:00' })]);
      assert.equal(r.resultados[0].resultado, 'comercio_descartado');
      assert.equal(r.candidatos_nuevos.length, 0);
      assert.equal((await candidatos(auth)).length, 0);
    });

    it('si se borra la suscripción confirmada, el comercio se vuelve a proponer', async () => {
      const auth = await crearUsuario();
      const { candidatos_nuevos: [c] } = await enviar(auth, [pago()]);
      const { suscripcion } = (await request(app).post(`/api/detecciones/candidatos/${c.id}/confirmar`).set(auth)).body;
      await request(app).delete(`/api/suscripciones/${suscripcion.id}`).set(auth).expect(204);

      const r = await enviar(auth, [pago({ fecha: '2026-11-23T07:20:00' })]);
      assert.equal(r.resultados[0].resultado, 'candidato_nuevo');
      assert.equal(r.candidatos_nuevos[0].id, c.id);
      assert.equal(r.candidatos_nuevos[0].estado, 'pendiente');
    });

    it('valida el estado del listado y el id', async () => {
      const auth = await crearUsuario();
      await request(app).get('/api/detecciones/candidatos?estado=otra').set(auth).expect(400);
      await request(app).post('/api/detecciones/candidatos/abc/confirmar').set(auth).expect(404);
      await request(app).post('/api/detecciones/candidatos/999999/descartar').set(auth).expect(404);
    });
  });

  describe('aislamiento entre usuarios', () => {
    it('nadie ve, confirma ni descarta candidatos de otro usuario', async () => {
      const ana = await crearUsuario();
      const beto = await crearUsuario();
      const p = pago();
      const { candidatos_nuevos: [c] } = await enviar(ana, [p]);

      assert.equal((await candidatos(beto)).length, 0);
      await request(app).post(`/api/detecciones/candidatos/${c.id}/confirmar`).set(beto).expect(404);
      await request(app).post(`/api/detecciones/candidatos/${c.id}/descartar`).set(beto).expect(404);
      assert.equal((await candidatos(ana))[0].estado, 'pendiente');

      // La huella es única por usuario: la de Ana no le afecta a Beto.
      const r = await enviar(beto, [p]);
      assert.equal(r.resultados[0].resultado, 'candidato_nuevo');
    });

    it('un pago no se cruza con suscripciones de otro usuario', async () => {
      const ana = await crearUsuario();
      const beto = await crearUsuario();
      await crearSuscripcion(ana, { nombre_servicio: 'Netflix' });
      const r = await enviar(beto, [pago({ comercio: 'NETFLIX.COM', comercio_normalizado: 'Netflix' })]);
      assert.equal(r.resultados[0].resultado, 'candidato_nuevo');
      assert.equal(r.resultados[0].suscripcion_id, null);
    });
  });

  describe('sin duplicados entre caminos (notificación, historial de SMS, compartir)', () => {
    const claude = {
      comercio: 'ANTHROPIC* CLAUDE SUB', comercio_normalizado: 'Claude', banco: 'Nequi', monto: 68139.27,
    };

    it('valida fecha_del_mensaje y compartido', async () => {
      const auth = await crearUsuario();
      await enviar(auth, [pago({ fecha_del_mensaje: 'no' })], 400);
      const res = await request(app).post('/api/detecciones/pagos').set(auth)
        .send({ pagos: [pago()], compartido: 'si' }).expect(400);
      assert.match(res.body.error, /compartido/);
      await request(app).post('/api/detecciones/pagos').set(auth)
        .send({ pagos: [pago(), pago()], compartido: true }).expect(400);
    });

    it('un SMS sin fecha (Nequi) que llega con segundos de diferencia es el mismo cobro', async () => {
      const auth = await crearUsuario();
      // Notificación: postTime. Historial de SMS: la hora de recepción, 18 s antes.
      let r = await enviar(auth, [pago({ ...claude, fecha: '2026-10-28T10:15:21', fecha_del_mensaje: false })]);
      assert.equal(r.resultados[0].resultado, 'candidato_nuevo');
      r = await enviar(auth, [pago({ ...claude, fecha: '2026-10-28T10:15:03', fecha_del_mensaje: false })]);
      assert.equal(r.resultados[0].resultado, 'repetido');

      // Fuera de la tolerancia (más de 5 minutos) es otro cobro.
      r = await enviar(auth, [pago({ ...claude, fecha: '2026-10-28T10:25:00', fecha_del_mensaje: false })]);
      assert.equal(r.resultados[0].resultado, 'candidato_actualizado');
      const { rows } = await pool.query(
        `SELECT count(*)::int AS n, bool_and(fecha_aproximada) AS aproximadas FROM pagos_detectados p
         JOIN usuarios u ON u.id = p.usuario_id WHERE u.correo = $1`,
        [`detecta${contador}@prueba.com`],
      );
      assert.deepEqual(rows[0], { n: 2, aproximadas: true });
    });

    it('con la fecha del propio mensaje en los dos, dos compras a minutos distintos son dos', async () => {
      const auth = await crearUsuario();
      const didi = { comercio: 'DIDI FOOD', comercio_normalizado: 'Didi Food', monto: 18900 };
      const r = await enviar(auth, [
        pago({ ...didi, fecha: '2026-10-30T13:10:00' }),
        pago({ ...didi, fecha: '2026-10-30T13:12:00' }),
      ]);
      assert.deepEqual(r.resultados.map((x) => x.resultado), ['compra_normal', 'compra_normal']);
    });

    it('un cobro compartido de un comercio desconocido se propone como suscripción', async () => {
      const auth = await crearUsuario();
      const gym = { comercio: 'GIMNASIO LA 80', comercio_normalizado: 'Gimnasio La 80', monto: 89900 };
      const res = await request(app).post('/api/detecciones/pagos').set(auth)
        .send({ pagos: [pago(gym)], compartido: true }).expect(200);
      assert.equal(res.body.resultados[0].resultado, 'candidato_nuevo');
      assert.equal(res.body.candidatos_nuevos[0].frecuencia_estimada, 'mensual');
      assert.equal(res.body.candidatos_nuevos[0].es_servicio_conocido, false);
    });
  });

  describe('retención: las compras normales no se quedan en el servidor', () => {
    async function pagosGuardados(auth) {
      const { rows } = await pool.query(
        `SELECT p.comercio_normalizado FROM pagos_detectados p
         WHERE p.usuario_id = (SELECT id FROM usuarios WHERE correo = $1) ORDER BY p.fecha`,
        [`detecta${auth.numero}@prueba.com`],
      );
      return rows.map((r) => r.comercio_normalizado);
    }

    async function usuarioNumerado() {
      const auth = await crearUsuario();
      return { auth, numero: contador };
    }

    it('una compra puntual se responde pero no se guarda', async () => {
      const u = await usuarioNumerado();
      const r = await enviar(u.auth, [pago({ comercio: 'DIDI FOOD', comercio_normalizado: 'Didi Food', monto: 18900 })]);
      assert.equal(r.resultados[0].resultado, 'compra_normal');
      assert.deepEqual(await pagosGuardados(u), []);
    });

    it('se conservan los pagos de candidatos y suscripciones, incluidos los alias del catálogo', async () => {
      const u = await usuarioNumerado();
      const gym = { comercio: 'BODYTECH*CHAPINERO', comercio_normalizado: 'Bodytech', banco: 'Davivienda', monto: 99900 };
      await enviar(u.auth, [
        pago({ ...gym, fecha: '2026-09-05T06:00:00' }),
        pago({ ...gym, fecha: '2026-10-05T06:00:00' }),
        // Servicio conocido con el nombre de un alias: el candidato queda como "Max".
        pago({ comercio: 'HBO MAX', comercio_normalizado: 'HBO Max', monto: 26900, fecha: '2026-10-10T08:00:00' }),
      ]);
      assert.deepEqual(await pagosGuardados(u), ['Bodytech', 'Bodytech', 'HBO Max']);
    });

    it('al descartar un candidato se borran sus pagos', async () => {
      const u = await usuarioNumerado();
      const { candidatos_nuevos: [c] } = await enviar(u.auth, [pago()]);
      assert.deepEqual(await pagosGuardados(u), ['Crunchyroll']);
      await request(app).post(`/api/detecciones/candidatos/${c.id}/descartar`).set(u.auth).expect(200);
      assert.deepEqual(await pagosGuardados(u), []);
    });

    it('la tarea diaria borra las compras normales de todos los usuarios', async () => {
      const u = await usuarioNumerado();
      const { rows: [usuario] } = await pool.query('SELECT id FROM usuarios WHERE correo = $1', [`detecta${u.numero}@prueba.com`]);
      // Una compra normal guardada antes de esta versión.
      await pool.query(
        `INSERT INTO pagos_detectados (usuario_id, comercio, comercio_normalizado, monto, moneda, fecha, banco, huella)
         VALUES ($1, 'DIDI FOOD', 'Didi Food', 18900, 'COP', '2026-10-30T13:10:00', 'Bancolombia', $2)`,
        [usuario.id, 'f'.repeat(64)],
      );
      const { transaccion } = await import('../src/db.js');
      const { purgarComprasNormales } = await import('../src/services/detecciones.js');
      const borrados = await transaccion((client) => purgarComprasNormales(client));
      assert.ok(borrados >= 1);
      assert.deepEqual(await pagosGuardados(u), []);
    });
  });
});
