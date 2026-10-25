import { query, transaccion } from '../db.js';
import { ESTADOS } from '../middlewares/validaciones.js';
import { centavosAnuales } from '../services/resumen.js';
import { HttpError } from '../utils/httpError.js';

// Columnas que se devuelven al cliente (usuario_id no hace falta: siempre es
// el del token).
export const COLUMNAS = `id, nombre_servicio, categoria, monto, moneda, frecuencia, fecha_proximo_cobro,
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
// Incluye los 3 últimos pagos y el total pagado (pantalla 09 del diseño).
export async function obtener(req, res) {
  const id = idDeLaRuta(req);
  const { rows } = await query(
    `SELECT ${COLUMNAS} FROM suscripciones WHERE id = $1 AND usuario_id = $2`,
    [id, req.usuarioId],
  );
  if (rows.length === 0) throw new HttpError(404, NO_ENCONTRADA);

  // Ya se comprobó arriba que la suscripción es del usuario.
  const [pagos, total, cambio] = await Promise.all([
    query(
      `SELECT fecha_pago, monto FROM historial_pagos
       WHERE suscripcion_id = $1 ORDER BY fecha_pago DESC, id DESC LIMIT 3`,
      [id],
    ),
    query('SELECT COALESCE(SUM(monto), 0) AS total FROM historial_pagos WHERE suscripcion_id = $1', [id]),
    query(
      `SELECT monto_anterior, monto_nuevo, fecha_cambio FROM cambios_precio
       WHERE suscripcion_id = $1 ORDER BY fecha_cambio DESC, id DESC LIMIT 1`,
      [id],
    ),
  ]);
  res.json({
    suscripcion: rows[0],
    pagos: pagos.rows,
    pagado_total: total.rows[0].total,
    ultimo_cambio_precio: cambio.rows[0] ?? null,
  });
}

// POST /api/suscripciones  (req.body ya validado por validarSuscripcion)
export async function crear(req, res) {
  const s = req.body;
  const { rows } = await query(
    `INSERT INTO suscripciones (usuario_id, nombre_servicio, monto, moneda, frecuencia,
       fecha_proximo_cobro, es_prueba_gratis, fecha_fin_prueba, dias_aviso, origen, categoria,
       fecha_deteccion)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10::varchar, $11,
       CASE WHEN $10::varchar = 'notificacion' THEN NOW() END)
     RETURNING ${COLUMNAS}`,
    [req.usuarioId, s.nombre_servicio, s.monto, s.moneda, s.frecuencia,
      s.fecha_proximo_cobro, s.es_prueba_gratis, s.fecha_fin_prueba, s.dias_aviso, s.origen,
      s.categoria],
  );
  res.status(201).json({ suscripcion: rows[0] });
}

// PUT /api/suscripciones/:id
// Edita los datos. El estado se cambia aparte (PATCH .../estado) y el origen
// no se modifica. Si el monto cambia, queda registrado en cambios_precio (RF08).
export async function actualizar(req, res) {
  const id = idDeLaRuta(req);
  const s = req.body;
  const suscripcion = await transaccion(async (client) => {
    const anterior = await client.query(
      'SELECT monto FROM suscripciones WHERE id = $1 AND usuario_id = $2 FOR UPDATE',
      [id, req.usuarioId],
    );
    if (anterior.rows.length === 0) throw new HttpError(404, NO_ENCONTRADA);

    const { rows } = await client.query(
      `UPDATE suscripciones
       SET nombre_servicio = $3, monto = $4, moneda = $5, frecuencia = $6,
           fecha_proximo_cobro = $7, es_prueba_gratis = $8, fecha_fin_prueba = $9, dias_aviso = $10,
           categoria = $11
       WHERE id = $1 AND usuario_id = $2
       RETURNING ${COLUMNAS}`,
      [id, req.usuarioId, s.nombre_servicio, s.monto, s.moneda, s.frecuencia,
        s.fecha_proximo_cobro, s.es_prueba_gratis, s.fecha_fin_prueba, s.dias_aviso, s.categoria],
    );

    const montoAnterior = anterior.rows[0].monto;
    if (rows[0].monto !== montoAnterior) {
      await client.query(
        'INSERT INTO cambios_precio (suscripcion_id, monto_anterior, monto_nuevo) VALUES ($1, $2, $3)',
        [id, montoAnterior, rows[0].monto],
      );
    }
    return rows[0];
  });
  res.json({ suscripcion });
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
