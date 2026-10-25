import bcrypt from 'bcryptjs';

import { query } from '../db.js';
import { HttpError } from '../utils/httpError.js';

// GET /api/usuarios/me/preferencias
export async function obtenerPreferencias(req, res) {
  const { rows } = await query(
    'SELECT dias_anticipacion_recordatorio FROM usuarios WHERE id = $1',
    [req.usuarioId],
  );
  if (rows.length === 0) throw new HttpError(401, 'Token inválido o expirado');
  res.json({ preferencias: rows[0] });
}

// PUT /api/usuarios/me/preferencias  {dias_anticipacion_recordatorio}
export async function actualizarPreferencias(req, res) {
  const { rows } = await query(
    `UPDATE usuarios SET dias_anticipacion_recordatorio = $1 WHERE id = $2
     RETURNING dias_anticipacion_recordatorio`,
    [req.body.dias_anticipacion_recordatorio, req.usuarioId],
  );
  if (rows.length === 0) throw new HttpError(401, 'Token inválido o expirado');
  res.json({ preferencias: rows[0] });
}

// DELETE /api/usuarios/me  {password}
// Elimina la cuenta y TODOS sus datos (RF13). Gracias a ON DELETE CASCADE,
// PostgreSQL borra también sus suscripciones, pagos, cancelaciones y avisos.
export async function eliminarCuenta(req, res) {
  const { rows } = await query('SELECT password_hash FROM usuarios WHERE id = $1', [req.usuarioId]);
  if (rows.length === 0) throw new HttpError(401, 'Token inválido o expirado');

  // Se pide la contraseña para que nadie con el celular desbloqueado pueda
  // borrar la cuenta por accidente. 403 (y no 401) porque la sesión sí es
  // válida: la app no debe cerrar sesión por esto.
  const coincide = await bcrypt.compare(req.body.password, rows[0].password_hash);
  if (!coincide) throw new HttpError(403, 'Contraseña incorrecta');

  await query('DELETE FROM usuarios WHERE id = $1', [req.usuarioId]);
  res.status(204).end();
}
