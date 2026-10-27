// Cálculo del resumen del dashboard. Es una función pura (no consulta la BD)
// para poder probarla fácilmente en test/resumen.test.js.
import { diasEntre } from '../utils/fechas.js';

// Estados que siguen generando cobros. Las canceladas no cuentan.
export const ESTADOS_EN_CURSO = ['activa', 'marcada_para_cancelar'];

// Cuántos cobros hay en un año según la frecuencia.
const COBROS_POR_ANIO = { semanal: 52, mensual: 12, anual: 1 };

const VENTANA_DIAS = 7;

// Para ordenar: COP primero (la moneda del país); el resto en orden alfabético.
function porMonedaPrimero(a, b) {
  if (a.moneda === b.moneda) return 0;
  if (a.moneda === 'COP') return -1;
  if (b.moneda === 'COP') return 1;
  return a.moneda.localeCompare(b.moneda);
}

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
    .sort(porMonedaPrimero)
    .map((t) => ({
      moneda: t.moneda,
      // Mensual equivalente = anual / 12 (semanal: monto * 52 / 12).
      gasto_mensual: Math.round(t.centavosAnuales / 12) / 100,
      proyeccion_anual: t.centavosAnuales / 100,
      cantidad: t.cantidad,
    }));

  // Gasto mensual por categoría (y moneda, porque no se suman COP con USD).
  // categoria null = "Sin categoría".
  const porCategoria = new Map();
  for (const s of enCurso) {
    const clave = `${s.categoria ?? ''}|${s.moneda}`;
    const grupo = porCategoria.get(clave)
      ?? { categoria: s.categoria ?? null, moneda: s.moneda, centavosAnuales: 0, cantidad: 0 };
    grupo.centavosAnuales += centavosAnuales(s);
    grupo.cantidad += 1;
    porCategoria.set(clave, grupo);
  }
  const por_categoria = [...porCategoria.values()]
    // Por moneda (COP primero), luego de mayor a menor gasto y "Sin categoría" al final.
    .sort((a, b) => porMonedaPrimero(a, b)
      || (a.categoria === null) - (b.categoria === null)
      || b.centavosAnuales - a.centavosAnuales
      || (a.categoria ?? '').localeCompare(b.categoria ?? ''))
    .map((g) => ({
      categoria: g.categoria,
      moneda: g.moneda,
      gasto_mensual: Math.round(g.centavosAnuales / 12) / 100,
      cantidad: g.cantidad,
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
    por_categoria,
    cantidad_activas: enCurso.length,
    proximos_cobros,
    pruebas_por_terminar,
  };
}
