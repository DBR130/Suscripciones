// Cálculo del resumen del dashboard. Es una función pura (no consulta la BD)
// para poder probarla fácilmente en test/resumen.test.js.
import { diasEntre } from '../utils/fechas.js';

// Estados que siguen generando cobros. Las canceladas no cuentan.
export const ESTADOS_EN_CURSO = ['activa', 'marcada_para_cancelar'];

// Cuántos cobros hay en un año según la frecuencia.
const COBROS_POR_ANIO = { semanal: 52, mensual: 12, anual: 1 };

const VENTANA_DIAS = 7;

/**
 * Costo anual en centavos. Se trabaja en centavos (enteros) para evitar los
 * errores de redondeo de los decimales en JavaScript (0.1 + 0.2 !== 0.3).
 * Las pruebas gratis cuestan 0 mientras dura la prueba.
 */
export function centavosAnuales(s) {
  if (s.es_prueba_gratis) return 0;
  return Math.round(s.monto * 100) * COBROS_POR_ANIO[s.frecuencia];
}

/**
 * @param suscripciones filas de la tabla suscripciones de UN usuario
 * @param hoy fecha "AAAA-MM-DD"
 */
export function calcularResumen(suscripciones, hoy) {
  const enCurso = suscripciones.filter((s) => ESTADOS_EN_CURSO.includes(s.estado));

  // Totales separados por moneda: no se convierten USD a COP.
  const porMoneda = new Map();
  for (const s of enCurso) {
    const total = porMoneda.get(s.moneda) ?? { moneda: s.moneda, centavosAnuales: 0, cantidad: 0 };
    total.centavosAnuales += centavosAnuales(s);
    total.cantidad += 1;
    porMoneda.set(s.moneda, total);
  }
  const totales = [...porMoneda.values()]
    // COP primero (la moneda del país); el resto en orden alfabético.
    .sort((a, b) => (a.moneda === 'COP' ? -1 : b.moneda === 'COP' ? 1 : a.moneda.localeCompare(b.moneda)))
    .map((t) => ({
      moneda: t.moneda,
      // Mensual equivalente = anual / 12 (semanal: monto * 52 / 12).
      gasto_mensual: Math.round(t.centavosAnuales / 12) / 100,
      proyeccion_anual: t.centavosAnuales / 100,
      cantidad: t.cantidad,
    }));

  const enVentana = (fecha) => {
    const dias = diasEntre(hoy, fecha);
    return dias >= 0 && dias <= VENTANA_DIAS ? dias : null;
  };

  const proximos_cobros = enCurso
    // Las pruebas gratis van en su propia lista para no mostrarlas dos veces.
    .filter((s) => !s.es_prueba_gratis && enVentana(s.fecha_proximo_cobro) !== null)
    .map((s) => ({ ...s, dias_restantes: diasEntre(hoy, s.fecha_proximo_cobro) }))
    .sort((a, b) => a.dias_restantes - b.dias_restantes);

  const pruebas_por_terminar = enCurso
    .filter((s) => s.es_prueba_gratis && s.fecha_fin_prueba && enVentana(s.fecha_fin_prueba) !== null)
    .map((s) => ({ ...s, dias_restantes: diasEntre(hoy, s.fecha_fin_prueba) }))
    .sort((a, b) => a.dias_restantes - b.dias_restantes);

  return {
    totales,
    cantidad_activas: enCurso.length,
    proximos_cobros,
    pruebas_por_terminar,
  };
}
