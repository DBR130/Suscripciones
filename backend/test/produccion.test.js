// Preparación para producción (Render + Neon, ver docs/despliegue.md).
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { after, before, describe, it } from 'node:test';

import request from 'supertest';

import { prepararBdPruebas } from './helpers/bd.js';
import { migracionesPendientes } from '../db/migrar.js';

const RAIZ = path.join(import.meta.dirname, '..');
const MIGRACIONES = fs.readdirSync(path.join(RAIZ, 'db/migraciones')).filter((f) => /^\d{3}_.+\.sql$/.test(f)).sort();
const PAQUETE = JSON.parse(fs.readFileSync(path.join(RAIZ, 'package.json'), 'utf8'));

// Lo que importa src/db.js se carga después de prepararBdPruebas() (ver
// test/helpers/bd.js y el candado de pruebas).
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

describe('scripts sin .env (Render)', () => {
  it('start, dev y db:* usan --env-file-if-exists; los :nube, .env.produccion', () => {
    for (const nombre of ['start', 'dev', 'db:migrate', 'db:guias', 'db:demo']) {
      assert.match(PAQUETE.scripts[nombre], /--env-file-if-exists=\.env /, nombre);
    }
    for (const nombre of ['db:migrate:nube', 'db:guias:nube', 'db:demo:nube']) {
      assert.match(PAQUETE.scripts[nombre], /--env-file=\.env\.produccion /, nombre);
    }
  });

  it('.env y .env.produccion están en .gitignore', () => {
    const ignorados = fs.readFileSync(path.join(RAIZ, '../.gitignore'), 'utf8').split(/\r?\n/);
    assert.ok(ignorados.includes('backend/.env'));
    assert.ok(ignorados.includes('backend/.env.produccion'));
  });

  it('sin .env ni variables, el servidor explica qué falta (no se cae por el archivo)', () => {
    // En una carpeta sin .env y sin DATABASE_URL ni JWT_SECRET: así no puede
    // conectarse a ninguna base.
    const env = { ...process.env };
    delete env.DATABASE_URL;
    delete env.JWT_SECRET;
    const r = spawnSync(
      process.execPath,
      ['--env-file-if-exists=.env', path.join(RAIZ, 'src/server.js')],
      { cwd: fs.mkdtempSync(path.join(os.tmpdir(), 'sin-env-')), env, encoding: 'utf8' },
    );
    // Node avisa ".env not found. Continuing without it." y sigue: el error
    // que se ve es el del servidor, no el del archivo.
    assert.equal(r.status, 1);
    assert.match(r.stderr, /Continuing without it/);
    assert.match(r.stderr, /Falta la variable de entorno DATABASE_URL/);
  });
});

describe('migraciones pendientes (aviso al arrancar)', () => {
  it('sin la tabla de migraciones, todas están pendientes', async () => {
    const consultar = async () => ({ rows: [{ existe: false }] });
    assert.deepEqual(await migracionesPendientes(consultar), MIGRACIONES);
  });

  it('lista solo las que faltan', async () => {
    const consultar = async (sql) => (sql.includes('to_regclass')
      ? { rows: [{ existe: true }] }
      : { rows: MIGRACIONES.slice(0, -1).map((version) => ({ version })) });
    assert.deepEqual(await migracionesPendientes(consultar), MIGRACIONES.slice(-1));
  });

  it('en una base migrada no hay pendientes', async () => {
    assert.deepEqual(await migracionesPendientes((sql) => pool.query(sql)), []);
  });
});

describe('GET /api/health', () => {
  it('responde rápido y sin sesión', async () => {
    const inicio = Date.now();
    const res = await request(app).get('/api/health').expect(200);
    assert.deepEqual(res.body, { ok: true });
    assert.ok(Date.now() - inicio < 2000);
  });
});
