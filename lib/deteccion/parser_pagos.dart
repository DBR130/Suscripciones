import 'catalogo_servicios.dart';
import 'notificacion_capturada.dart';

/// Campos extraídos de una notificación de cobro. Es lo único que saldrá del
/// celular (hito 3): el texto crudo se queda en la cola local.
class PagoExtraido {
  const PagoExtraido({
    required this.banco,
    required this.monto,
    required this.moneda,
    required this.comercioOriginal,
    required this.comercio,
    required this.fecha,
    required this.fechaDelMensaje,
    this.medio,
    this.servicio,
    this.indicaSuscripcion = false,
  });

  /// "Bancolombia", "Nequi"...
  final String banco;
  final double monto;

  /// "COP" o "USD".
  final String moneda;

  /// Como viene en el mensaje: "GOOGLE *Crunchyroll".
  final String comercioOriginal;

  /// Normalizado: "Crunchyroll".
  final String comercio;

  /// La del mensaje si la trae; si no, la hora de llegada de la notificación.
  final DateTime fecha;
  final bool fechaDelMensaje;

  /// "T.Deb", "T.Cred"... (nunca los dígitos de la tarjeta).
  final String? medio;

  /// Nombre del servicio en el catálogo de guías, o null si el comercio no
  /// es un servicio conocido (por ejemplo, una compra en DiDi Food).
  final String? servicio;

  /// El mensaje dice que es una suscripción ("SUB").
  final bool indicaSuscripcion;

  bool get esServicioConocido => servicio != null;
}

/// Resultado del parser: un cobro con sus campos, o el motivo por el que no lo es.
class InterpretacionPago {
  const InterpretacionPago.cobro(PagoExtraido this.pago) : motivo = null;
  const InterpretacionPago.noEsCobro(String this.motivo) : pago = null;

  final PagoExtraido? pago;
  final String? motivo;

  bool get esCobro => pago != null;
}

/// Interpreta notificaciones de pago de bancos colombianos (hito 2).
///
/// Solo reconoce cobros de bancos conocidos con la forma
/// "compraste/pagaste MONTO en COMERCIO". Ante la duda, responde que
/// no es un cobro: es mejor perder un cobro que inventar uno.
class ParserPagos {
  const ParserPagos([this.catalogo = CatalogoServicios.vacio]);

  final CatalogoServicios catalogo;

  InterpretacionPago interpretarNotificacion(NotificacionCapturada n) =>
      interpretar(n.texto, titulo: n.titulo, recibidaEn: n.recibidaEn);

  InterpretacionPago interpretar(String texto, {String titulo = '', required DateTime recibidaEn}) {
    final t = texto.trim();
    if (t.isEmpty) return const InterpretacionPago.noEsCobro('sin texto');

    final normal = normalizarNombre(t);
    for (final (patron, motivo) in _noCobros) {
      if (patron.hasMatch(normal)) return InterpretacionPago.noEsCobro(motivo);
    }

    final banco = _banco(t, titulo);
    if (banco == null) return const InterpretacionPago.noEsCobro('no es de un banco conocido');

    final m = _cobro.firstMatch(t);
    if (m == null) {
      return const InterpretacionPago.noEsCobro('no dice "compraste/pagaste <monto> en <comercio>"');
    }
    final monto = leerMonto(m.namedGroup('monto')!);
    if (monto == null || monto.valor <= 0) return const InterpretacionPago.noEsCobro('monto no válido');

    final original = m.namedGroup('comercio')!.trim();
    final comercio = _normalizarComercio(original);
    final fecha = leerFecha(t);

    return InterpretacionPago.cobro(PagoExtraido(
      banco: banco,
      monto: monto.valor,
      moneda: monto.moneda,
      comercioOriginal: original,
      comercio: comercio.nombre,
      servicio: comercio.servicio,
      indicaSuscripcion: comercio.indicaSuscripcion,
      fecha: fecha ?? recibidaEn,
      fechaDelMensaje: fecha != null,
      medio: _medio.firstMatch(t)?.namedGroup('medio')?.trim(),
    ));
  }

  /// El banco, por el título o por el remitente al inicio del texto
  /// ("Bancolombia: ...", "NEQUI: ...").
  String? _banco(String texto, String titulo) {
    final dosPuntos = texto.indexOf(':');
    final remitente = dosPuntos > 0 && dosPuntos <= 40 ? texto.substring(0, dosPuntos) : '';
    for (final donde in [titulo, remitente, texto]) {
      final n = ' ${normalizarNombre(donde)} ';
      for (final (nombre, patron) in _bancos) {
        if (patron.hasMatch(n)) return nombre;
      }
    }
    return null;
  }

