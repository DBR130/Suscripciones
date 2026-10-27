import { query } from '../db.js';
import { calcularAvisos } from '../services/avisos.js';
import { hoyColombia } from '../utils/fechas.js';
import { COLUMNAS } from './suscripciones.controller.js';

// GET /api/avisos
// Próximos cobros y fines de prueba dentro de sus días de aviso, y cambios de
// precio de los últimos 30 días (ver services/avisos.js).
export async function avisos(req, res) {
  const [suscripciones, cambios, usuario] = await Promise.all([
    query(`SELECT ${COLUMNAS} FROM suscripciones WHERE usuario_id = $1`, [req.usuarioId]),
    // JOIN: solo los cambios de suscripciones de este usuario.
    query(
      `SELECT c.suscripcion_id, c.monto_anterior, c.monto_nuevo, c.fecha_cambio,
              s.nombre_servicio, s.moneda, s.frecuencia
       FROM cambios_precio c
       JOIN suscripciones s ON s.id = c.suscripcion_id
       WHERE s.usuario_id = $1 AND s.estado <> 'cancelada'
         AND c.fecha_cambio >= NOW() - INTERVAL '31 days'`,
      [req.usuarioId],
    ),
    query('SELECT dias_anticipacion_recordatorio FROM usuarios WHERE id = $1', [req.usuarioId]),
  ]);

  const dias = usuario.rows[0]?.dias_anticipacion_recordatorio ?? 3;
  res.json({
    dias_anticipacion_recordatorio: dias,
    avisos: calcularAvisos(suscripciones.rows, cambios.rows, dias, hoyColombia()),
  });
}
