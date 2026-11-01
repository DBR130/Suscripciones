// Validación de los datos que llegan en el cuerpo (body) de la petición.
//
// Aunque la app Flutter ya valida los formularios, el servidor debe volver a
// validar: cualquiera puede llamar a la API directamente (curl, Thunder Client)
// sin pasar por la app.
//
// Si los datos son válidos, se dejan limpios en req.body y se llama a next()
// para continuar con el controlador. Si no, se responde 400 con el motivo.

import { esFechaValida } from '../utils/fechas.js';

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

// ─── Suscripciones ───────────────────────────────────────────────────────────

export const FRECUENCIAS = ['semanal', 'mensual', 'anual'];
export const ESTADOS = ['activa', 'marcada_para_cancelar', 'cancelada'];
const MONEDAS = ['COP', 'USD'];
const ORIGENES = ['manual', 'notificacion'];
// Mismas categorías que el CHECK de la migración 003.
export const CATEGORIAS = [
  'Streaming', 'Música', 'Cloud gaming', 'Almacenamiento', 'Gimnasio', 'Software', 'Diseño',
];
const NOMBRE_SERVICIO_MAX = 100;
const DIAS_MAX = 30;

// NUMERIC(12,2): hasta 10 dígitos enteros y 2 decimales, sin negativos.
const REGEX_MONTO = /^\d{1,10}(\.\d{1,2})?$/;

// Devuelve el monto como texto ("45900.5") para que PostgreSQL lo guarde
// exacto, o null si no es válido. Acepta número (45900) o texto ("45900.50").
function montoValido(valor) {
  const monto = typeof valor === 'number' ? String(valor) : texto(valor).trim();
  return REGEX_MONTO.test(monto) ? monto : null;
}

function diasValidos(valor) {
  return Number.isInteger(valor) && valor >= 0 && valor <= DIAS_MAX;
}

function error400(res, error) {
  return res.status(400).json({ error });
}

/**
 * Valida y limpia los datos de una suscripción. Devuelve { datos } o
 * { error }. La usan validarSuscripcion y la confirmación de un candidato
 * detectado (controllers/detecciones.controller.js).
 */
export function limpiarSuscripcion(body) {
  const nombre_servicio = texto(body.nombre_servicio).trim();
  if (!nombre_servicio) return { error: 'El nombre del servicio es obligatorio' };
  if (nombre_servicio.length > NOMBRE_SERVICIO_MAX) {
    return { error: `El nombre admite máximo ${NOMBRE_SERVICIO_MAX} caracteres` };
  }

  // Opcional: null, ausente o "" = sin categoría. Se normaliza a NFC porque
  // "Música" puede llegar como "u" + tilde combinada y no coincidiría.
  const categoria = body.categoria === undefined || body.categoria === ''
    ? null
    : typeof body.categoria === 'string' ? body.categoria.normalize('NFC') : body.categoria;
  if (categoria !== null && !CATEGORIAS.includes(categoria)) {
    return { error: `La categoría debe ser una de: ${CATEGORIAS.join(', ')}` };
  }

  const monto = montoValido(body.monto);
  if (monto === null) {
    return { error: 'El monto debe ser un número mayor o igual a 0 con máximo 2 decimales' };
  }

  const moneda = body.moneda ?? 'COP';
  if (!MONEDAS.includes(moneda)) return { error: 'La moneda debe ser COP o USD' };

  const { frecuencia } = body;
  if (!FRECUENCIAS.includes(frecuencia)) {
    return { error: 'La frecuencia debe ser semanal, mensual o anual' };
  }

  const { fecha_proximo_cobro } = body;
  if (!esFechaValida(fecha_proximo_cobro)) {
    return { error: 'La fecha del próximo cobro no es válida (formato AAAA-MM-DD)' };
  }

  const es_prueba_gratis = body.es_prueba_gratis ?? false;
  if (typeof es_prueba_gratis !== 'boolean') return { error: 'es_prueba_gratis debe ser true o false' };

  let fecha_fin_prueba = null;
  if (es_prueba_gratis) {
    if (!esFechaValida(body.fecha_fin_prueba)) {
      return { error: 'La fecha de fin de la prueba es obligatoria (formato AAAA-MM-DD)' };
    }
    fecha_fin_prueba = body.fecha_fin_prueba;
  }

  // null o ausente = usar la preferencia global del usuario.
  const dias_aviso = body.dias_aviso ?? null;
  if (dias_aviso !== null && !diasValidos(dias_aviso)) {
    return { error: `Los días de aviso deben ser un entero entre 0 y ${DIAS_MAX}` };
  }

  const origen = body.origen ?? 'manual';
  if (!ORIGENES.includes(origen)) return { error: 'El origen debe ser manual o notificacion' };

  return {
    datos: {
      nombre_servicio, categoria, monto, moneda, frecuencia, fecha_proximo_cobro,
      es_prueba_gratis, fecha_fin_prueba, dias_aviso, origen,
    },
  };
}

// Para crear (POST) y editar (PUT). En el PUT se envían todos los campos.
export function validarSuscripcion(req, res, next) {
  const { datos, error } = limpiarSuscripcion(req.body ?? {});
  if (error) return error400(res, error);
  req.body = datos;
  next();
}

