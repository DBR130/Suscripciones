// Candado de la base de datos de pruebas.
//
// Si el proceso corre bajo node:test (o con NODE_ENV=test), solo se permite
// conectarse a una base cuyo nombre termine en "_test". Así un test mal
// escrito nunca puede escribir en la base real "subtrack", aunque importe
// db.js antes de tiempo. Lo usan src/db.js y los scripts de db/.

/** true si el proceso es un test: node --test define NODE_TEST_CONTEXT y npm test, NODE_ENV=test. */
export function corriendoTests(env = process.env) {
  return Boolean(env.NODE_TEST_CONTEXT) || env.NODE_ENV === 'test';
}

/** Nombre de la base en una URL de conexión ("" si no se puede leer). */
export function nombreDeBd(connectionString) {
  try {
    return decodeURIComponent(new URL(connectionString).pathname.slice(1));
  } catch {
    return '';
  }
}

/** Lanza un error (antes de conectar) si un test intenta usar una base que no es de pruebas. */
export function verificarBdPermitida(connectionString, env = process.env) {
  if (!corriendoTests(env)) return;
  const nombre = nombreDeBd(connectionString ?? '');
  if (!nombre.endsWith('_test')) {
    throw new Error(
      `Candado de pruebas: este proceso corre bajo tests y no puede conectarse a la base "${nombre || '(sin nombre)'}". `
      + 'Solo se permiten bases cuyo nombre termine en "_test" (ver test/helpers/bd.js).',
    );
  }
}
