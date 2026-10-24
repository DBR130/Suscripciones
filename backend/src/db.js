// Conexión a PostgreSQL.
//
// Un "Pool" es un grupo de conexiones abiertas a la base de datos que se
// reutilizan. Abrir una conexión es lento, así que en lugar de abrir y cerrar
// una por cada petición, el Pool las mantiene listas y las presta cuando se
// necesitan.
import pg from 'pg';

export const pool = new pg.Pool({
  // Toda la información (usuario, contraseña, host, puerto y base de datos)
  // viene en una sola cadena definida en el archivo .env.
  connectionString: process.env.DATABASE_URL,
});

// Si una conexión inactiva del Pool falla (por ejemplo, se reinicia
// PostgreSQL), se registra el error en lugar de tumbar el servidor.
pool.on('error', (err) => {
  console.error('Error inesperado en el pool de PostgreSQL:', err.message);
});

/**
 * Ejecuta una consulta SQL.
 *
 * IMPORTANTE: los valores NUNCA se pegan dentro del texto SQL. Se escriben
 * marcadores $1, $2, ... y los valores se pasan aparte en el arreglo `params`.
 * Así PostgreSQL los trata como datos y no como código, lo que evita la
 * "inyección SQL" (que alguien escriba SQL malicioso en un campo del formulario).
 *
 * Ejemplo: query('SELECT * FROM usuarios WHERE correo = $1', [correo])
 */
export function query(text, params) {
  return pool.query(text, params);
}
