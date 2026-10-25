// Avisos de la pestaña "Avisos" (pantalla 11). Función pura, sin BD, para
// poder probarla en test/avisos.test.js.
import { ESTADOS_EN_CURSO } from './resumen.js';
import { diasEntre, hoyColombia, sumarDias } from '../utils/fechas.js';

const DIAS_CAMBIO_PRECIO = 30;

/**
 * Arma la lista de avisos de un usuario:
 * - proximo_cobro: cobros que ya entraron en su periodo de aviso (los días de
 *   la suscripción o, si no tiene, la preferencia global).
 * - fin_prueba_gratis: pruebas que terminan dentro de su periodo de aviso.
 * - cambio_precio: cambios de monto de los últimos 30 días.
 *
 * `fecha_aviso` es el día en que salió (o sale hoy) el recordatorio; la lista
 * va de la más reciente a la más antigua, como en el diseño.
 *
 * @param suscripciones filas de suscripciones del usuario
 * @param cambios filas de cambios_precio (con nombre_servicio, moneda, frecuencia)
 * @param diasGlobales preferencia dias_anticipacion_recordatorio del usuario
 * @param hoy "AAAA-MM-DD"
 */
export function calcularAvisos(suscripciones, cambios, diasGlobales, hoy) {
  const avisos = [];

  for (const s of suscripciones.filter((x) => ESTADOS_EN_CURSO.includes(x.estado))) {
    const dias = s.dias_aviso ?? diasGlobales;
    const tipo = s.es_prueba_gratis ? 'fin_prueba_gratis' : 'proximo_cobro';
    const fecha = s.es_prueba_gratis ? s.fecha_fin_prueba : s.fecha_proximo_cobro;
    if (!fecha) continue;

    const restantes = diasEntre(hoy, fecha);
    if (restantes < 0 || restantes > dias) continue;
    avisos.push({
      tipo,
      suscripcion_id: s.id,
      nombre_servicio: s.nombre_servicio,
      monto: s.monto,
      moneda: s.moneda,
      frecuencia: s.frecuencia,
      fecha,
      dias_restantes: restantes,
      fecha_aviso: sumarDias(fecha, -dias),
    });
  }

  for (const c of cambios) {
    // fecha_cambio llega como Date (TIMESTAMP); se toma el día en Colombia
    // (con toISOString, un cambio a las 8 p. m. caería en el día siguiente).
    const dia = c.fecha_cambio instanceof Date ? hoyColombia(c.fecha_cambio) : String(c.fecha_cambio).slice(0, 10);
    if (diasEntre(dia, hoy) > DIAS_CAMBIO_PRECIO) continue;
    avisos.push({
      tipo: 'cambio_precio',
      suscripcion_id: c.suscripcion_id,
      nombre_servicio: c.nombre_servicio,
      monto: c.monto_nuevo,
      monto_anterior: c.monto_anterior,
      moneda: c.moneda,
      frecuencia: c.frecuencia,
      fecha: dia,
      fecha_aviso: dia,
    });
  }

  // Más reciente primero; a igual fecha, el evento más cercano primero.
  return avisos.sort((a, b) => b.fecha_aviso.localeCompare(a.fecha_aviso)
    || (a.dias_restantes ?? 0) - (b.dias_restantes ?? 0));
}
