// Detección automática de suscripciones a partir de pagos detectados en las
// notificaciones del celular (RF02, RF03).
//
// Al backend llegan solo los campos que extrajo el parser del celular
// (comercio, monto, moneda, fecha, banco y una huella); nunca el texto.
import { transaccion } from '../db.js';
import { avanzarCiclo, diasEntre } from '../utils/fechas.js';
import { buscarGuia, normalizar } from './guias.js';
import { ESTADOS_EN_CURSO } from './resumen.js';

/** Caso c): dos pagos son "del mismo monto" si difieren máximo un 10 %. */
export const TOLERANCIA_MONTOS = 0.1;

/**
 * Caso a): por debajo de esta variación no es un cambio de precio, sino la
 * tasa de cambio (un cobro en USD que el banco convierte a COP varía un poco
 * cada mes).
 */
export const TOLERANCIA_CAMBIO_PRECIO = 0.05;

/** Días entre dos cobros para cada frecuencia (con margen por meses cortos y retrasos). */
const INTERVALOS = [
  { frecuencia: 'semanal', min: 6, max: 8 },
  { frecuencia: 'mensual', min: 26, max: 35 },
  { frecuencia: 'anual', min: 355, max: 375 },
];

/** Si ya hay un cobro registrado a ±3 días, el pago detectado es ese mismo. */
const DIAS_MISMO_COBRO = 3;

/**
 * Un SMS sin fecha en el texto (Nequi) toma la hora de llegada, que cambia
 * unos segundos según el camino (notificación o historial de SMS). Dentro de
 * este margen, mismo banco, comercio y monto es el mismo cobro.
 */
export const MINUTOS_TOLERANCIA_SIN_FECHA = 5;

export function frecuenciaDeIntervalo(dias) {
  return INTERVALOS.find((i) => dias >= i.min && dias <= i.max)?.frecuencia ?? null;
}

/**
 * Frecuencia de una serie de fechas "AAAA-MM-DD" ordenadas: todos los
 * intervalos deben corresponder a la misma. null si son menos de 2 fechas o
 * no son periódicas.
 */
export function estimarFrecuencia(fechas) {
  if (fechas.length < 2) return null;
  let frecuencia = null;
  for (let i = 1; i < fechas.length; i += 1) {
    const f = frecuenciaDeIntervalo(diasEntre(fechas[i - 1], fechas[i]));
    if (!f || (frecuencia && f !== frecuencia)) return null;
    frecuencia = f;
  }
  return frecuencia;
}

export function montosSimilares(a, b) {
  return Math.abs(a - b) <= TOLERANCIA_MONTOS * Math.max(a, b);
}

export function hayCambioDePrecio(anterior, nuevo) {
  return Math.abs(nuevo - anterior) > TOLERANCIA_CAMBIO_PRECIO * anterior;
}

/**
 * true si el comercio de un pago corresponde a la suscripción: uno contiene
 * al otro como palabras completas ("Netflix" y "Netflix Estándar") o los dos
 * llevan a la misma guía del catálogo ("Max" y "HBO Max").
 */
export function mismoServicio(nombreSuscripcion, comercio, guias) {
  const a = normalizar(nombreSuscripcion);
  const b = normalizar(comercio);
  if (!a || !b) return false;
  if (` ${a} `.includes(` ${b} `) || ` ${b} `.includes(` ${a} `)) return true;
  const ga = buscarGuia(nombreSuscripcion, guias);
  const gb = buscarGuia(comercio, guias);
  return !ga.esGenerica && !gb.esGenerica && ga.guia.nombre_servicio === gb.guia.nombre_servicio;
}

/** Primer cobro después de `hoy`, contando ciclos desde el último pago. */
export function siguienteCobro(ultimoPago, frecuencia, hoy) {
  let fecha = avanzarCiclo(ultimoPago, frecuencia);
  while (fecha <= hoy) fecha = avanzarCiclo(fecha, frecuencia);
  return fecha;
}

export const COLUMNAS_CANDIDATO = `id, comercio_normalizado, monto, moneda, frecuencia_estimada, estado,
  suscripcion_id, es_servicio_conocido, banco, fecha_ultimo_pago, creado_en`;

