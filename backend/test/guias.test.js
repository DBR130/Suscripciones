// Guías de cancelación: coincidencia por nombre (pura) y endpoints (con BD).
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { after, before, describe, it } from 'node:test';

import request from 'supertest';

import { prepararBdPruebas } from './helpers/bd.js';
import { cargarGuias, validarGuias } from '../db/cargar-guias.js';
import { buscarGuia, normalizar } from '../src/services/guias.js';

const GUIAS = JSON.parse(fs.readFileSync(path.join(import.meta.dirname, '../db/guias.json'), 'utf8'));
const guiaPara = (nombre) => buscarGuia(nombre, GUIAS);

describe('normalizar y buscarGuia', () => {
  it('normaliza mayúsculas, tildes, signos y "+"', () => {
    assert.equal(normalizar('  Música  Premium! '), 'musica premium');
    assert.equal(normalizar('Disney+'), 'disney plus');
    assert.equal(normalizar('Apple TV+'), 'apple tv plus');
    assert.equal(normalizar('Microsoft-365'), 'microsoft 365');
  });

  it('encuentra por nombre sin importar mayúsculas ni tildes', () => {
    assert.equal(guiaPara('NETFLIX').guia.nombre_servicio, 'Netflix');
    assert.equal(guiaPara('spótify').guia.nombre_servicio, 'Spotify');
    assert.equal(guiaPara('Disney+').guia.nombre_servicio, 'Disney+');
  });

  it('encuentra por alias', () => {
    assert.equal(guiaPara('HBO Max').guia.nombre_servicio, 'Max');
    assert.equal(guiaPara('Disney Plus').guia.nombre_servicio, 'Disney+');
    assert.equal(guiaPara('iCloud+').guia.nombre_servicio, 'Apple');
    assert.equal(guiaPara('Office 365').guia.nombre_servicio, 'Microsoft 365');
    assert.equal(guiaPara('Adobe Photoshop').guia.nombre_servicio, 'Adobe');
  });

  it('Claude se encuentra también como Anthropic (detección de pagos)', () => {
    assert.equal(guiaPara('Claude Pro').guia.nombre_servicio, 'Claude');
    assert.equal(guiaPara('Anthropic').guia.nombre_servicio, 'Claude');
    assert.equal(guiaPara('ANTHROPIC* CLAUDE SUB').guia.nombre_servicio, 'Claude');
  });

  it('acepta el nombre con el plan', () => {
    assert.equal(guiaPara('Netflix Estándar').guia.nombre_servicio, 'Netflix');
    assert.equal(guiaPara('Spotify Premium Familiar').guia.nombre_servicio, 'Spotify');
    assert.equal(guiaPara('Smart Fit Plan Black').guia.nombre_servicio, 'Smart Fit');
    assert.equal(guiaPara('Plan Google One 100 GB').guia.nombre_servicio, 'Google One');
  });

  it('no confunde palabras sueltas y prefiere la coincidencia más larga', () => {
    // "max" está dentro de "maxima" pero no como palabra completa.
    assert.equal(guiaPara('Revista Maxima').esGenerica, true);
    // "Apple TV+" (alias más largo) gana sobre "Apple".
    assert.equal(guiaPara('Apple TV+ mensual').guia.nombre_servicio, 'Apple');
  });

  it('sin coincidencia devuelve la genérica', () => {
    const r = guiaPara('El Tiempo Digital');
    assert.equal(r.esGenerica, true);
    assert.equal(r.guia.nombre_servicio, 'Otro servicio');
  });
});

describe('guias.json', () => {
  it('es válido y tiene entre 15 y 20 servicios más la genérica', () => {
    validarGuias(GUIAS);
    const especificas = GUIAS.filter((g) => !g.es_generica);
    assert.ok(especificas.length >= 15 && especificas.length <= 20, `hay ${especificas.length}`);
    for (const g of GUIAS) {
      assert.ok(g.pasos.length >= 3 && g.pasos.length <= 5, `${g.nombre_servicio}: ${g.pasos.length} pasos`);
    }
  });

  it('validarGuias rechaza datos mal formados', () => {
    assert.throws(() => validarGuias([{ nombre_servicio: 'X', pasos: 'no es arreglo', es_generica: true }]));
    assert.throws(() => validarGuias([{ nombre_servicio: 'X', pasos: ['a'] }]), /genérica|generica/);
    assert.throws(() => validarGuias([
      { nombre_servicio: 'X', pasos: ['a'], es_generica: true, enlace_directo: 'http://inseguro.com' },
    ]), /https/);
  });
});

