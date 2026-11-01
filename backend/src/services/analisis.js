// Cálculo de la pestaña Análisis. Función pura, sin BD, para probarla en
// test/analisis.test.js. Reúne lo que ya calculan el resumen y el ahorro y
// agrega los cobros de los próximos 30 días y las suscripciones más caras.
import { calcularAhorro } from './ahorro.js';
import { calcularResumen, centavosAnuales, ESTADOS_EN_CURSO } from './resumen.js';
import { avanzarCiclo, diasEntre } from '../utils/fechas.js';

export const VENTANA_CALENDARIO = 30;
export const CANTIDAD_MAS_CARAS = 3;

function porMonedaPrimero(a, b) {
  if (a === b) return 0;
  if (a === 'COP') return -1;
  if (b === 'COP') return 1;
  return a.localeCompare(b);
}

/**
 * Cobros de hoy a `dias` días: una semanal puede cobrarse varias veces. Una
 * prueba gratis aparece el día que termina, con el monto que empieza a cobrar.
 */
export function cobrosEnVentana(enCurso, hoy, dias = VENTANA_CALENDARIO) {
  const cobros = [];
  for (const s of enCurso) {
    const prueba = s.es_prueba_gratis && s.fecha_fin_prueba;
    let fecha = prueba ? s.fecha_fin_prueba : s.fecha_proximo_cobro;
    // Una prueba vencida sigue pendiente de cobro: no se repite.
    if (prueba) {
      const faltan = diasEntre(hoy, fecha);
      if (faltan >= 0 && faltan <= dias) {
        cobros.push(cobro(s, fecha, faltan, true));
      }
      continue;
    }
    // Las fechas pasadas aún no cobradas avanzan hasta hoy o después.
    while (diasEntre(hoy, fecha) < 0) fecha = avanzarCiclo(fecha, s.frecuencia);
    while (diasEntre(hoy, fecha) <= dias) {
      cobros.push(cobro(s, fecha, diasEntre(hoy, fecha), false));
      fecha = avanzarCiclo(fecha, s.frecuencia);
    }
  }
  return cobros.sort((a, b) => a.fecha.localeCompare(b.fecha)
    || porMonedaPrimero(a.moneda, b.moneda)
    || a.nombre_servicio.localeCompare(b.nombre_servicio));
}

function cobro(s, fecha, dias, finDePrueba) {
  return {
    suscripcion_id: s.id,
    nombre_servicio: s.nombre_servicio,
    monto: Number(s.monto),
    moneda: s.moneda,
    fecha,
    dias_restantes: dias,
    fin_de_prueba: finDePrueba,
  };
}

/**
 * Las más caras por gasto mensual equivalente. No se convierten monedas: van
 * primero las de COP y después las demás (USD...).
 */
export function masCaras(enCurso, cantidad = CANTIDAD_MAS_CARAS) {
  return enCurso
    .filter((s) => !s.es_prueba_gratis)
    .map((s) => ({ s, centavos: centavosAnuales(s) }))
    .sort((a, b) => porMonedaPrimero(a.s.moneda, b.s.moneda) || b.centavos - a.centavos)
    .slice(0, cantidad)
    .map(({ s, centavos }) => ({
      id: s.id,
      nombre_servicio: s.nombre_servicio,
      categoria: s.categoria ?? null,
      moneda: s.moneda,
      monto: Number(s.monto),
      frecuencia: s.frecuencia,
      gasto_mensual: Math.round(centavos / 12) / 100,
    }));
}

/**
 * @param suscripciones filas de suscripciones de UN usuario (todas)
 * @param canceladas filas como las de GET /api/ahorro
 * @param pagosPorMes filas { mes, moneda, total } de historial_pagos
 * @param hoy "AAAA-MM-DD"
 */
export function calcularAnalisis(suscripciones, canceladas, pagosPorMes, hoy) {
  const enCurso = suscripciones.filter((s) => ESTADOS_EN_CURSO.includes(s.estado));
  const resumen = calcularResumen(enCurso, hoy);
  const ahorro = calcularAhorro(canceladas, pagosPorMes, hoy);
  return {
    // Proyección anual y gasto mensual actual, por moneda.
    totales: resumen.totales,
    cantidad_activas: resumen.cantidad_activas,
    // Gasto pagado (historial) de los últimos 6 meses, por moneda.
    gasto_mensual: ahorro.evolucion,
    por_categoria: resumen.por_categoria,
    proximos_cobros: cobrosEnVentana(enCurso, hoy),
    mas_caras: masCaras(enCurso),
    ahorro: {
      totales: ahorro.totales,
      cantidad_canceladas: ahorro.cantidad_canceladas,
      canceladas: ahorro.canceladas,
    },
  };
}
