import { query, transaccion } from '../db.js';
import { FRECUENCIAS, limpiarSuscripcion } from '../middlewares/validaciones.js';
import {
  COLUMNAS_CANDIDATO, enlazarPagos, procesarPagos, siguienteCobro,
} from '../services/detecciones.js';
import { hoyColombia } from '../utils/fechas.js';
import { HttpError } from '../utils/httpError.js';
import { COLUMNAS } from './suscripciones.controller.js';

const ESTADOS_CANDIDATO = ['pendiente', 'confirmada', 'descartada'];
const MAX_ID = 2147483647;
// Mismo criterio que en suscripciones: 404 si no existe o es de otro usuario.
const NO_ENCONTRADO = 'Candidato no encontrado';

function idDeLaRuta(req) {
  const id = Number(req.params.id);
  if (!Number.isInteger(id) || id < 1 || id > MAX_ID) throw new HttpError(404, NO_ENCONTRADO);
  return id;
}

/** Lee y bloquea un candidato pendiente del usuario (404 / 409 si no se puede). */
async function candidatoPendiente(client, id, usuarioId) {
  const { rows } = await client.query(
    `SELECT ${COLUMNAS_CANDIDATO} FROM candidatos_suscripcion
     WHERE id = $1 AND usuario_id = $2 FOR UPDATE`,
    [id, usuarioId],
  );
  const candidato = rows[0];
  if (!candidato) throw new HttpError(404, NO_ENCONTRADO);
  if (candidato.estado !== 'pendiente') {
    throw new HttpError(409, `Este candidato ya está ${candidato.estado}`);
  }
  return candidato;
}

// POST /api/detecciones/pagos  {pagos: [...]}  (validado por validarPagosDetectados)
export async function registrarPagos(req, res) {
  res.json(await procesarPagos(req.usuarioId, req.body.pagos));
}

// GET /api/detecciones/candidatos?estado=pendiente  (por defecto, los pendientes)
// num_pagos: cuántos pagos detectados hay de ese comercio.
export async function listarCandidatos(req, res) {
  const estados = req.query.estado === undefined
    ? ['pendiente']
    : String(req.query.estado).split(',').map((e) => e.trim());
  if (estados.some((e) => !ESTADOS_CANDIDATO.includes(e))) {
    throw new HttpError(400, `El estado debe ser uno de: ${ESTADOS_CANDIDATO.join(', ')}`);
  }
  const { rows } = await query(
    `SELECT ${COLUMNAS_CANDIDATO.replace(/(\w+)/g, 'c.$1')},
       (SELECT count(*)::int FROM pagos_detectados p
        WHERE p.usuario_id = c.usuario_id
          AND lower(p.comercio_normalizado) = lower(c.comercio_normalizado)) AS num_pagos
     FROM candidatos_suscripcion c
     WHERE c.usuario_id = $1 AND c.estado = ANY($2)
     ORDER BY c.creado_en DESC, c.id DESC`,
    [req.usuarioId, estados],
  );
  res.json({ candidatos: rows });
}

// POST /api/detecciones/candidatos/:id/confirmar
// Cuerpo opcional con los datos corregidos por el usuario (los mismos campos
// que una suscripción). Lo que no venga se toma del candidato. Crea la
// suscripción con origen 'notificacion' y enlaza los pagos detectados.
export async function confirmarCandidato(req, res) {
  const id = idDeLaRuta(req);
  const resultado = await transaccion(async (client) => {
    const c = await candidatoPendiente(client, id, req.usuarioId);
    const cambios = req.body ?? {};
    const frecuencia = cambios.frecuencia ?? c.frecuencia_estimada;
    const { datos, error } = limpiarSuscripcion({
      nombre_servicio: c.comercio_normalizado,
      monto: c.monto,
      moneda: c.moneda,
      // Si el usuario cambió la frecuencia, el próximo cobro se calcula con la
      // suya (si no es válida, limpiarSuscripcion responde el error).
      fecha_proximo_cobro: FRECUENCIAS.includes(frecuencia)
        ? siguienteCobro(c.fecha_ultimo_pago, frecuencia, hoyColombia())
        : undefined,
      ...cambios,
      frecuencia,
      origen: 'notificacion',
    });
    if (error) throw new HttpError(400, error);

    const { rows } = await client.query(
      `INSERT INTO suscripciones (usuario_id, nombre_servicio, monto, moneda, frecuencia,
         fecha_proximo_cobro, es_prueba_gratis, fecha_fin_prueba, dias_aviso, origen, categoria,
         fecha_deteccion)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11,
         -- fecha_deteccion = cuando se detectó (se creó el candidato).
         (SELECT creado_en FROM candidatos_suscripcion WHERE id = $12))
       RETURNING ${COLUMNAS}`,
      [req.usuarioId, datos.nombre_servicio, datos.monto, datos.moneda, datos.frecuencia,
        datos.fecha_proximo_cobro, datos.es_prueba_gratis, datos.fecha_fin_prueba, datos.dias_aviso,
        datos.origen, datos.categoria, id],
    );
    const suscripcion = rows[0];

    const candidato = (await client.query(
      `UPDATE candidatos_suscripcion SET estado = 'confirmada', suscripcion_id = $2
       WHERE id = $1 RETURNING ${COLUMNAS_CANDIDATO}`,
      [id, suscripcion.id],
    )).rows[0];
    const pagosEnlazados = await enlazarPagos(client, req.usuarioId, c.comercio_normalizado, suscripcion);
    return { suscripcion, candidato, pagos_enlazados: pagosEnlazados };
  });
  res.status(201).json(resultado);
}

// POST /api/detecciones/candidatos/:id/descartar
// El comercio no se vuelve a proponer.
export async function descartarCandidato(req, res) {
  const id = idDeLaRuta(req);
  const candidato = await transaccion(async (client) => {
    await candidatoPendiente(client, id, req.usuarioId);
    return (await client.query(
      `UPDATE candidatos_suscripcion SET estado = 'descartada'
       WHERE id = $1 RETURNING ${COLUMNAS_CANDIDATO}`,
      [id],
    )).rows[0];
  });
  res.json({ candidato });
}
