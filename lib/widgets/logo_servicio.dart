import 'package:flutter/material.dart';

/// Cuadro de color con las iniciales del servicio ("Netflix" → "N",
/// "Disney Plus" → "DP") sobre el color de marca del servicio (ver
/// [LogoServicio.colorDe]).
class LogoServicio extends StatelessWidget {
  const LogoServicio(this.nombre, {super.key, this.size = 44, this.heroTag});

  final String nombre;
  final double size;

  /// Con valor, el logo "vuela" de la tarjeta al detalle (Hero).
  final Object? heroTag;

  /// Etiqueta del Hero de una suscripción (tarjeta → detalle).
  static String tagHero(int id) => 'logo-suscripcion-$id';

  /// Neutro de las suscripciones sin color de marca conocido (diseño).
  static const Color colorNeutro = Color(0xFF334155);

  /// Colores de marca: los de design/subtrack-pantallas.md y, para los demás
  /// servicios del catálogo, su color de marca real. La clave es una o más
  /// palabras completas del nombre, en minúsculas y sin símbolos.
  static const Map<String, Color> coloresMarca = {
    // Del diseño.
    'disney': Color(0xFF113CCF),
    'geforce': Color(0xFF3F6B00),
    'netflix': Color(0xFFC1121F),
    'spotify': Color(0xFF12833F),
    'icloud': Color(0xFF2F3437),
    'apple': Color(0xFF2F3437),
    'smart fit': Color(0xFF8A7A00),
    'smartfit': Color(0xFF8A7A00),
    'photoshop': Color(0xFF0A2F52),
    'canva': Color(0xFF0B7285),
    'paramount': Color(0xFF0064FF),
    // Otros servicios con su color de marca.
    'max': Color(0xFF002BE7),
    'hbo': Color(0xFF002BE7),
    'prime video': Color(0xFF00A8E1),
    'amazon': Color(0xFF00A8E1),
    'youtube': Color(0xFFFF0000),
    'google': Color(0xFF4285F4),
    'crunchyroll': Color(0xFFF47521),
    'chatgpt': Color(0xFF10A37F),
    'openai': Color(0xFF10A37F),
    'claude': Color(0xFFD97757),
    'anthropic': Color(0xFFD97757),
    'adobe': Color(0xFFEB1000),
    'microsoft': Color(0xFFD83B01),
    'office': Color(0xFFD83B01),
    'xbox': Color(0xFF107C10),
    'playstation': Color(0xFF003791),
    'rappi': Color(0xFFFF441F),
    'didi': Color(0xFFFC6B21),
    'duolingo': Color(0xFF58CC02),
  };

  /// Color de marca del servicio, o [colorNeutro] si no se conoce.
  /// "YouTube Premium" → rojo; "Disney+" → azul; "Servicios Web Ebanx" → neutro.
  static Color colorDe(String nombre) {
    final normal = nombre
        .toLowerCase()
        .replaceAll(RegExp('[áà]'), 'a')
        .replaceAll(RegExp('[éè]'), 'e')
        .replaceAll(RegExp('[íì]'), 'i')
        .replaceAll(RegExp('[óò]'), 'o')
        .replaceAll(RegExp('[úù]'), 'u')
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim();
    final palabras = ' $normal ';
    // Primero "photoshop" que "adobe", "prime video" que "amazon"...: gana
    // la clave más larga que aparezca como palabras completas.
    final claves = coloresMarca.keys.where((k) => palabras.contains(' $k ')).toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    return claves.isEmpty ? colorNeutro : coloresMarca[claves.first]!;
  }

  static String iniciales(String nombre) {
    final palabras = nombre.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (palabras.isEmpty) return '?';
    if (palabras.length == 1) {
      final p = palabras.first;
      return p.length >= 2 ? p[0].toUpperCase() + p[1].toLowerCase() : p.toUpperCase();
    }
    return (palabras[0][0] + palabras[1][0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final logo = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colorDe(nombre),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        iniciales(nombre),
        style: TextStyle(
          color: Colors.white,
          fontSize: size >= 52 ? 16 : 13.5,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.3,
        ),
      ),
    );
    if (heroTag == null) return logo;
    // Material transparente: el texto conserva su estilo mientras vuela.
    return Hero(tag: heroTag!, child: Material(type: MaterialType.transparency, child: logo));
  }
}