  ({String nombre, String? servicio, bool indicaSuscripcion}) _normalizarComercio(String original) {
    var limpio = original;
    String? marca;
    for (final (patron, nombre) in _pasarelas) {
      final m = patron.firstMatch(limpio);
      if (m != null) {
        limpio = limpio.substring(m.end);
        marca = nombre;
        break;
      }
    }
    // Teléfono pegado al final ("STEAMGAMES.COM 4259522985", SMS real de Nequi).
    limpio = limpio.replaceAll(_telefonoAlFinal, '');
    final indicaSuscripcion = tieneSenalDeSuscripcion(limpio);
    limpio = limpio.replaceAll(_suscripcion, ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    // "APPLE.COM/BILL" solo: el comercio es la pasarela misma.
    if (limpio.isEmpty) limpio = marca ?? original;

    final servicio = catalogo.buscar(limpio);
    return (nombre: servicio ?? _presentable(limpio), servicio: servicio, indicaSuscripcion: indicaSuscripcion);
  }
}

/// Monto y moneda: "$19.900,00", "$26.900", "68.139,27", "COP 26,900.00",
/// "USD 20.00". Sin "USD" se asume COP.
({double valor, String moneda})? leerMonto(String texto) {
  final numero = RegExp(r'\d(?:[\d.,]*\d)?').firstMatch(texto)?.group(0);
  if (numero == null) return null;
  final valor = leerNumero(numero);
  if (valor == null) return null;
  final bajo = texto.toLowerCase();
  return (valor: valor, moneda: bajo.contains('usd') || bajo.contains(r'us$') ? 'USD' : 'COP');
}

/// Número con separadores colombianos o internacionales. Si hay punto y
/// coma, el último es el decimal. Si hay uno solo, es de miles cuando lo
/// siguen grupos de 3 dígitos ("26.900") y decimal cuando lo siguen 1 o 2
/// ("20.00", "68139,27").
double? leerNumero(String n) {
  final punto = n.lastIndexOf('.');
  final coma = n.lastIndexOf(',');
  if (punto >= 0 && coma >= 0) {
    final decimal = punto > coma ? '.' : ',';
    final miles = decimal == '.' ? ',' : '.';
    return double.tryParse(n.replaceAll(miles, '').replaceAll(decimal, '.'));
  }
  final separador = punto >= 0 ? '.' : (coma >= 0 ? ',' : null);
  if (separador == null) return double.tryParse(n);
  final partes = n.split(separador);
  if (partes.first.length <= 3 && partes.skip(1).every((p) => p.length == 3)) {
    return double.tryParse(partes.join());
  }
  if (partes.length == 2 && partes[1].length <= 2) return double.tryParse('${partes[0]}.${partes[1]}');
  return null;
}

/// Fecha y hora del mensaje: "el 23/10/2026 a las 07:20", "23/10/26 07:20" o
/// solo la fecha. null si no la trae o no es una fecha real (31/02).
DateTime? leerFecha(String texto) {
  final m = _fecha.firstMatch(texto);
  if (m == null) return null;
  final d = int.parse(m.namedGroup('d')!);
  final mes = int.parse(m.namedGroup('m')!);
  var a = int.parse(m.namedGroup('a')!);
  if (a < 100) a += 2000;
  final h = int.tryParse(m.namedGroup('h') ?? '') ?? 0;
  final min = int.tryParse(m.namedGroup('min') ?? '') ?? 0;
  final fecha = DateTime(a, mes, d, h, min);
  // DateTime acepta 31/02 y lo pasa a marzo: así se detecta una fecha falsa.
  final valida = fecha.year == a && fecha.month == mes && fecha.day == d && fecha.hour == h && fecha.minute == min;
  return valida ? fecha : null;
}

/// "DIDI FOOD" -> "Didi Food", sin sufijos (".COM", "INC") ni la ciudad
/// después de "*" ("TIENDA*Medellin" -> "Tienda").
String _presentable(String comercio) {
  var c = comercio.split('*').firstWhere((p) => p.trim().isNotEmpty, orElse: () => comercio);
  c = c
      .replaceAll(RegExp(r'\.com\b', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'\b(inc|llc|ltd|s\.?a\.?s|s\.?a)\b\.?', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (c.isEmpty) return comercio.trim();
  return c.split(' ').map((p) {
    if (p.contains(RegExp(r'\d'))) return p;
    return p[0].toUpperCase() + p.substring(1).toLowerCase();
  }).join(' ');
}

// Sobre el texto normalizado (minúsculas, sin tildes ni signos). El orden
// importa solo para el motivo que se muestra.
final _noCobros = [
  (RegExp(r'\b(codigo|clave|otp|contrasena|verificacion)\b'), 'código de verificación'),
  (RegExp(r'\b(recibiste|recibio|te enviaron|te envio|te consignaron|consignacion|abono)\b'), 'dinero recibido'),
  (RegExp(r'\b(transferiste|transferencia|enviaste)\b'), 'transferencia'),
  (RegExp(r'\b(recarga|recargaste|recargar)\b'), 'recarga'),
  (RegExp(r'\b(retiro|retiraste)\b'), 'retiro de dinero'),
  (RegExp(r'\b(aprovecha|descuento|promocion|oferta|sorteo|participa|gana)\b'), 'publicidad'),
];

// Sobre ' texto normalizado ' (con espacios a los lados).
final _bancos = [
  ('Bancolombia', RegExp(r' bancolombia ')),
  ('Nequi', RegExp(r' nequi ')),
  ('Davivienda', RegExp(r' davivienda ')),
  ('Daviplata', RegExp(r' daviplata ')),
  ('BBVA', RegExp(r' bbva ')),
  ('Banco de Bogotá', RegExp(r' banco de bogota ')),
  ('Scotiabank Colpatria', RegExp(r' (scotiabank|colpatria) ')),
];

const _monto = r'(?:(?:usd|cop|us\$)\s?)?\$?\s?\d(?:[\d.,]*\d)?(?:\s?(?:usd|cop))?';

final _cobro = RegExp(
  r'\b(?:compraste|pagaste|realizaste una compra|realizaste un pago|compra|pago|d[eé]bito)'
  '(?:\\s+(?:por|de))?\\s+(?<monto>$_monto)\\s+(?:en|a)\\s+'
  r'(?<comercio>.+?)(?=\s+con\s+tu\b|\s+desde\b|\s+el\s+\d|[,\n]|\.(?:\s|$)|$)',
  caseSensitive: false,
  unicode: true,
);

final _medio = RegExp(
  r'con\s+tu\s+(?<medio>T\.?\s?(?:Deb|Cred)[a-z.]*|tarjeta\s+(?:de\s+)?(?:d[eé]bito|cr[eé]dito)|cuenta\s+de\s+ahorros|cuenta\s+corriente)',
  caseSensitive: false,
  unicode: true,
);

final _fecha = RegExp(
  r'\b(?<d>\d{1,2})/(?<m>\d{1,2})/(?<a>\d{4}|\d{2})\b(?:\s+(?:a\s+las\s+)?(?<h>\d{1,2}):(?<min>\d{2}))?',
  caseSensitive: false,
);

// Prefijos de pasarelas de pago: el comercio real va después.
final _pasarelas = [
  (RegExp(r'^google\s*\*\s*', caseSensitive: false), 'Google'),
  (RegExp(r'^apple\.com/bill\s*', caseSensitive: false), 'Apple'),
  (RegExp(r'^paypal\s*\*\s*', caseSensitive: false), 'PayPal'),
  (RegExp(r'^ebanx\s*\*?\s*', caseSensitive: false), 'EBANX'),
];

/// Un número de 7 dígitos o más al final del comercio es un teléfono.
final _telefonoAlFinal = RegExp(r'\s+\+?\d{7,}\s*$');

/// "SUB" (y variantes) en el comercio indica una suscripción y se quita del nombre.
final _suscripcion = RegExp(r'\b(sub|subs|subscription|suscripcion|suscripción)\b', caseSensitive: false, unicode: true);

/// Palabras que indican una suscripción. Las de [_suscripcion] se quitan del
/// nombre; estas otras son parte del nombre ("YouTube Premium", "Rappi Pro").
/// La misma lista está en backend/src/services/detecciones.js.
const palabrasSenalSuscripcion = [
  'sub', 'subs', 'subscription', 'suscripcion', 'membresia', 'prime', 'pro', 'plus', 'premium',
];

/// true si el comercio trae una señal clara de suscripción, como palabra
/// completa y con las palabras pegadas separadas ("YouTubePremium").
bool tieneSenalDeSuscripcion(String comercio) {
  final palabras = normalizarNombre(comercio, separarPegadas: true).split(' ');
  return palabras.any(palabrasSenalSuscripcion.contains);
}
