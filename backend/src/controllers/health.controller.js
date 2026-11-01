import { query } from '../db.js';

// Si la base no contesta en este tiempo, el health check responde igual (503)
// en vez de quedarse esperando.
export const LIMITE_HEALTH_MS = 5000;

// GET /api/health
// Sirve para comprobar que la API está viva y que puede hablar con PostgreSQL.
// Es la ruta que se abre para despertar el servidor en Render (y que Render
// usa como health check): no requiere sesión y responde en pocos segundos.
export async function health(req, res) {
  let limite;
  try {
    await Promise.race([
      query('SELECT 1'),
      new Promise((_, rechazar) => {
        limite = setTimeout(() => rechazar(new Error('la base de datos no respondió a tiempo')), LIMITE_HEALTH_MS);
      }),
    ]);
    res.json({ ok: true });
  } catch (err) {
    console.error('Health check: sin conexión a la base de datos:', err.message);
    // 503 = "servicio no disponible".
    res.status(503).json({ ok: false, error: 'Sin conexión a la base de datos' });
  } finally {
    clearTimeout(limite);
  }
}