/**
 * Procesa un lote de pagos detectados del usuario, en una transacción.
 * `pagos` ya viene validado (middlewares/validaciones.js). Se procesan en
 * orden de fecha para que la periodicidad vea primero los más antiguos.
 *
 * Por cada pago, `resultado` es:
 * - 'repetido': esa huella ya estaba registrada (no se hace nada).
 * - 'suscripcion_existente': caso a), corresponde a una suscripción del usuario.
 * - 'candidato_nuevo' / 'candidato_actualizado': casos b) o c).
 * - 'comercio_descartado': el usuario ya dijo que ese comercio no es suyo.
 * - 'ya_confirmado': el comercio ya se confirmó como suscripción.
 * - 'compra_normal': comercio desconocido sin pagos periódicos. No se guarda
 *   (ver purgarComprasNormales).
 *
 * `compartido`: el usuario compartió el SMS con SubTrack para registrarlo. Si
 * es de un comercio desconocido y sin pagos periódicos, igual se propone como
 * suscripción (mensual): el usuario dice que lo es.
 *
 * @returns {{ resultados: object[], candidatos_nuevos: object[] }}
 */
export async function procesarPagos(usuarioId, pagos, { compartido = false } = {}) {
  return transaccion(async (client) => {
    // Bloquea al usuario: si llegan dos lotes suyos a la vez, el segundo espera
    // (así no se crean dos candidatos ni se leen montos viejos).
    await client.query('SELECT 1 FROM usuarios WHERE id = $1 FOR UPDATE', [usuarioId]);
    const guias = (await client.query(
      'SELECT nombre_servicio, alias, es_generica FROM guias_cancelacion',
    )).rows;
    const suscripciones = (await client.query(
      `SELECT id, nombre_servicio, monto, moneda FROM suscripciones
       WHERE usuario_id = $1 AND estado = ANY($2) ORDER BY id`,
      [usuarioId, ESTADOS_EN_CURSO],
    )).rows;

    const ordenados = [...pagos].sort((x, y) => x.fecha.localeCompare(y.fecha));
    const resultados = [];
    const candidatosNuevos = [];
    for (const pago of ordenados) {
      const r = await procesarPago(client, usuarioId, pago, guias, suscripciones, compartido);
      if (r.candidato && r.resultado === 'candidato_nuevo') candidatosNuevos.push(r.candidato);
      resultados.push({
        huella: pago.huella,
        resultado: r.resultado,
        suscripcion_id: r.suscripcionId ?? null,
        candidato_id: r.candidato?.id ?? r.candidatoId ?? null,
        cambio_precio: r.cambioPrecio ?? false,
      });
    }
    // Al final del lote: las compras que no terminaron en una suscripción o
    // un candidato no se quedan en el servidor.
    await purgarComprasNormales(client, usuarioId, guias);
    return { resultados, candidatos_nuevos: candidatosNuevos };
  });
}

async function procesarPago(client, usuarioId, pago, guias, suscripciones, compartido) {
  const aproximada = pago.fecha_del_mensaje === false;
  if (await esCobroRepetido(client, usuarioId, pago, aproximada)) return { resultado: 'repetido' };
  const insertado = await client.query(
    `INSERT INTO pagos_detectados
       (usuario_id, comercio, comercio_normalizado, monto, moneda, fecha, banco, huella, fecha_aproximada)
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
     ON CONFLICT (usuario_id, huella) DO NOTHING
     RETURNING id, monto`,
    [usuarioId, pago.comercio, pago.comercio_normalizado, pago.monto, pago.moneda, pago.fecha,
      pago.banco, pago.huella, aproximada],
  );
  if (insertado.rowCount === 0) return { resultado: 'repetido' };
  const { id: pagoId, monto } = insertado.rows[0];
  const dia = pago.fecha.slice(0, 10);

  // a) Ya es una suscripción del usuario.
  const suscripcion = suscripciones.find((s) => mismoServicio(s.nombre_servicio, pago.comercio_normalizado, guias));
  if (suscripcion) {
    const cambioPrecio = await registrarEnSuscripcion(client, suscripcion, pagoId, monto, pago.moneda, pago.fecha, dia);
    return { resultado: 'suscripcion_existente', suscripcionId: suscripcion.id, cambioPrecio };
  }

  // b) Servicio conocido: candidato desde el primer pago.
  const { guia, esGenerica } = buscarGuia(pago.comercio_normalizado, guias);
  const conocido = !esGenerica && guia !== null;
  const nombre = conocido ? guia.nombre_servicio : pago.comercio_normalizado;

  // c) Comercio desconocido: hacen falta 2 o más pagos de monto similar y periódicos.
  const anteriores = (await client.query(
    `SELECT fecha::date AS dia, monto FROM pagos_detectados
     WHERE usuario_id = $1 AND lower(comercio_normalizado) = lower($2) AND moneda = $3
     ORDER BY fecha, id`,
    [usuarioId, pago.comercio_normalizado, pago.moneda],
  )).rows;
  const fechas = anteriores.filter((p) => montosSimilares(p.monto, monto)).map((p) => p.dia);
  const frecuencia = estimarFrecuencia(fechas);
  if (!conocido && !frecuencia && !compartido) return { resultado: 'compra_normal' };

  return proponer(client, usuarioId, {
    nombre, monto, moneda: pago.moneda, banco: pago.banco, dia, conocido,
    // Con un solo pago de un servicio conocido se asume mensual (lo más común).
    frecuencia: frecuencia ?? 'mensual',
  });
}

