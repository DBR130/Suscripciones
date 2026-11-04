/// Servicios conocidos para la detección: los nombres y alias del catálogo de
/// guías de cancelación (GET /api/guias, backend/db/guias.json).
///
/// Sirve para normalizar el comercio de un cobro: "NETFLIX.COM",
/// "Netflix*Bogota" y "NETFLIX INC" son todos "Netflix".
class CatalogoServicios {
  const CatalogoServicios(this.servicios);

  /// Sin catálogo (por ejemplo, sin conexión con el backend): ningún
  /// comercio se reconoce como servicio conocido.
  static const vacio = CatalogoServicios([]);

  final List<({String nombre, List<String> alias})> servicios;

  /// Acepta la respuesta de GET /api/guias (`{guias: [...]}`) o el arreglo de
  /// guias.json. La guía genérica ("Otro servicio") no es un servicio.
  factory CatalogoServicios.fromJson(Object json) {
    final lista = json is Map ? json['guias'] as List : json as List;
    return CatalogoServicios([
      for (final g in lista.cast<Map>())
        if (g['es_generica'] != true)
          (
            nombre: g['nombre_servicio'] as String,
            alias: ((g['alias'] as List?) ?? const []).cast<String>(),
          ),
    ]);
  }

  bool get estaVacio => servicios.isEmpty;

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
