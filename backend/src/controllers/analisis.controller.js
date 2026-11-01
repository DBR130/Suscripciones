import { query } from '../db.js';
import { calcularAnalisis } from '../services/analisis.js';
import { ESTADOS_EN_CURSO } from '../services/resumen.js';
import { hoyColombia } from '../utils/fechas.js';
import { consultarAhorro } from './ahorro.controller.js';
import { COLUMNAS } from './suscripciones.controller.js';

// GET /api/analisis
// Todo lo de la pestaña Análisis en una sola petición: gasto de 6 meses,
// categorías, cobros de 30 días, más caras, proyección y ahorro.
export async function analisis(req, res) {
  const hoy = hoyColombia();
  const [suscripciones, { canceladas, pagos }] = await Promise.all([
    query(
      `SELECT ${COLUMNAS} FROM suscripciones
       WHERE usuario_id = $1 AND estado = ANY($2)`,
      [req.usuarioId, ESTADOS_EN_CURSO],
    ),
    consultarAhorro(req.usuarioId, hoy),
  ]);
  res.json(calcularAnalisis(suscripciones.rows, canceladas, pagos, hoy));
}