/**
 * El mismo cobro ya registrado por otro camino: misma huella (lo resuelve el
 * INSERT) o, si alguna de las dos fechas es la hora de llegada (SMS sin
 * fecha), mismo banco, comercio, monto y moneda a ±5 minutos.
 */
async function esCobroRepetido(client, usuarioId, pago, aproximada) {
  const { rowCount } = await client.query(
    `SELECT 1 FROM pagos_detectados
     WHERE usuario_id = $1 AND banco = $2 AND lower(comercio_normalizado) = lower($3)
       AND monto = $4 AND moneda = $5
       AND ($7 OR fecha_aproximada)
       AND fecha BETWEEN $6::timestamp - make_interval(mins => $8)
                     AND $6::timestamp + make_interval(mins => $8)
     LIMIT 1`,
    [usuarioId, pago.banco, pago.comercio_normalizado, pago.monto, pago.moneda, pago.fecha, aproximada,
      MINUTOS_TOLERANCIA_SIN_FECHA],
  );
  return rowCount > 0;
}

/**
 * Minimización de datos: borra los pagos detectados del usuario que no están
 * enlazados a una suscripción ni corresponden a un candidato pendiente o
 * confirmado (compras normales y comercios que el usuario descartó). Se
 * llama al final de cada lote, al descartar un candidato y en la tarea
 * diaria (tareas.js).
 *
 * `usuarioId` null = todos los usuarios. Devuelve cuántos borró.
 */
export async function purgarComprasNormales(client, usuarioId = null, guias = null) {
  const catalogo = guias ?? (await client.query(
    'SELECT nombre_servicio, alias, es_generica FROM guias_cancelacion',
  )).rows;
  const sueltos = (await client.query(
    `SELECT id, usuario_id, comercio_normalizado FROM pagos_detectados
     WHERE suscripcion_id IS NULL AND ($1::int IS NULL OR usuario_id = $1)`,
    [usuarioId],
  )).rows;
  if (sueltos.length === 0) return 0;
  const vivos = (await client.query(
    `SELECT usuario_id, comercio_normalizado FROM candidatos_suscripcion
     WHERE estado IN ('pendiente', 'confirmada') AND ($1::int IS NULL OR usuario_id = $1)`,
    [usuarioId],
  )).rows;
  const borrar = sueltos
    .filter((p) => !vivos.some((c) => c.usuario_id === p.usuario_id
      && mismoServicio(c.comercio_normalizado, p.comercio_normalizado, catalogo)))
    .map((p) => p.id);
  if (borrar.length > 0) await client.query('DELETE FROM pagos_detectados WHERE id = ANY($1)', [borrar]);
  return borrar.length;
}

/**
 * Caso a): enlaza el pago, lo agrega al historial y, si el monto cambió más
 * que la tolerancia, registra el cambio de precio (RF08). Devuelve si hubo
 * cambio de precio.
 */
