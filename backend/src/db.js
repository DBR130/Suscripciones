// Conexión a PostgreSQL.
//
// Un "Pool" es un grupo de conexiones abiertas a la base de datos que se
// reutilizan. Abrir una conexión es lento, así que en lugar de abrir y cerrar
// una por cada petición, el Pool las mantiene listas y las presta cuando se
// necesitan.
import pg from 'pg';

// Cómo convierte "pg" algunos tipos de PostgreSQL a JavaScript:
// - NUMERIC (montos): por defecto llega como texto ("45900.00") para no perder
//   precisión. Con 12 dígitos y 2 decimales un número de JS basta, así que se
//   convierte a número para que la API devuelva 45900 y no "45900.00".
// - DATE: por defecto se convierte a un Date a la medianoche de la zona horaria
//   del PC, y al enviarlo como JSON puede cambiar de día. Se deja como el texto
//   "AAAA-MM-DD" que manda PostgreSQL.
const OID_NUMERIC = 1700;
const OID_DATE = 1082;
pg.types.setTypeParser(OID_NUMERIC, (valor) => Number(valor));
pg.types.setTypeParser(OID_DATE, (valor) => valor);

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

/**
 * Ejecuta varias consultas como una sola unidad (transacción): si alguna
 * falla, se deshacen todas. `fn` recibe un cliente y debe usar client.query().
 */
export async function transaccion(fn) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const resultado = await fn(client);
    await client.query('COMMIT');
    return resultado;
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}
