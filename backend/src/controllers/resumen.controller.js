import { query } from '../db.js';
import { calcularResumen, ESTADOS_EN_CURSO } from '../services/resumen.js';
import { hoyLocal } from '../utils/fechas.js';
import { COLUMNAS } from './suscripciones.controller.js';

// GET /api/resumen
// Totales por moneda, próximos cobros y pruebas que terminan en 7 días.
export async function resumen(req, res) {
  const [suscripciones, usuario] = await Promise.all([
    query(
      `SELECT ${COLUMNAS} FROM suscripciones
       WHERE usuario_id = $1 AND estado = ANY($2)`,
      [req.usuarioId, ESTADOS_EN_CURSO],
    ),
    query('SELECT dias_anticipacion_recordatorio FROM usuarios WHERE id = $1', [req.usuarioId]),
  ]);

  res.json({
    ...calcularResumen(suscripciones.rows, hoyLocal()),
    // La app lo usa para resaltar los cobros que entran en el aviso.
    dias_anticipacion_recordatorio: usuario.rows[0]?.dias_anticipacion_recordatorio ?? 3,
  });
}
