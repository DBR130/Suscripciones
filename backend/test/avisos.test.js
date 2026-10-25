// Pruebas de funciones puras: avance de fechas y cálculo de avisos.
import assert from 'node:assert/strict';
import { describe, it } from 'node:test';

import { calcularAvisos } from '../src/services/avisos.js';
import { avanzarCiclo, hoyColombia, sumarMeses } from '../src/utils/fechas.js';

describe('avanzarCiclo', () => {
  it('semanal suma 7 días, incluso cruzando mes y año', () => {
    assert.equal(avanzarCiclo('2026-03-10', 'semanal'), '2026-03-17');
    assert.equal(avanzarCiclo('2026-12-28', 'semanal'), '2027-01-04');
  });

  it('mensual respeta el fin de mes', () => {
    assert.equal(avanzarCiclo('2026-03-15', 'mensual'), '2026-04-15');
    assert.equal(avanzarCiclo('2026-01-31', 'mensual'), '2026-02-28');
    assert.equal(avanzarCiclo('2028-01-31', 'mensual'), '2028-02-29'); // bisiesto
    assert.equal(avanzarCiclo('2026-03-31', 'mensual'), '2026-04-30');
    assert.equal(avanzarCiclo('2026-12-15', 'mensual'), '2027-01-15');
  });

  it('anual suma un año (29 feb pasa a 28 feb)', () => {
    assert.equal(avanzarCiclo('2026-05-20', 'anual'), '2027-05-20');
    assert.equal(avanzarCiclo('2028-02-29', 'anual'), '2029-02-28');
  });

  it('sumarMeses acepta varios meses', () => {
    assert.equal(sumarMeses('2026-01-31', 13), '2027-02-28');
  });

  it('hoyColombia usa la zona America/Bogota', () => {
    // 2026-03-01 03:00 UTC = 2026-02-28 22:00 en Colombia (UTC-5).
    assert.equal(hoyColombia(new Date('2026-03-01T03:00:00Z')), '2026-02-28');
    assert.equal(hoyColombia(new Date('2026-03-01T06:00:00Z')), '2026-03-01');
  });
});

describe('calcularAvisos', () => {
  const HOY = '2026-03-10';
  let id = 1;
  const sus = (datos) => ({
    id: id++, nombre_servicio: 'Servicio', monto: 10000, moneda: 'COP', frecuencia: 'mensual',
    fecha_proximo_cobro: '2026-04-30', es_prueba_gratis: false, fecha_fin_prueba: null,
    dias_aviso: null, estado: 'activa', ...datos,
  });

  it('incluye cobros dentro de los días de aviso (propios o globales)', () => {
    const avisos = calcularAvisos([
      sus({ nombre_servicio: 'En 2 días', fecha_proximo_cobro: '2026-03-12' }),
      sus({ nombre_servicio: 'En 5 días', fecha_proximo_cobro: '2026-03-15' }),
      sus({ nombre_servicio: 'En 5 días con aviso de 7', fecha_proximo_cobro: '2026-03-15', dias_aviso: 7 }),
      sus({ nombre_servicio: 'Hoy', fecha_proximo_cobro: '2026-03-10' }),
      sus({ nombre_servicio: 'Cancelada', fecha_proximo_cobro: '2026-03-11', estado: 'cancelada' }),
    ], [], 3, HOY);

    assert.deepEqual(
      avisos.map((a) => [a.nombre_servicio, a.tipo, a.dias_restantes, a.fecha_aviso]),
      [
        ['Hoy', 'proximo_cobro', 0, '2026-03-07'],
        ['En 2 días', 'proximo_cobro', 2, '2026-03-09'],
        ['En 5 días con aviso de 7', 'proximo_cobro', 5, '2026-03-08'],
      ].sort((a, b) => b[3].localeCompare(a[3]) || a[2] - b[2]),
    );
  });

  it('las pruebas gratis avisan por su fecha de fin', () => {
    const [aviso] = calcularAvisos([
      sus({ es_prueba_gratis: true, fecha_fin_prueba: '2026-03-12', fecha_proximo_cobro: '2026-03-12' }),
    ], [], 3, HOY);
    assert.equal(aviso.tipo, 'fin_prueba_gratis');
    assert.equal(aviso.dias_restantes, 2);
  });

  it('incluye cambios de precio de los últimos 30 días', () => {
    const avisos = calcularAvisos([], [
      { suscripcion_id: 1, nombre_servicio: 'Adobe', monto_anterior: 41900, monto_nuevo: 47900,
        moneda: 'COP', frecuencia: 'mensual', fecha_cambio: '2026-03-01' },
      { suscripcion_id: 2, nombre_servicio: 'Viejo', monto_anterior: 1, monto_nuevo: 2,
        moneda: 'COP', frecuencia: 'mensual', fecha_cambio: '2026-01-15' },
    ], 3, HOY);
    assert.equal(avisos.length, 1);
    assert.equal(avisos[0].tipo, 'cambio_precio');
    assert.equal(avisos[0].monto_anterior, 41900);
    assert.equal(avisos[0].monto, 47900);
  });
});
