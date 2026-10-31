// Cálculo de la pantalla de Ahorro (pantalla 12). Función pura, sin BD,
// para probarla en test/ahorro.test.js.
import { sumarMeses } from '../utils/fechas.js';

export const MESES_EVOLUCION = 6;

/** Los últimos `n` meses hasta el de `hoy`, como "AAAA-MM", del más viejo al actual. */
export function ultimosMeses(hoy, n = MESES_EVOLUCION) {
  const primeroDelMes = `${hoy.slice(0, 7)}-01`;
  return Array.from({ length: n }, (_, i) => sumarMeses(primeroDelMes, i - (n - 1)).slice(0, 7));
}

function porMonedaPrimero(a, b) {
  if (a === b) return 0;
  if (a === 'COP') return -1;
  if (b === 'COP') return 1;
  return a.localeCompare(b);
}

/**
 * @param canceladas filas con id, nombre_servicio, categoria, moneda,
 *   fecha_cancelacion ("AAAA-MM-DD") y ahorro_proyectado_anual
 * @param pagosPorMes filas { mes: "AAAA-MM", moneda, total } de historial_pagos
 * @param hoy "AAAA-MM-DD"
 */
export function calcularAhorro(canceladas, pagosPorMes, hoy) {
  // Totales por moneda: no se suman COP con USD.
  const porMoneda = new Map();
  for (const c of canceladas) {
    const t = porMoneda.get(c.moneda) ?? { moneda: c.moneda, centavos: 0, cantidad: 0 };
    t.centavos += Math.round(c.ahorro_proyectado_anual * 100);
    t.cantidad += 1;
    porMoneda.set(c.moneda, t);
  }
  const totales = [...porMoneda.values()]
    .sort((a, b) => porMonedaPrimero(a.moneda, b.moneda))
    .map((t) => ({
      moneda: t.moneda,
      ahorro_anual: t.centavos / 100,
      ahorro_mensual: Math.round(t.centavos / 12) / 100,
      cantidad: t.cantidad,
    }));

  // Evolución del gasto: un total por mes y moneda; los meses sin pagos van
  // con 0. COP siempre aparece (es la gráfica principal).
  const meses = ultimosMeses(hoy);
  const monedas = new Set(['COP', ...pagosPorMes.map((p) => p.moneda)]);
  const evolucion = [...monedas].sort(porMonedaPrimero).map((moneda) => ({
    moneda,
    meses: meses.map((mes) => ({
      mes,
      total: pagosPorMes
        .filter((p) => p.moneda === moneda && p.mes === mes)
        .reduce((t, p) => t + Number(p.total), 0),
    })),
  }));

  const lista = [...canceladas].sort((a, b) =>
    b.fecha_cancelacion.localeCompare(a.fecha_cancelacion) || b.id - a.id);

  return {
    totales,
    cantidad_canceladas: canceladas.length,
    canceladas: lista,
    evolucion,
  };
}
