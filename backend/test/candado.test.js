// Candado de la base de pruebas (src/utils/candadoBd.js): bajo tests nada
// puede conectarse a una base que no termine en "_test".
//
// Ninguna prueba se conecta de verdad: las URLs apuntan a 127.0.0.1:1, donde
// no hay nada. Si el candado fallara, el error sería de conexión y no el del
// candado, y la prueba lo detectaría.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import path from 'node:path';
import { describe, it } from 'node:test';

import { crearDemo } from '../db/demo.js';
import { cargarGuias } from '../db/cargar-guias.js';
import { migrar } from '../db/migrar.js';
import { corriendoTests, verificarBdPermitida } from '../src/utils/candadoBd.js';

const REAL = 'postgres://usuario:clave@127.0.0.1:1/subtrack';
const PRUEBAS = 'postgres://usuario:clave@127.0.0.1:1/subtrack_test';
const CANDADO = /Candado de pruebas/;
const GUIA = [{ nombre_servicio: 'Otro servicio', es_generica: true, pasos: ['Uno'] }];

describe('candado de la base de pruebas', () => {
  it('detecta que el proceso es un test', () => {
    assert.ok(corriendoTests()); // node --test define NODE_TEST_CONTEXT
    assert.ok(corriendoTests({ NODE_TEST_CONTEXT: 'child-v8' }));
    assert.ok(corriendoTests({ NODE_ENV: 'test' }));
    assert.ok(!corriendoTests({}));
    assert.ok(!corriendoTests({ NODE_ENV: 'development' }));
  });

  it('bajo tests solo deja pasar bases que terminen en "_test"', () => {
    assert.throws(() => verificarBdPermitida(REAL, { NODE_TEST_CONTEXT: 'child-v8' }), CANDADO);
    assert.throws(() => verificarBdPermitida(REAL, { NODE_ENV: 'test' }), CANDADO);
    assert.throws(() => verificarBdPermitida(undefined, { NODE_ENV: 'test' }), CANDADO);
    assert.throws(() => verificarBdPermitida('no es una url', { NODE_ENV: 'test' }), CANDADO);
    assert.doesNotThrow(() => verificarBdPermitida(PRUEBAS, { NODE_ENV: 'test' }));
    // Fuera de los tests (npm run dev, db:migrate) no interviene.
    assert.doesNotThrow(() => verificarBdPermitida(REAL, {}));
  });

  it('los scripts de db/ se niegan antes de conectar', async () => {
    await assert.rejects(migrar(REAL, () => {}), CANDADO);
    await assert.rejects(cargarGuias(REAL, GUIA), CANDADO);
    await assert.rejects(crearDemo(REAL), CANDADO);
  });

  it('src/db.js falla al importarse si apunta a la base real', () => {
    // En un proceso aparte, porque db.js lee DATABASE_URL al cargarse.
    const importar = (env) => spawnSync(
      process.execPath,
      ['--input-type=module', '-e', "await import('./src/db.js')"],
      { cwd: path.join(import.meta.dirname, '..'), env, encoding: 'utf8' },
    );
    const sinMarcas = { ...process.env };
    delete sinMarcas.NODE_TEST_CONTEXT;
    delete sinMarcas.NODE_ENV;

    for (const marca of [{ NODE_TEST_CONTEXT: 'child-v8' }, { NODE_ENV: 'test' }]) {
      const r = importar({ ...sinMarcas, ...marca, DATABASE_URL: REAL });
      assert.notEqual(r.status, 0, `debió fallar con ${JSON.stringify(marca)}`);
      assert.match(r.stderr, CANDADO);
    }
    // Con la base de pruebas, o fuera de los tests, se importa sin problema
    // (el pool no se conecta hasta la primera consulta).
    assert.equal(importar({ ...sinMarcas, NODE_ENV: 'test', DATABASE_URL: PRUEBAS }).status, 0);
    assert.equal(importar({ ...sinMarcas, DATABASE_URL: REAL }).status, 0);
  });

  it('npm test fija NODE_ENV=test', (t) => {
    if (process.env.npm_lifecycle_event !== 'test') {
      t.skip('solo aplica al correr con "npm test"');
      return;
    }
    assert.equal(process.env.NODE_ENV, 'test');
  });
});