describe('endpoints de guías', () => {
  let app;
  let pool;

  before(async () => {
    await prepararBdPruebas();
    ({ app } = await import('../src/app.js'));
    ({ pool } = await import('../src/db.js'));
    await cargarGuias(process.env.DATABASE_URL, GUIAS);
  });

  after(async () => {
    await pool?.end();
  });

  let contador = 0;
  async function crearUsuario() {
    contador += 1;
    const res = await request(app).post('/api/auth/registro').send({
      nombre: `Guias ${contador}`, correo: `guias${contador}@prueba.com`, password: 'secreta123',
    });
    return { Authorization: `Bearer ${res.body.token}` };
  }

  async function crear(auth, nombre) {
    const res = await request(app).post('/api/suscripciones').set(auth)
      .send({ nombre_servicio: nombre, monto: 10000, frecuencia: 'mensual', fecha_proximo_cobro: '2026-12-01' });
    return res.body.suscripcion;
  }

  it('db:guias es idempotente: la segunda vez no cambia nada', async () => {
    const cambios = await cargarGuias(process.env.DATABASE_URL, GUIAS);
    assert.equal(cambios, 0);
    const { rows } = await pool.query('SELECT count(*)::int AS n FROM guias_cancelacion');
    assert.equal(rows[0].n, GUIAS.length);

    // Si cambia una guía, solo esa se actualiza.
    const editadas = GUIAS.map((g) => (g.nombre_servicio === 'Netflix' ? { ...g, duracion_minutos: 4 } : g));
    assert.equal(await cargarGuias(process.env.DATABASE_URL, editadas), 1);
    await cargarGuias(process.env.DATABASE_URL, GUIAS);
  });

  it('GET /api/guias lista nombre y alias, sin la genérica', async () => {
    const auth = await crearUsuario();
    await request(app).get('/api/guias').expect(401);
    const { body } = await request(app).get('/api/guias').set(auth).expect(200);
    assert.equal(body.guias.length, GUIAS.length - 1);
    const max = body.guias.find((g) => g.nombre_servicio === 'Max');
    assert.deepEqual(max.alias, ['HBO Max', 'HBO']);
  });

  it('GET /api/suscripciones/:id/guia encuentra la guía o la genérica', async () => {
    const auth = await crearUsuario();
    const netflix = await crear(auth, 'Netflix Estándar');
    const rara = await crear(auth, 'Periódico El Tiempo');

    const r1 = await request(app).get(`/api/suscripciones/${netflix.id}/guia`).set(auth).expect(200);
    assert.equal(r1.body.es_generica, false);
    assert.equal(r1.body.guia.nombre_servicio, 'Netflix');
    assert.ok(Array.isArray(r1.body.guia.pasos)); // JSONB llega como arreglo
    assert.equal(r1.body.suscripcion.nombre_servicio, 'Netflix Estándar');

    const r2 = await request(app).get(`/api/suscripciones/${rara.id}/guia`).set(auth).expect(200);
    assert.equal(r2.body.es_generica, true);
    assert.equal(r2.body.guia.nombre_servicio, 'Otro servicio');
  });

  it('la guía de una suscripción ajena responde 404', async () => {
    const ana = await crearUsuario();
    const beto = await crearUsuario();
    const deAna = await crear(ana, 'Spotify');
    const res = await request(app).get(`/api/suscripciones/${deAna.id}/guia`).set(beto).expect(404);
    assert.equal(res.body.error, 'Suscripción no encontrada');
    await request(app).get('/api/suscripciones/abc/guia').set(beto).expect(404);
  });
});