export function validarEstado(req, res, next) {
  const estado = req.body?.estado;
  if (!ESTADOS.includes(estado)) {
    return error400(res, `El estado debe ser uno de: ${ESTADOS.join(', ')}`);
  }
  req.body = { estado };
  next();
}

// ─── Detecciones (pagos detectados en notificaciones) ───────────────────────

const MAX_PAGOS = 100;
const REGEX_HUELLA = /^[0-9a-f]{64}$/;
// Hora local de Colombia, sin zona: "2026-10-23T07:20", con segundos y
// milisegundos opcionales (como DateTime.toIso8601String() en Dart).
const REGEX_FECHA_HORA = /^(\d{4}-\d{2}-\d{2})[T ](\d{2}):(\d{2})(?::(\d{2})(?:\.\d{1,6})?)?$/;
const COMERCIO_MAX = 100;
const BANCO_MAX = 50;

/** Texto obligatorio, recortado, de máximo `max` caracteres; null si no es válido. */
function textoObligatorio(valor, max) {
  const t = texto(valor).trim();
  return t && t.length <= max ? t : null;
}

function fechaHoraValida(valor) {
  const m = REGEX_FECHA_HORA.exec(texto(valor));
  if (!m || !esFechaValida(m[1])) return null;
  const [hora, minuto, segundo = '00'] = [m[2], m[3], m[4]];
  if (Number(hora) > 23 || Number(minuto) > 59 || Number(segundo) > 59) return null;
  return `${m[1]}T${hora}:${minuto}:${segundo}`;
}

// POST /api/detecciones/pagos  {pagos: [{huella, comercio, comercio_normalizado,
// monto, moneda, fecha, banco}]}. Si un pago no es válido, se rechaza el lote.
export function validarPagosDetectados(req, res, next) {
  const pagos = req.body?.pagos;
  if (!Array.isArray(pagos) || pagos.length === 0) {
    return error400(res, 'Envía un arreglo "pagos" con al menos un pago');
  }
  if (pagos.length > MAX_PAGOS) return error400(res, `Máximo ${MAX_PAGOS} pagos por envío`);

  const limpios = [];
  for (const [i, p] of pagos.entries()) {
    const donde = `Pago ${i + 1}`;
    if (p === null || typeof p !== 'object' || Array.isArray(p)) return error400(res, `${donde}: debe ser un objeto`);
    // Privacidad: el texto de la notificación nunca debe salir del celular.
    if ('texto' in p || 'titulo' in p) {
      return error400(res, `${donde}: el texto de la notificación no se envía al servidor`);
    }

    const huella = texto(p.huella).toLowerCase();
    if (!REGEX_HUELLA.test(huella)) return error400(res, `${donde}: la huella debe ser un SHA-256 en hexadecimal`);

    const comercio = textoObligatorio(p.comercio, COMERCIO_MAX);
    const comercioNormalizado = textoObligatorio(p.comercio_normalizado, COMERCIO_MAX);
    if (!comercio || !comercioNormalizado) {
      return error400(res, `${donde}: el comercio es obligatorio (máx. ${COMERCIO_MAX} caracteres)`);
    }

    const monto = montoValido(p.monto);
    if (monto === null || Number(monto) <= 0) {
      return error400(res, `${donde}: el monto debe ser mayor que 0 con máximo 2 decimales`);
    }

    if (!MONEDAS.includes(p.moneda)) return error400(res, `${donde}: la moneda debe ser COP o USD`);

    const fecha = fechaHoraValida(p.fecha);
    if (!fecha) return error400(res, `${donde}: la fecha debe ser AAAA-MM-DDTHH:MM (hora local)`);

    const banco = textoObligatorio(p.banco, BANCO_MAX);
    if (!banco) return error400(res, `${donde}: el banco es obligatorio (máx. ${BANCO_MAX} caracteres)`);

    // false = el texto no traía fecha y es la hora de llegada (ver services/detecciones.js).
    if (p.fecha_del_mensaje !== undefined && typeof p.fecha_del_mensaje !== 'boolean') {
      return error400(res, `${donde}: fecha_del_mensaje debe ser true o false`);
    }

    limpios.push({
      huella, comercio, comercio_normalizado: comercioNormalizado, monto, moneda: p.moneda, fecha, banco,
      fecha_del_mensaje: p.fecha_del_mensaje ?? true,
    });
  }
  const compartido = req.body.compartido;
  if (compartido !== undefined && typeof compartido !== 'boolean') {
    return error400(res, 'compartido debe ser true o false');
  }
  // Un SMS compartido es uno solo: lo eligió el usuario.
  if (compartido && limpios.length !== 1) return error400(res, 'Un cobro compartido se envía solo');
  req.body = { pagos: limpios, compartido: compartido === true };
  next();
}

// ─── Usuario ─────────────────────────────────────────────────────────────────

export function validarPreferencias(req, res, next) {
  const dias = req.body?.dias_anticipacion_recordatorio;
  if (!diasValidos(dias)) {
    return error400(res, `dias_anticipacion_recordatorio debe ser un entero entre 0 y ${DIAS_MAX}`);
  }
  req.body = { dias_anticipacion_recordatorio: dias };
  next();
}

export function validarEliminarCuenta(req, res, next) {
  const password = texto(req.body?.password);
  if (!password) return error400(res, 'Escribe tu contraseña para eliminar la cuenta');
  req.body = { password };
  next();
}
