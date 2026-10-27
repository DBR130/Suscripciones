// Prepara una base de datos SOLO para pruebas, separada de la real.
//
// Usa TEST_DATABASE_URL si existe; si no, toma DATABASE_URL del .env y cambia
// el nombre de la base por "subtrack_test". La crea si no existe, la deja
// vacía y le aplica todas las migraciones. Así los tests nunca tocan los
// datos de la base "subtrack".
import pg from 'pg';

import { migrar } from '../../db/migrar.js';

function urlDePruebas() {
  if (process.env.TEST_DATABASE_URL) return new URL(process.env.TEST_DATABASE_URL);
  if (!process.env.DATABASE_URL) {
    throw new Error('Define DATABASE_URL o TEST_DATABASE_URL para correr los tests.');
  }
  const url = new URL(process.env.DATABASE_URL);
  url.pathname = '/subtrack_test';
  return url;
}

export async function prepararBdPruebas() {
  const url = urlDePruebas();
  const nombre = decodeURIComponent(url.pathname.slice(1));
  // Protección: esta función borra todo, así que se niega a usar una base
  // cuyo nombre no termine en "_test".
  if (!nombre.endsWith('_test')) {
    throw new Error(`La base de pruebas debe terminar en "_test" (recibido: ${nombre}).`);
  }

  // Para crear la base hay que conectarse a otra: "postgres" siempre existe.
  const admin = new URL(url);
  admin.pathname = '/postgres';
  const clienteAdmin = new pg.Client({ connectionString: admin.href });
  await clienteAdmin.connect();
  try {
    const { rowCount } = await clienteAdmin.query('SELECT 1 FROM pg_database WHERE datname = $1', [nombre]);
    if (rowCount === 0) {
      // CREATE DATABASE no admite parámetros $1; el nombre ya se validó arriba.
      await clienteAdmin.query(`CREATE DATABASE "${nombre.replaceAll('"', '""')}"`);
    }
  } finally {
    await clienteAdmin.end();
  }

  // Empieza siempre desde cero para que cada ejecución sea igual.
  const cliente = new pg.Client({ connectionString: url.href });
  await cliente.connect();
  try {
    await cliente.query('DROP SCHEMA public CASCADE; CREATE SCHEMA public;');
  } finally {
    await cliente.end();
  }
  await migrar(url.href, () => {});

  // src/db.js lee estas variables al importarse: deben definirse antes.
  process.env.DATABASE_URL = url.href;
  process.env.JWT_SECRET ??= 'secreto-solo-para-pruebas';
}