async function registrarEnSuscripcion(client, s, pagoId, monto, moneda, fecha, dia) {
  await client.query('UPDATE pagos_detectados SET suscripcion_id = $1 WHERE id = $2', [s.id, pagoId]);
  // historial_pagos no guarda moneda: un pago en otra moneda solo se enlaza.
  if (s.moneda !== moneda) return false;

  // El proceso automático de cobros ya pudo registrar este mismo cobro.
  const cercano = await client.query(
    `SELECT 1 FROM historial_pagos
     WHERE suscripcion_id = $1 AND fecha_pago BETWEEN $2::date - $3::int AND $2::date + $3::int`,
    [s.id, dia, DIAS_MISMO_COBRO],
  );
  if (cercano.rowCount === 0) {
    await client.query(
      `INSERT INTO historial_pagos (suscripcion_id, monto, fecha_pago) VALUES ($1, $2, $3)
       ON CONFLICT (suscripcion_id, fecha_pago) DO NOTHING`,
      [s.id, monto, dia],
    );
  }

  // Un pago viejo que llega tarde no cambia el precio actual.
  const posterior = await client.query(
    'SELECT 1 FROM pagos_detectados WHERE suscripcion_id = $1 AND fecha > $2 LIMIT 1',
    [s.id, fecha],
  );
  if (posterior.rowCount > 0 || !hayCambioDePrecio(s.monto, monto)) return false;

  await client.query(
    'INSERT INTO cambios_precio (suscripcion_id, monto_anterior, monto_nuevo) VALUES ($1, $2, $3)',
    [s.id, s.monto, monto],
  );
  await client.query('UPDATE suscripciones SET monto = $2 WHERE id = $1', [s.id, monto]);
  s.monto = monto; // para el siguiente pago del mismo lote
  return true;
}

/**
 * Crea el candidato, o actualiza el pendiente con el último pago. Un comercio
 * descartado no se vuelve a proponer; uno confirmado solo si su suscripción
 * se borró.
 */
async function proponer(client, usuarioId, c) {
  const existente = (await client.query(
    `SELECT id, estado, suscripcion_id FROM candidatos_suscripcion
     WHERE usuario_id = $1 AND lower(comercio_normalizado) = lower($2)`,
    [usuarioId, c.nombre],
  )).rows[0];

  if (!existente) {
    const { rows } = await client.query(
      `INSERT INTO candidatos_suscripcion
         (usuario_id, comercio_normalizado, monto, moneda, frecuencia_estimada, es_servicio_conocido,
          banco, fecha_ultimo_pago)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
       RETURNING ${COLUMNAS_CANDIDATO}`,
      [usuarioId, c.nombre, c.monto, c.moneda, c.frecuencia, c.conocido, c.banco, c.dia],
    );
    return { resultado: 'candidato_nuevo', candidato: rows[0] };
  }
  if (existente.estado === 'descartada') return { resultado: 'comercio_descartado', candidatoId: existente.id };
  if (existente.estado === 'confirmada' && existente.suscripcion_id !== null) {
    return { resultado: 'ya_confirmado', candidatoId: existente.id };
  }

  // Pendiente: se actualiza con el último pago. Confirmado cuya suscripción se
  // borró: se vuelve a proponer (cuenta como nuevo para avisar al usuario).
  const reabierto = existente.estado === 'confirmada';
  const { rows } = await client.query(
    `UPDATE candidatos_suscripcion SET
       monto = CASE WHEN $3::date >= fecha_ultimo_pago THEN $2 ELSE monto END,
       fecha_ultimo_pago = GREATEST(fecha_ultimo_pago, $3::date),
       moneda = $4, frecuencia_estimada = $5, banco = $6,
       estado = 'pendiente', suscripcion_id = NULL
     WHERE id = $1
     RETURNING ${COLUMNAS_CANDIDATO}`,
    [existente.id, c.monto, c.dia, c.moneda, c.frecuencia, c.banco],
  );
  return { resultado: reabierto ? 'candidato_nuevo' : 'candidato_actualizado', candidato: rows[0] };
}

/**
 * Pagos detectados del usuario que corresponden a un candidato confirmado y
 * todavía no están enlazados: se enlazan a la suscripción y se agregan a su
 * historial (si son de la misma moneda).
 */
export async function enlazarPagos(client, usuarioId, nombre, suscripcion) {
  const guias = (await client.query(
    'SELECT nombre_servicio, alias, es_generica FROM guias_cancelacion',
  )).rows;
  const pagos = (await client.query(
    `SELECT id, comercio_normalizado, monto, moneda, fecha::date AS dia FROM pagos_detectados
     WHERE usuario_id = $1 AND suscripcion_id IS NULL`,
    [usuarioId],
  )).rows.filter((p) => mismoServicio(nombre, p.comercio_normalizado, guias));

  for (const p of pagos) {
    await client.query('UPDATE pagos_detectados SET suscripcion_id = $1 WHERE id = $2', [suscripcion.id, p.id]);
    if (p.moneda === suscripcion.moneda) {
      await client.query(
        `INSERT INTO historial_pagos (suscripcion_id, monto, fecha_pago) VALUES ($1, $2, $3)
         ON CONFLICT (suscripcion_id, fecha_pago) DO NOTHING`,
        [suscripcion.id, p.monto, p.dia],
      );
    }
  }
  return pagos.length;
}
