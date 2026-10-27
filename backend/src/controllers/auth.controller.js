import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';

import { query } from '../db.js';
import { HttpError } from '../utils/httpError.js';

// Número de "rondas" de bcrypt: cuántas veces se repite el cálculo del hash.
// Más rondas = más lento para un atacante que intente adivinar contraseñas.
// 10 es el valor recomendado para empezar.
const RONDAS_BCRYPT = 10;

// Mensaje único para el login fallido: no se dice si falló el correo o la
// contraseña, así nadie puede averiguar qué correos están registrados.
const ERROR_LOGIN = 'Correo o contraseña incorrectos';

// Hash de una contraseña cualquiera. Se usa cuando el correo no existe para
// que la respuesta tarde lo mismo que con un correo real (ver login()).
const HASH_FICTICIO = bcrypt.hashSync('contraseña-ficticia', RONDAS_BCRYPT);

// Código de error de PostgreSQL cuando se viola una restricción UNIQUE.
const PG_UNIQUE_VIOLATION = '23505';

// Crea el token JWT. "sub" (subject) guarda el id del usuario.
// El token se firma con JWT_SECRET y deja de ser válido a los 7 días.
function crearToken(usuarioId) {
  return jwt.sign({ sub: String(usuarioId) }, process.env.JWT_SECRET, {
    expiresIn: '7d',
  });
}

// POST /api/auth/registro
export async function registro(req, res) {
  // req.body ya viene validado y limpio por middlewares/validaciones.js
  const { nombre, correo, password } = req.body;

  // Nunca se guarda la contraseña tal cual: se guarda su hash. Un hash no se
  // puede "deshacer"; para comprobarla luego se usa bcrypt.compare().
  const passwordHash = await bcrypt.hash(password, RONDAS_BCRYPT);

  try {
    // RETURNING devuelve las columnas de la fila recién insertada.
    // password_hash NO se incluye para no enviarlo nunca al cliente.
    const { rows } = await query(
      `INSERT INTO usuarios (nombre, correo, password_hash)
       VALUES ($1, $2, $3)
       RETURNING id, nombre, correo`,
      [nombre, correo, passwordHash],
    );
    const usuario = rows[0];
    res.status(201).json({ token: crearToken(usuario.id), usuario });
  } catch (err) {
    // La columna correo es UNIQUE: si ya existe, PostgreSQL rechaza el INSERT.
    if (err.code === PG_UNIQUE_VIOLATION) {
      throw new HttpError(409, 'Ya existe una cuenta con ese correo');
    }
    throw err;
  }
}

// POST /api/auth/login
export async function login(req, res) {
  const { correo, password } = req.body;

  const { rows } = await query(
    'SELECT id, nombre, correo, password_hash FROM usuarios WHERE correo = $1',
    [correo],
  );
  const fila = rows[0];

  // Se compara siempre (aunque el usuario no exista) para que el tiempo de
  // respuesta no delate si el correo está registrado.
  const coincide = await bcrypt.compare(password, fila?.password_hash ?? HASH_FICTICIO);
  if (!fila || !coincide) {
    throw new HttpError(401, ERROR_LOGIN);
  }

  const usuario = { id: fila.id, nombre: fila.nombre, correo: fila.correo };
  res.json({ token: crearToken(usuario.id), usuario });
}

// GET /api/auth/me  (protegida con middlewares/auth.js)
export async function me(req, res) {
  const { rows } = await query(
    'SELECT id, nombre, correo FROM usuarios WHERE id = $1',
    [req.usuarioId],
  );
  // El token puede ser válido pero el usuario ya no existir (cuenta borrada).
  if (rows.length === 0) {
    throw new HttpError(401, 'Token inválido o expirado');
  }
  res.json({ usuario: rows[0] });
}
