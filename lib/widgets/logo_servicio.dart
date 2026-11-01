import 'package:flutter/material.dart';

/// Cuadro de color con las iniciales del servicio ("Netflix" → "N",
/// "Disney Plus" → "DP"). El color sale del nombre, así cada servicio
/// conserva siempre el mismo.
class LogoServicio extends StatelessWidget {
  const LogoServicio(this.nombre, {super.key, this.size = 44, this.heroTag});

  final String nombre;
  final double size;

  /// Con valor, el logo "vuela" de la tarjeta al detalle (Hero).
  final Object? heroTag;

  /// Etiqueta del Hero de una suscripción (tarjeta → detalle).
  static String tagHero(int id) => 'logo-suscripcion-$id';

  // Tonos de marca del diseño.
  static const List<Color> _colores = [
    Color(0xFF113CCF),
    Color(0xFF3F6B00),
    Color(0xFFC1121F),
    Color(0xFF12833F),
    Color(0xFF2F3437),
    Color(0xFF8A7A00),
    Color(0xFF0A2F52),
    Color(0xFF0B7285),
    Color(0xFF0064FF),
    Color(0xFF6D28D9),
  ];

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
    final indice = nombre.trim().toLowerCase().codeUnits.fold(0, (a, b) => a + b) % _colores.length;
    final logo = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _colores[indice],
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
