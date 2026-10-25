// Pruebas del cálculo del resumen (función pura: no usa la base de datos).
import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import { calcularResumen } from '../src/services/resumen.js';
import { diasEntre, esFechaValida } from '../src/utils/fechas.js';

const HOY = '2026-11-10';

let siguienteId = 1;
function sus(datos) {
  return {
    id: siguienteId++,
    nombre_servicio: 'Servicio',
    moneda: 'COP',
    frecuencia: 'mensual',
    fecha_proximo_cobro: '2026-12-01',
    es_prueba_gratis: false,
    fecha_fin_prueba: null,
    estado: 'activa',
    ...datos,
  };
}

describe('calcularResumen', () => {
  it('convierte cada frecuencia a gasto mensual equivalente', () => {
    const r = calcularResumen([
      sus({ monto: 45900, frecuencia: 'mensual' }),
      sus({ monto: 120000, frecuencia: 'anual' }), // 10.000 al mes
      sus({ monto: 12000, frecuencia: 'semanal' }), // 12.000 * 52 / 12 = 52.000
    ], HOY);

    assert.deepEqual(r.totales, [{
      moneda: 'COP',
      gasto_mensual: 45900 + 10000 + 52000,
      proyeccion_anual: 45900 * 12 + 120000 + 12000 * 52,
      cantidad: 3,
    }]);
    assert.equal(r.cantidad_activas, 3);
  });

  it('separa los totales por moneda sin convertir, con COP primero', () => {
    const r = calcularResumen([
      sus({ monto: 9.99, moneda: 'USD' }),
      sus({ monto: 20.01, moneda: 'USD' }),
      sus({ monto: 38900, moneda: 'COP' }),
    ], HOY);

    assert.deepEqual(r.totales.map((t) => t.moneda), ['COP', 'USD']);
    // 9.99 + 20.01 exacto (sin errores de decimales).
    assert.equal(r.totales[1].gasto_mensual, 30);
    assert.equal(r.totales[1].proyeccion_anual, 360);
  });

  it('redondea el mensual equivalente a 2 decimales', () => {
    const r = calcularResumen([sus({ monto: 10, frecuencia: 'semanal', moneda: 'USD' })], HOY);
    // 10 * 52 / 12 = 43.333...
    assert.equal(r.totales[0].gasto_mensual, 43.33);
    assert.equal(r.totales[0].proyeccion_anual, 520);
  });

  it('cuenta activas y marcadas para cancelar, pero no canceladas', () => {
    const r = calcularResumen([
      sus({ monto: 10000, estado: 'activa' }),
      sus({ monto: 20000, estado: 'marcada_para_cancelar' }),
      sus({ monto: 99999, estado: 'cancelada' }),
    ], HOY);

    assert.equal(r.cantidad_activas, 2);
    assert.equal(r.totales[0].gasto_mensual, 30000);
  });

  it('las pruebas gratis cuentan como activas pero no suman gasto', () => {
    const r = calcularResumen([
      sus({ monto: 30000 }),
      sus({ monto: 89900, es_prueba_gratis: true, fecha_fin_prueba: '2026-11-12' }),
    ], HOY);

    assert.equal(r.cantidad_activas, 2);
    assert.equal(r.totales[0].cantidad, 2);
    assert.equal(r.totales[0].gasto_mensual, 30000);
  });

  it('lista los cobros de hoy a 7 días, ordenados', () => {
    const r = calcularResumen([
      sus({ nombre_servicio: 'Ayer', monto: 1, fecha_proximo_cobro: '2026-11-09' }),
      sus({ nombre_servicio: 'En 7', monto: 1, fecha_proximo_cobro: '2026-11-17' }),
      sus({ nombre_servicio: 'Hoy', monto: 1, fecha_proximo_cobro: '2026-11-10' }),
      sus({ nombre_servicio: 'En 8', monto: 1, fecha_proximo_cobro: '2026-11-18' }),
      sus({ nombre_servicio: 'Cancelada', monto: 1, fecha_proximo_cobro: '2026-11-11', estado: 'cancelada' }),
    ], HOY);

    assert.deepEqual(
      r.proximos_cobros.map((s) => [s.nombre_servicio, s.dias_restantes]),
      [['Hoy', 0], ['En 7', 7]],
    );
  });

  it('lista aparte las pruebas gratis que terminan en 7 días', () => {
    const r = calcularResumen([
      sus({ nombre_servicio: 'Prueba', monto: 89900, es_prueba_gratis: true,
        fecha_fin_prueba: '2026-11-12', fecha_proximo_cobro: '2026-11-12' }),
      sus({ nombre_servicio: 'Prueba larga', monto: 1, es_prueba_gratis: true,
        fecha_fin_prueba: '2026-12-30' }),
    ], HOY);

    assert.deepEqual(r.pruebas_por_terminar.map((s) => [s.nombre_servicio, s.dias_restantes]), [['Prueba', 2]]);
    assert.equal(r.proximos_cobros.length, 0);
  });

  it('agrupa el gasto mensual por categoría y moneda', () => {
    const r = calcularResumen([
      sus({ categoria: 'Streaming', monto: 38900 }),
      sus({ categoria: 'Streaming', monto: 26900 }),
      sus({ categoria: 'Música', monto: 19900 }),
      sus({ categoria: 'Diseño', monto: 120000, frecuencia: 'anual' }), // 10.000 al mes
      sus({ categoria: null, monto: 99000 }),
      sus({ categoria: 'Software', monto: 20, moneda: 'USD' }),
      sus({ categoria: 'Cloud gaming', monto: 89900, es_prueba_gratis: true, fecha_fin_prueba: '2026-11-20' }),
      sus({ categoria: 'Gimnasio', monto: 89900, estado: 'cancelada' }),
    ], HOY);

    assert.deepEqual(r.por_categoria, [
      { categoria: 'Streaming', moneda: 'COP', gasto_mensual: 65800, cantidad: 2 },
      { categoria: 'Música', moneda: 'COP', gasto_mensual: 19900, cantidad: 1 },
      { categoria: 'Diseño', moneda: 'COP', gasto_mensual: 10000, cantidad: 1 },
      // La prueba gratis cuenta pero suma 0.
      { categoria: 'Cloud gaming', moneda: 'COP', gasto_mensual: 0, cantidad: 1 },
      // "Sin categoría" va al final aunque gaste más.
      { categoria: null, moneda: 'COP', gasto_mensual: 99000, cantidad: 1 },
      { categoria: 'Software', moneda: 'USD', gasto_mensual: 20, cantidad: 1 },
    ]);
  });

  it('sin suscripciones devuelve todo vacío', () => {
    assert.deepEqual(calcularResumen([], HOY), {
      totales: [], por_categoria: [], cantidad_activas: 0, proximos_cobros: [], pruebas_por_terminar: [],
    });
  });
});

describe('fechas', () => {
  it('valida fechas reales en formato AAAA-MM-DD', () => {
    assert.equal(esFechaValida('2026-02-28'), true);
    assert.equal(esFechaValida('2028-02-29'), true);
    assert.equal(esFechaValida('2026-02-30'), false);
    assert.equal(esFechaValida('2026-13-01'), false);
    assert.equal(esFechaValida('10/11/2026'), false);
    assert.equal(esFechaValida(20261110), false);
  });

  it('cuenta días entre fechas, incluso cruzando meses y años', () => {
    assert.equal(diasEntre('2026-12-30', '2027-01-02'), 3);
    assert.equal(diasEntre('2026-11-10', '2026-11-09'), -1);
  });
});
