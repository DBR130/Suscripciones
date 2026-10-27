// Tareas automáticas del servidor.
import cron from 'node-cron';

import { procesarCobros } from './services/cobros.js';
import { ZONA_COLOMBIA, hoyColombia } from './utils/fechas.js';

async function correrCobros(motivo) {
  try {
    const hoy = hoyColombia();
    const { suscripciones, pagos } = await procesarCobros(hoy);
    console.log(`[cobros] ${motivo} (${hoy}): ${pagos} pagos registrados en ${suscripciones} suscripciones`);
  } catch (err) {
    // Un error aquí no debe tumbar la API; se intenta de nuevo en la próxima.
    console.error(`[cobros] ${motivo}: falló el proceso de cobros:`, err.message);
  }
}

export function iniciarTareas() {
  // Al arrancar: el portátil pudo estar apagado varios días.
  correrCobros('al arrancar');

  // Todos los días a las 00:05 hora de Colombia ("5 0 * * *" = minuto 5, hora 0).
  cron.schedule('5 0 * * *', () => correrCobros('tarea diaria'), {
    timezone: ZONA_COLOMBIA,
    noOverlap: true,
  });
}
