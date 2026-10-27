import { HttpError } from '../utils/httpError.js';

// Responde 404 a cualquier ruta que no exista.
export function noEncontrado(req, res) {
  res.status(404).json({ error: 'Ruta no encontrada' });
}

// Manejador central de errores. Express lo reconoce porque recibe 4 parámetros.
// En Express 5, si una función async lanza un error, llega aquí automáticamente.
//
// Regla de seguridad: al cliente solo se le envían mensajes pensados para él.
// Los detalles internos (consultas SQL, rutas de archivos, etc.) se imprimen en
// la consola del servidor, nunca en la respuesta.
// eslint-disable-next-line no-unused-vars
export function manejarErrores(err, req, res, next) {
  if (err instanceof HttpError) {
    return res.status(err.status).json({ error: err.message });
  }

  // El cuerpo de la petición no es un JSON válido (lo detecta express.json()).
  if (err.type === 'entity.parse.failed') {
    return res.status(400).json({ error: 'El cuerpo de la petición no es un JSON válido' });
  }

  // Otros errores 4xx generados por Express (por ejemplo, cuerpo demasiado grande).
  if (err.status >= 400 && err.status < 500 && err.expose) {
    return res.status(err.status).json({ error: err.message });
  }

  console.error(err);
  res.status(500).json({ error: 'Error interno del servidor' });
}
