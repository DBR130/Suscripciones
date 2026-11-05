import { query } from '../db.js';
import { buscarGuia } from '../services/guias.js';
import { PROCESADORES } from '../services/procesadores.js';
import { HttpError } from '../utils/httpError.js';

const COLUMNAS_GUIA = `nombre_servicio, pasos, enlace_directo, alias, duracion_minutos,
  actualizada_en, es_generica`;

// GET /api/guias
// Catálogo de guías (nombre, alias y si el servicio es ambiguo), sin la genérica.
export async function listarGuias(req, res) {
  const { rows } = await query(
    `SELECT id, nombre_servicio, alias, es_ambigua FROM guias_cancelacion
     WHERE NOT es_generica ORDER BY nombre_servicio`,
  );
  // Los procesadores de pago van con el catálogo: la app los usa para
  // reconocer cobros como "SERVICIOS WEB EBANX CO".
  res.json({ guias: rows, procesadores: PROCESADORES });
}

// GET /api/suscripciones/:id/guia
// La guía que corresponde a la suscripción (por nombre o alias, sin importar
// mayúsculas ni tildes). Si no hay, la genérica con es_generica: true.
export async function guiaDeSuscripcion(req, res) {
  const id = Number(req.params.id);
  if (!Number.isInteger(id) || id < 1 || id > 2147483647) {
    throw new HttpError(404, 'Suscripción no encontrada');
  }
  // Mismo filtro por usuario_id que el resto: 404 si es de otro usuario.
  const suscripcion = await query(
    'SELECT id, nombre_servicio FROM suscripciones WHERE id = $1 AND usuario_id = $2',
    [id, req.usuarioId],
  );
  if (suscripcion.rows.length === 0) throw new HttpError(404, 'Suscripción no encontrada');

  // El catálogo es pequeño (unas 20 guías): se compara en JavaScript.
  const guias = await query(`SELECT ${COLUMNAS_GUIA} FROM guias_cancelacion`);
  const { guia, esGenerica } = buscarGuia(suscripcion.rows[0].nombre_servicio, guias.rows);
  if (!guia) throw new HttpError(404, 'No hay guías de cancelación cargadas (npm run db:guias)');

  res.json({ suscripcion: suscripcion.rows[0], guia, es_generica: esGenerica });
}
