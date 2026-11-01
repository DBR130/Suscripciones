// Genera los PNG del ícono de la app y del splash a partir de los SVG del logo
// (assets/logo/). Se corre con el motor de Flutter, sin programas externos:
//
//   flutter test tool/generar_iconos.dart
//   dart run flutter_launcher_icons
//   dart run flutter_native_splash:create
//
// Los PNG quedan en assets/iconos/ (no se incluyen en la app: solo los usan
// flutter_launcher_icons y flutter_native_splash, ver pubspec.yaml).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

/// (svg de origen, png de destino, lado en px, margen de cada lado en px).
const _iconos = [
  // Ícono normal (Android 7 y anteriores): el redondeado.
  ('icono-redondeado.svg', 'icono.png', 1024, 0),
  // Primer plano del ícono adaptativo (Android 8+): el SVG ya trae la zona
  // segura de 108 × 108.
  ('icono-foreground.svg', 'icono-foreground.png', 1024, 0),
  // Splash de Android 12+: 1152 × 1152, el logo cabe en el círculo de 768.
  ('icono-foreground.svg', 'splash-android12.png', 1152, 0),
  // Splash de Android 11 y anteriores: más pequeño (se muestra a 1/4 en dp).
  ('icono-foreground.svg', 'splash.png', 768, 0),
];

void main() {
  test('genera los PNG del ícono y del splash', () async {
    final destino = Directory('assets/iconos')..createSync(recursive: true);
    for (final (svg, png, lado, margen) in _iconos) {
      final texto = File('assets/logo/$svg').readAsStringSync();
      final info = await vg.loadPicture(SvgStringLoader(texto), null);
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      final util = lado - 2 * margen;
      canvas.translate(margen.toDouble(), margen.toDouble());
      canvas.scale(util / info.size.width, util / info.size.height);
      canvas.drawPicture(info.picture);
      final imagen = await recorder.endRecording().toImage(lado, lado);
      final bytes = await imagen.toByteData(format: ui.ImageByteFormat.png);
      File('${destino.path}/$png').writeAsBytesSync(bytes!.buffer.asUint8List());
      info.picture.dispose();
    }
  });
}
