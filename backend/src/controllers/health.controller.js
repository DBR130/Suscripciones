import { query } from '../db.js';

// GET /api/health
// Sirve para comprobar que la API está viva y que puede hablar con PostgreSQL.
export async function health(req, res) {
  try {
    await query('SELECT 1');
    res.json({ ok: true });
  } catch (err) {
    console.error('Health check: sin conexión a la base de datos:', err.message);
    // 503 = "servicio no disponible".
    res.status(503).json({ ok: false, error: 'Sin conexión a la base de datos' });
  }
}
