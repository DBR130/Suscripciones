import { query, transaccion } from '../db.js';
import { ESTADOS } from '../middlewares/validaciones.js';
import { centavosAnuales } from '../services/resumen.js';
import { HttpError } from '../utils/httpError.js';

// Columnas que se devuelven al cliente (usuario_id no hace falta: siempre es
// el del token).
export const COLUMNAS = `id, nombre_servicio, monto, moneda, frecuencia, fecha_proximo_cobro,
  es_prueba_gratis, fecha_fin_prueba, dias_aviso, origen, estado, fecha_deteccion, creado_en`;

const MAX_ID = 2147483647; // máximo de una columna INT/SERIAL

// REGLA DE SEGURIDAD: toda consulta filtra por usuario_id = el del token.
// Si la suscripción no existe o es de otro usuario, se responde 404 en ambos
// casos, para no revelar que el id existe.
const NO_ENCONTRADA = 'Suscripción no encontrada';

function idDeLaRuta(req) {
  const id = Number(req.params.id);
  if (!Number.isInteger(id) || id < 1 || id > MAX_ID) throw new HttpError(404, NO_ENCONTRADA);
  return id;
}

// GET /api/suscripciones?estado=activa  (varios: ?estado=activa,marcada_para_cancelar)
export async function listar(req, res) {
  let estados = ESTADOS;
  if (req.query.estado !== undefined) {
    estados = String(req.query.estado).split(',').map((e) => e.trim());
    if (estados.some((e) => !ESTADOS.includes(e))) {
      throw new HttpError(400, `El estado debe ser uno de: ${ESTADOS.join(', ')}`);
    }
  }

  // "= ANY($2)" compara contra un arreglo: estado = 'activa' OR estado = '...'.
  const { rows } = await query(
    `SELECT ${COLUMNAS} FROM suscripciones
     WHERE usuario_id = $1 AND estado = ANY($2)
     ORDER BY fecha_proximo_cobro, id`,
    [req.usuarioId, estados],
  );
  res.json({ suscripciones: rows });
}

// GET /api/suscripciones/:id
export async function obtener(req, res) {
  const { rows } = await query(
    `SELECT ${COLUMNAS} FROM suscripciones WHERE id = $1 AND usuario_id = $2`,
    [idDeLaRuta(req), req.usuarioId],
  );
  if (rows.length === 0) throw new HttpError(404, NO_ENCONTRADA);
  res.json({ suscripcion: rows[0] });
}

// POST /api/suscripciones  (req.body ya validado por validarSuscripcion)
export async function crear(req, res) {
  const s = req.body;
  const { rows } = await query(
    `INSERT INTO suscripciones (usuario_id, nombre_servicio, monto, moneda, frecuencia,
       fecha_proximo_cobro, es_prueba_gratis, fecha_fin_prueba, dias_aviso, origen, fecha_deteccion)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10::varchar,
       CASE WHEN $10::varchar = 'notificacion' THEN NOW() END)
     RETURNING ${COLUMNAS}`,
    [req.usuarioId, s.nombre_servicio, s.monto, s.moneda, s.frecuencia,
      s.fecha_proximo_cobro, s.es_prueba_gratis, s.fecha_fin_prueba, s.dias_aviso, s.origen],
  );
  res.status(201).json({ suscripcion: rows[0] });
}

// PUT /api/suscripciones/:id
// Edita los datos. El estado se cambia aparte (PATCH .../estado) y el origen
// no se modifica.
export async function actualizar(req, res) {
  const s = req.body;
  const { rows } = await query(
    `UPDATE suscripciones
     SET nombre_servicio = $3, monto = $4, moneda = $5, frecuencia = $6,
         fecha_proximo_cobro = $7, es_prueba_gratis = $8, fecha_fin_prueba = $9, dias_aviso = $10
     WHERE id = $1 AND usuario_id = $2
     RETURNING ${COLUMNAS}`,
    [idDeLaRuta(req), req.usuarioId, s.nombre_servicio, s.monto, s.moneda, s.frecuencia,
      s.fecha_proximo_cobro, s.es_prueba_gratis, s.fecha_fin_prueba, s.dias_aviso],
  );
  if (rows.length === 0) throw new HttpError(404, NO_ENCONTRADA);
  res.json({ suscripcion: rows[0] });
}

// DELETE /api/suscripciones/:id
export async function eliminar(req, res) {
  const { rowCount } = await query(
    'DELETE FROM suscripciones WHERE id = $1 AND usuario_id = $2',
    [idDeLaRuta(req), req.usuarioId],
  );
  if (rowCount === 0) throw new HttpError(404, NO_ENCONTRADA);
  res.status(204).end(); // 204 = éxito sin contenido
}

// PATCH /api/suscripciones/:id/estado  {estado}
// Al pasar a "cancelada" se guarda una fila en cancelaciones con el ahorro
// anual proyectado (para la pantalla de ahorro de una fase siguiente). Si se
// reactiva, esa fila se borra. Todo en una transacción.
export async function cambiarEstado(req, res) {
  const id = idDeLaRuta(req);
  const { estado } = req.body;

  const suscripcion = await transaccion(async (client) => {
    // FOR UPDATE bloquea la fila hasta terminar, por si llegan dos cambios a la vez.
    const { rows } = await client.query(
      `SELECT ${COLUMNAS} FROM suscripciones WHERE id = $1 AND usuario_id = $2 FOR UPDATE`,
      [id, req.usuarioId],
    );
    const anterior = rows[0];
    if (!anterior) throw new HttpError(404, NO_ENCONTRADA);
    if (anterior.estado === estado) return anterior;

    const actualizada = await client.query(
      `UPDATE suscripciones SET estado = $1 WHERE id = $2 RETURNING ${COLUMNAS}`,
      [estado, id],
    );
    if (estado === 'cancelada') {
      await client.query(
        'INSERT INTO cancelaciones (suscripcion_id, ahorro_proyectado_anual) VALUES ($1, $2)',
        [id, centavosAnuales(anterior) / 100],
      );
    } else if (anterior.estado === 'cancelada') {
      await client.query('DELETE FROM cancelaciones WHERE suscripcion_id = $1', [id]);
    }
    return actualizada.rows[0];
  });

  res.json({ suscripcion });
}
