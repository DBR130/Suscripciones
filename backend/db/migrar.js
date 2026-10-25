// Sistema simple de migraciones.
//
// Una "migración" es un archivo .sql numerado (001_..., 002_...) con un cambio
// al esquema de la BD. Se aplican en orden y cada una una sola vez: la tabla
// schema_migrations guarda cuáles ya se aplicaron.
//
// Uso:  npm run db:migrate
import fs from 'node:fs/promises';
import path from 'node:path';

import pg from 'pg';

const CARPETA = path.join(import.meta.dirname, 'migraciones');
const PATRON = /^\d{3}_.+\.sql$/;
const INICIAL = '001_inicial.sql';

/**
 * Aplica las migraciones pendientes en la BD de `connectionString`.
 * Devuelve la lista de migraciones aplicadas en esta ejecución.
 */
export async function migrar(connectionString, log = console.log) {
  const client = new pg.Client({ connectionString });
  await client.connect();
  try {
    await client.query(`
      CREATE TABLE IF NOT EXISTS schema_migrations (
        version     VARCHAR(255) PRIMARY KEY,
        aplicada_en TIMESTAMP    NOT NULL DEFAULT NOW()
      )`);

    const { rows } = await client.query('SELECT version FROM schema_migrations');
    const aplicadas = new Set(rows.map((r) => r.version));

    // La BD original se creó a mano antes de existir este sistema. Si ya tiene
    // la tabla usuarios, la 001 se da por aplicada en lugar de ejecutarla
    // (ejecutarla fallaría porque las tablas ya existen).
    if (!aplicadas.has(INICIAL)) {
      const existe = await client.query("SELECT to_regclass('public.usuarios') IS NOT NULL AS existe");
      if (existe.rows[0].existe) {
        await client.query('INSERT INTO schema_migrations (version) VALUES ($1)', [INICIAL]);
        aplicadas.add(INICIAL);
        log(`= ${INICIAL} (la tabla usuarios ya existía: marcada como aplicada sin ejecutarla)`);
      }
    }

    const archivos = (await fs.readdir(CARPETA)).filter((f) => PATRON.test(f)).sort();
    const pendientes = archivos.filter((f) => !aplicadas.has(f));

    for (const archivo of pendientes) {
      const sql = await fs.readFile(path.join(CARPETA, archivo), 'utf8');
      // Transacción: o se aplica la migración completa, o no se aplica nada.
      // Si una sentencia falla, ROLLBACK deja la BD como estaba.
      await client.query('BEGIN');
      try {
        await client.query(sql);
        await client.query('INSERT INTO schema_migrations (version) VALUES ($1)', [archivo]);
        await client.query('COMMIT');
        log(`+ ${archivo}`);
      } catch (err) {
        await client.query('ROLLBACK');
        err.message = `Falló la migración ${archivo}: ${err.message}`;
        throw err;
      }
    }

    if (pendientes.length === 0) log('La base de datos ya está al día.');
    return pendientes;
  } finally {
    await client.end();
  }
}

// Solo se ejecuta cuando se corre este archivo directamente (npm run db:migrate),
// no cuando los tests lo importan.
if (import.meta.main) {
  if (!process.env.DATABASE_URL) {
    console.error('Falta DATABASE_URL. Revisa el archivo .env (ver .env.example).');
    process.exit(1);
  }
  try {
    await migrar(process.env.DATABASE_URL);
  } catch (err) {
    console.error(err.message);
    process.exit(1);
  }
}
