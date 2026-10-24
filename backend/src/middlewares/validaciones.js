// Validación de los datos que llegan en el cuerpo (body) de la petición.
//
// Aunque la app Flutter ya valida los formularios, el servidor debe volver a
// validar: cualquiera puede llamar a la API directamente (curl, Thunder Client)
// sin pasar por la app.
//
// Si los datos son válidos, se dejan limpios en req.body y se llama a next()
// para continuar con el controlador. Si no, se responde 400 con el motivo.

// Mismo patrón que Validators.email en lib/utils/validators.dart.
const REGEX_CORREO = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;

// Mismo mínimo que Validators.password en Flutter.
const PASSWORD_MIN = 6;
// bcrypt solo usa los primeros 72 bytes de la contraseña; el resto lo ignora.
const PASSWORD_MAX = 72;

// Límites iguales a los tamaños de las columnas en la tabla usuarios.
const NOMBRE_MAX = 100;
const CORREO_MAX = 150;

function texto(valor) {
  return typeof valor === 'string' ? valor : '';
}

// Devuelve el correo limpio (sin espacios y en minúsculas) o un mensaje de error.
function validarCorreo(valor) {
  const correo = texto(valor).trim().toLowerCase();
  if (!correo) return { error: 'El correo es obligatorio' };
  if (correo.length > CORREO_MAX || !REGEX_CORREO.test(correo)) {
    return { error: 'Correo no válido' };
  }
  return { correo };
}

export function validarRegistro(req, res, next) {
  const body = req.body ?? {};

  const nombre = texto(body.nombre).trim();
  if (!nombre) return res.status(400).json({ error: 'El nombre es obligatorio' });
  if (nombre.length > NOMBRE_MAX) {
    return res.status(400).json({ error: `El nombre admite máximo ${NOMBRE_MAX} caracteres` });
  }

  const { correo, error } = validarCorreo(body.correo);
  if (error) return res.status(400).json({ error });

  // La contraseña no se recorta: los espacios también cuentan.
  const password = texto(body.password);
  if (password.length < PASSWORD_MIN) {
    return res.status(400).json({ error: `La contraseña debe tener mínimo ${PASSWORD_MIN} caracteres` });
  }
  if (Buffer.byteLength(password) > PASSWORD_MAX) {
    return res.status(400).json({ error: 'La contraseña es demasiado larga' });
  }

  req.body = { nombre, correo, password };
  next();
}

export function validarLogin(req, res, next) {
  const body = req.body ?? {};

  const { correo, error } = validarCorreo(body.correo);
  if (error) return res.status(400).json({ error });

  const password = texto(body.password);
  if (!password) return res.status(400).json({ error: 'La contraseña es obligatoria' });

  req.body = { correo, password };
  next();
}
