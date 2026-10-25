// Utilidades para fechas sin hora, en formato "AAAA-MM-DD" (igual que DATE en
// PostgreSQL). Se calcula en UTC para que los cambios de horario no muevan
// los días.

const FORMATO = /^\d{4}-\d{2}-\d{2}$/;
const MS_POR_DIA = 24 * 60 * 60 * 1000;

function aUtc(fecha) {
  const [anio, mes, dia] = fecha.split('-').map(Number);
  return Date.UTC(anio, mes - 1, dia);
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

/** Fecha de hoy en la zona horaria del servidor (Colombia en el portátil). */
export function hoyLocal(ahora = new Date()) {
  const pad = (n) => String(n).padStart(2, '0');
  return `${ahora.getFullYear()}-${pad(ahora.getMonth() + 1)}-${pad(ahora.getDate())}`;
}

/** Días desde `desde` hasta `hasta` (negativo si `hasta` ya pasó). */
export function diasEntre(desde, hasta) {
  return Math.round((aUtc(hasta) - aUtc(desde)) / MS_POR_DIA);
}
