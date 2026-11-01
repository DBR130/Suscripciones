import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Logo de SubTrack (concepto "Cuenta regresiva": un anillo que se llena
/// hasta el próximo cobro, con la S al centro). Versión para fondos oscuros.
/// - `AppMarca()`: el ícono redondeado grande.
/// - `AppMarca.fila()`: ícono y "SubTrack" al lado (encabezados, bienvenida,
///   login y registro). [altura] cambia el tamaño.
class AppMarca extends StatelessWidget {
  const AppMarca({super.key, this.altura = 64}) : _fila = false;

  const AppMarca.fila({super.key, this.altura = 28}) : _fila = true;

  final bool _fila;
  final double altura;

  static const String iconoAsset = 'assets/logo/icono-redondeado.svg';
  static const String filaAsset = 'assets/logo/logo-nombre-oscuro.svg';

  /// Proporción del logo con nombre (viewBox 239 × 64).
  static const double _proporcionFila = 239 / 64;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      _fila ? filaAsset : iconoAsset,
      height: altura,
      width: _fila ? altura * _proporcionFila : altura,
      semanticsLabel: 'SubTrack',
    );
  }
}
