import { query } from '../db.js';
import { calcularAhorro, ultimosMeses } from '../services/ahorro.js';
import { hoyColombia } from '../utils/fechas.js';

/**
 * Canceladas del usuario con su ahorro y pagos por mes y moneda desde hace
 * 6 meses. Lo usan GET /api/ahorro y GET /api/analisis.
 */
export async function consultarAhorro(usuarioId, hoy) {
  const desde = `${ultimosMeses(hoy)[0]}-01`;
  const [canceladas, pagos] = await Promise.all([
    // cancelaciones solo tiene filas mientras la suscripción sigue cancelada
    // (al reactivarla se borra la fila).
    query(
      `SELECT s.id, s.nombre_servicio, s.categoria, s.moneda,
              c.fecha_cancelacion, c.ahorro_proyectado_anual
       FROM cancelaciones c
       JOIN suscripciones s ON s.id = c.suscripcion_id
       WHERE s.usuario_id = $1 AND s.estado = 'cancelada'`,
      [usuarioId],
    ),
    // to_char agrupa los pagos por mes ("2026-10").
    query(
      `SELECT to_char(h.fecha_pago, 'YYYY-MM') AS mes, s.moneda, SUM(h.monto) AS total
       FROM historial_pagos h
       JOIN suscripciones s ON s.id = h.suscripcion_id
       WHERE s.usuario_id = $1 AND h.fecha_pago >= $2
       GROUP BY 1, 2`,
      [usuarioId, desde],
    ),
  ]);
  return { canceladas: canceladas.rows, pagos: pagos.rows };
}

// GET /api/ahorro
// Ahorro por suscripciones canceladas y gasto mensual de los últimos 6 meses.
export async function ahorro(req, res) {
  const hoy = hoyColombia();
  const { canceladas, pagos } = await consultarAhorro(req.usuarioId, hoy);
  res.json(calcularAhorro(canceladas, pagos, hoy));
}
