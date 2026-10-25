// Utilidades para fechas sin hora, en formato "AAAA-MM-DD" (igual que DATE en
// PostgreSQL). Se calcula en UTC para que los cambios de horario no muevan
// los días.

const FORMATO = /^\d{4}-\d{2}-\d{2}$/;
const MS_POR_DIA = 24 * 60 * 60 * 1000;
export const ZONA_COLOMBIA = 'America/Bogota';

function aUtc(fecha) {
  const [anio, mes, dia] = fecha.split('-').map(Number);
  return Date.UTC(anio, mes - 1, dia);
}

function desdeUtc(ms) {
  return new Date(ms).toISOString().slice(0, 10);
}

/** true si `valor` es un texto "AAAA-MM-DD" con una fecha que existe. */
export function esFechaValida(valor) {
  if (typeof valor !== 'string' || !FORMATO.test(valor)) return false;
  const [anio, mes, dia] = valor.split('-').map(Number);
  const d = new Date(aUtc(valor));
  // Rechaza fechas como 2026-02-30, que Date "corrige" a otro día.
  return anio >= 2000 && anio <= 2100
    && d.getUTCFullYear() === anio && d.getUTCMonth() === mes - 1 && d.getUTCDate() === dia;
}

/**
 * Fecha de hoy en Colombia, sin importar la zona horaria del PC donde corra
 * el servidor. "en-CA" formatea como AAAA-MM-DD.
 */
export function hoyColombia(ahora = new Date()) {
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: ZONA_COLOMBIA, year: 'numeric', month: '2-digit', day: '2-digit',
  }).format(ahora);
}

/** Días desde `desde` hasta `hasta` (negativo si `hasta` ya pasó). */
export function diasEntre(desde, hasta) {
  return Math.round((aUtc(hasta) - aUtc(desde)) / MS_POR_DIA);
}

export function sumarDias(fecha, dias) {
  return desdeUtc(aUtc(fecha) + dias * MS_POR_DIA);
}

/**
 * Suma meses respetando el fin de mes: si el día no existe en el mes de
 * llegada, se usa el último día (31 ene + 1 mes = 28 o 29 feb).
 */
export function sumarMeses(fecha, meses) {
  const [anio, mes, dia] = fecha.split('-').map(Number);
  const total = (mes - 1) + meses;
  const anioNuevo = anio + Math.floor(total / 12);
  const mesNuevo = ((total % 12) + 12) % 12; // 0-11
  // Día 0 del mes siguiente = último día de este mes.
  const ultimoDia = new Date(Date.UTC(anioNuevo, mesNuevo + 1, 0)).getUTCDate();
  return desdeUtc(Date.UTC(anioNuevo, mesNuevo, Math.min(dia, ultimoDia)));
}

/** Fecha del siguiente cobro según la frecuencia. */
export function avanzarCiclo(fecha, frecuencia) {
  switch (frecuencia) {
    case 'semanal': return sumarDias(fecha, 7);
    case 'mensual': return sumarMeses(fecha, 1);
    case 'anual': return sumarMeses(fecha, 12);
    default: throw new Error(`Frecuencia desconocida: ${frecuencia}`);
  }
}
