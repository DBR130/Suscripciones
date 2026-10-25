// Registro automático de cobros.
//
// Cuando llega (o ya pasó) la fecha de cobro de una suscripción, se guarda el
// pago en historial_pagos y la fecha avanza al siguiente ciclo. Si el portátil
// estuvo apagado varios días y se saltaron ciclos, se registran todos.
import { transaccion } from '../db.js';
import { ESTADOS_EN_CURSO } from './resumen.js';
import { avanzarCiclo, hoyColombia } from '../utils/fechas.js';

/**
 * Procesa los cobros pendientes hasta `hoy` (incluido).
 *
 * - Solo suscripciones 'activa' o 'marcada_para_cancelar' (las canceladas no).
 * - Prueba gratis: si ya pasó su fecha de fin, deja de ser prueba y se cobra.
 *   Si la prueba sigue vigente, no se cobra nada todavía.
 * - Es idempotente: correrlo dos veces no duplica pagos, porque la fecha ya
 *   avanzó y porque historial_pagos tiene UNIQUE (suscripcion_id, fecha_pago).
 * - Todo va en una transacción: si algo falla, no queda nada a medias.
 *
 * Devuelve cuántas suscripciones se actualizaron y cuántos pagos se crearon.
 */
export async function procesarCobros(hoy = hoyColombia()) {
  return transaccion(async (client) => {
    // FOR UPDATE: si el cron y el arranque coinciden, el segundo espera.
    const { rows } = await client.query(
      `SELECT id, monto, frecuencia, fecha_proximo_cobro, es_prueba_gratis, fecha_fin_prueba
       FROM suscripciones
       WHERE estado = ANY($1) AND fecha_proximo_cobro <= $2
       ORDER BY id
       FOR UPDATE`,
      [ESTADOS_EN_CURSO, hoy],
    );

    let suscripciones = 0;
    let pagos = 0;
    for (const s of rows) {
      let esPrueba = s.es_prueba_gratis;
      if (esPrueba) {
        // La prueba sigue vigente: todavía no hay cobro.
        if (s.fecha_fin_prueba > hoy) continue;
        esPrueba = false;
      }

      // Registra cada ciclo vencido hasta que la fecha quede en el futuro.
      let fecha = s.fecha_proximo_cobro;
      while (fecha <= hoy) {
        const { rowCount } = await client.query(
          `INSERT INTO historial_pagos (suscripcion_id, monto, fecha_pago)
           VALUES ($1, $2, $3)
           ON CONFLICT (suscripcion_id, fecha_pago) DO NOTHING`,
          [s.id, s.monto, fecha],
        );
        pagos += rowCount;
        fecha = avanzarCiclo(fecha, s.frecuencia);
      }

      await client.query(
        'UPDATE suscripciones SET fecha_proximo_cobro = $2, es_prueba_gratis = $3 WHERE id = $1',
        [s.id, fecha, esPrueba],
      );
      suscripciones += 1;
    }
    return { suscripciones, pagos };
  });
}
