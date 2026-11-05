/// Servicios conocidos para la detección: los nombres y alias del catálogo de
/// guías de cancelación (GET /api/guias, backend/db/guias.json).
///
/// Sirve para normalizar el comercio de un cobro: "NETFLIX.COM",
/// "Netflix*Bogota" y "NETFLIX INC" son todos "Netflix".
class CatalogoServicios {
  const CatalogoServicios(this.servicios, {this.procesadores = const []});

  /// Sin catálogo (por ejemplo, sin conexión con el backend): ningún
  /// comercio se reconoce como servicio conocido.
  static const vacio = CatalogoServicios([]);

  /// [ambiguo]: el comercio también vende cosas sueltas (Rappi, Apple,
  /// PlayStation...): solo se propone con patrón o señal de suscripción.
  /// [precioCop]: precio de referencia en Colombia, para sugerir el servicio
  /// de un cobro de procesador ("¿Es Crunchyroll?"); null si no se conoce.
  final List<({String nombre, List<String> alias, bool ambiguo, double? precioCop})> servicios;

  /// Procesadores de pago (EBANX, PayU, dLocal...): cobran en nombre de otro
  /// servicio, así que el SMS trae su nombre y no el del servicio
  /// (backend/db/procesadores.json).
  final List<({String nombre, List<String> alias})> procesadores;

  /// Acepta la respuesta de GET /api/guias (`{guias: [...], procesadores: [...]}`)
  /// o el arreglo de guias.json. La guía genérica ("Otro servicio") no es un
  /// servicio.
  factory CatalogoServicios.fromJson(Object json) {
    final lista = json is Map ? json['guias'] as List : json as List;
    final procesadores = json is Map ? (json['procesadores'] as List? ?? const []) : const [];
    return CatalogoServicios(procesadores: [
      for (final p in procesadores.cast<Map>())
        (nombre: p['nombre'] as String, alias: ((p['alias'] as List?) ?? const []).cast<String>()),
    ], [
      for (final g in lista.cast<Map>())
        if (g['es_generica'] != true)
          (
            nombre: g['nombre_servicio'] as String,
            alias: ((g['alias'] as List?) ?? const []).cast<String>(),
            ambiguo: g['es_ambigua'] == true,
            precioCop: (g['precio_referencia_cop'] as num?)?.toDouble(),
          ),
    ]);
  }

  bool get estaVacio => servicios.isEmpty;

  /// Nombre del procesador cuyo alias aparece en [texto] como palabra
  /// completa ("Servicios Web Ebanx Co" -> "EBANX"), o null.
  String? procesadorDe(String texto) {
    final t = ' ${normalizarNombre(texto)} ';
    final tSeparado = ' ${normalizarNombre(texto, separarPegadas: true)} ';
    for (final p in procesadores) {
      for (final alias in p.alias) {
        final a = normalizarNombre(alias);
        if (a.isNotEmpty && (t.contains(' $a ') || tSeparado.contains(' $a '))) return p.nombre;
      }
    }
    return null;
  }

  /// Margen para sugerir un servicio por el monto de un cobro (±5 %).
  static const toleranciaSugerencia = 0.05;

  /// Servicio cuyo precio de referencia está a ±5 % de [monto] (solo COP), o
  /// null. Es una sugerencia: el usuario decide.
  String? sugerirPorMonto(double monto, String moneda) {
    if (moneda != 'COP') return null;
    for (final s in servicios) {
      final precio = s.precioCop;
      if (precio != null && (monto - precio).abs() <= toleranciaSugerencia * precio) return s.nombre;
    }
    return null;
  }

  /// true si [servicio] (un nombre del catálogo) es ambiguo.
  bool esAmbiguo(String servicio) => servicios.any((s) => s.nombre == servicio && s.ambiguo);

  /// Nombre del servicio cuyo nombre o alias aparece en [texto] como palabras
  /// completas ("anthropic claude sub" contiene "claude"). Si varios
  /// coinciden, gana el más largo, igual que buscarGuia en el backend.
  ///
  /// Se compara de dos formas: tal cual ("YOUTUBE PREMIUM") y con las
  /// palabras pegadas separadas en los dos lados ("YouTubePremium" y la
  /// clave "YouTube Premium" quedan como "you tube premium").
  String? buscar(String texto) {
    final t = ' ${normalizarNombre(texto)} ';
    final tSeparado = ' ${normalizarNombre(texto, separarPegadas: true)} ';
    String? mejor;
    var largoMejor = 0;
    for (final s in servicios) {
      for (final clave in [s.nombre, ...s.alias]) {
        final c = normalizarNombre(clave);
        final cSeparada = normalizarNombre(clave, separarPegadas: true);
        final coincide = t.contains(' $c ') || tSeparado.contains(' $cSeparada ');
        if (c.isNotEmpty && coincide && c.length > largoMejor) {
          mejor = s.nombre;
          largoMejor = c.length;
        }
      }
    }
    return mejor;
  }
}

const _tildes = {
  'á': 'a', 'à': 'a', 'ä': 'a', 'â': 'a', 'é': 'e', 'è': 'e', 'ë': 'e', 'ê': 'e',
  'í': 'i', 'ì': 'i', 'ï': 'i', 'î': 'i', 'ó': 'o', 'ò': 'o', 'ö': 'o', 'ô': 'o',
  'ú': 'u', 'ù': 'u', 'ü': 'u', 'û': 'u', 'ñ': 'n',
};

/// Minúsculas, sin tildes, "+" como "plus" y cualquier otro signo como
/// espacio. Es la misma regla que normalizar() en backend/src/services/guias.js.
///
/// [separarPegadas]: antes, separa las palabras pegadas por mayúsculas
/// ("YouTubePremium" -> "You Tube Premium").
String normalizarNombre(String texto, {bool separarPegadas = false}) {
  if (separarPegadas) texto = texto.replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}');
  final sinTildes = texto.toLowerCase().split('').map((c) => _tildes[c] ?? c).join();
  return sinTildes
      .replaceAll('+', ' plus ')
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim();
}
