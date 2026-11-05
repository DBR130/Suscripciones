// Carga el catálogo de guías de cancelación (db/guias.json) en la BD.
//
// Uso:  npm run db:guias
//
// Es idempotente: inserta las guías nuevas y actualiza las que cambiaron
// ("upsert"). Si una guía no cambió, no se toca (ni su fecha de
// actualización). Las guías que se quiten del JSON NO se borran de la BD.
import fs from 'node:fs/promises';
import path from 'node:path';

import pg from 'pg';

import { verificarBdPermitida } from '../src/utils/candadoBd.js';

const ARCHIVO = path.join(import.meta.dirname, 'guias.json');

/** Revisa que el JSON tenga la forma correcta. Lanza un error si no. */
export function validarGuias(guias) {
  if (!Array.isArray(guias) || guias.length === 0) throw new Error('guias.json debe ser un arreglo con guías');
  const nombres = new Set();
  let genericas = 0;
  for (const [i, g] of guias.entries()) {
    const donde = `guía #${i + 1} (${g?.nombre_servicio ?? 'sin nombre'})`;
    if (typeof g.nombre_servicio !== 'string' || !g.nombre_servicio.trim() || g.nombre_servicio.length > 100) {
      throw new Error(`${donde}: nombre_servicio es obligatorio (máx. 100)`);
    }
    if (nombres.has(g.nombre_servicio)) throw new Error(`${donde}: nombre repetido`);
    nombres.add(g.nombre_servicio);
    if (!Array.isArray(g.pasos) || g.pasos.length < 1 || g.pasos.some((p) => typeof p !== 'string' || !p.trim())) {
      throw new Error(`${donde}: pasos debe ser un arreglo de textos`);
    }
    if (g.alias !== undefined && (!Array.isArray(g.alias) || g.alias.some((a) => typeof a !== 'string'))) {
      throw new Error(`${donde}: alias debe ser un arreglo de textos`);
    }
    if (g.duracion_minutos != null && (!Number.isInteger(g.duracion_minutos) || g.duracion_minutos < 1)) {
      throw new Error(`${donde}: duracion_minutos debe ser un entero positivo`);
    }
    if (g.enlace_directo != null && !/^https:\/\/\S+$/.test(g.enlace_directo)) {
      throw new Error(`${donde}: enlace_directo debe empezar por https://`);
    }
    if (g.es_ambigua !== undefined && typeof g.es_ambigua !== 'boolean') {
      throw new Error(`${donde}: es_ambigua debe ser true o false`);
    }
    if (g.precio_referencia_cop != null && !(Number.isFinite(g.precio_referencia_cop) && g.precio_referencia_cop > 0)) {
      throw new Error(`${donde}: precio_referencia_cop debe ser un número mayor que 0`);
    }
    if (g.es_generica) genericas += 1;
  }
  if (genericas !== 1) throw new Error('Debe haber exactamente una guía con "es_generica": true');
}

/** Hace el upsert de `guias` en la BD. Devuelve cuántas se crearon o cambiaron. */
export async function cargarGuias(connectionString, guias) {
  validarGuias(guias);
  verificarBdPermitida(connectionString);
  const client = new pg.Client({ connectionString });
  await client.connect();
  try {
    await client.query('BEGIN');
    let cambios = 0;
    for (const g of guias) {
      // ON CONFLICT: si ya existe una guía con ese nombre, se actualiza, pero
      // solo cuando algo es distinto (IS DISTINCT FROM también compara NULL).
      const { rowCount } = await client.query(
        `INSERT INTO guias_cancelacion
           (nombre_servicio, pasos, enlace_directo, alias, duracion_minutos, es_generica, es_ambigua,
            precio_referencia_cop)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
         ON CONFLICT (nombre_servicio) DO UPDATE SET
           pasos = EXCLUDED.pasos,
           enlace_directo = EXCLUDED.enlace_directo,
           alias = EXCLUDED.alias,
           duracion_minutos = EXCLUDED.duracion_minutos,
           es_generica = EXCLUDED.es_generica,
           es_ambigua = EXCLUDED.es_ambigua,
           precio_referencia_cop = EXCLUDED.precio_referencia_cop,
           actualizada_en = NOW()
         WHERE (guias_cancelacion.pasos, guias_cancelacion.enlace_directo, guias_cancelacion.alias,
                guias_cancelacion.duracion_minutos, guias_cancelacion.es_generica,
                guias_cancelacion.es_ambigua, guias_cancelacion.precio_referencia_cop)
           IS DISTINCT FROM
               (EXCLUDED.pasos, EXCLUDED.enlace_directo, EXCLUDED.alias,
                EXCLUDED.duracion_minutos, EXCLUDED.es_generica, EXCLUDED.es_ambigua,
                EXCLUDED.precio_referencia_cop)`,
        [
          g.nombre_servicio,
          JSON.stringify(g.pasos),
          g.enlace_directo ?? null,
          g.alias ?? [],
          g.duracion_minutos ?? null,
          g.es_generica === true,
          g.es_ambigua === true,
          g.precio_referencia_cop ?? null,
        ],
      );
      cambios += rowCount;
    }
    await client.query('COMMIT');
    return cambios;
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    await client.end();
  }
}

if (import.meta.main) {
  if (!process.env.DATABASE_URL) {
    console.error('Falta DATABASE_URL. Revisa el archivo .env (ver .env.example).');
    process.exit(1);
  }
  try {
    const guias = JSON.parse(await fs.readFile(ARCHIVO, 'utf8'));
    const cambios = await cargarGuias(process.env.DATABASE_URL, guias);
    console.log(`Catálogo cargado: ${guias.length} guías en el archivo, ${cambios} nuevas o actualizadas.`);
  } catch (err) {
    console.error('No se pudo cargar el catálogo:', err.message);
    process.exit(1);
  }
}
