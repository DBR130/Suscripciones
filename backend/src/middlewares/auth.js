import jwt from 'jsonwebtoken';

import { HttpError } from '../utils/httpError.js';

// Protege las rutas que requieren sesión iniciada.
//
// La app envía el token en el encabezado:
//   Authorization: Bearer eyJhbGciOi...
// Si el token es válido y no ha expirado, se guarda el id del usuario en
// req.usuarioId para que el controlador sepa quién hace la petición.
export function verificarToken(req, res, next) {
  const [tipo, token] = (req.headers.authorization ?? '').split(' ');
  if (tipo !== 'Bearer' || !token) {
    throw new HttpError(401, 'Token no proporcionado');
  }

  try {
    // jwt.verify comprueba la firma (que el token lo creó este servidor con
    // JWT_SECRET) y la fecha de expiración. Si algo falla, lanza un error.
    const payload = jwt.verify(token, process.env.JWT_SECRET);
    req.usuarioId = Number(payload.sub);
    next();
  } catch {
    throw new HttpError(401, 'Token inválido o expirado');
  }
}
