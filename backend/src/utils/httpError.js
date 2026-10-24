// Error con código HTTP. Los controladores lanzan `new HttpError(409, '...')`
// y el manejador central de errores (middlewares/errorHandler.js) lo convierte
// en la respuesta JSON { error: '...' } con ese código.
export class HttpError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}
