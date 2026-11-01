import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_suscripciones/widgets/animacion_inicio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Animación de inicio (design/logo/4-cuenta-regresiva/animacion-inicio.md).
void main() {
  Widget app({required VoidCallback alTerminar, bool reducir = false}) => MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reducir),
          child: Scaffold(
            backgroundColor: ColoresLogo.fondo,
            body: Center(
              child: RepaintBoundary(
                key: const Key('logo'),
                child: AnimacionInicio(alTerminar: alTerminar),
              ),
            ),
          ),
        ),
      );

  testWidgets('dura 1500 ms más 300 de pausa y luego avisa una sola vez', (tester) async {
    var avisos = 0;
    await tester.pumpWidget(app(alTerminar: () => avisos++));
    // El reloj de la animación arranca en el primer cuadro.
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(AnimacionInicio.duracion);
    await tester.pump(const Duration(milliseconds: 299));
    expect(avisos, 0);
    await tester.pump(const Duration(milliseconds: 2));
    expect(avisos, 1);

    // Si la app aún no sigue, el anillo gira en bucle sin volver a avisar.
    await tester.pump(const Duration(seconds: 3));
    expect(avisos, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('con animaciones reducidas avisa a los 300 ms', (tester) async {
    var avisos = 0;
    await tester.pumpWidget(app(alTerminar: () => avisos++, reducir: true));
    await tester.pump(const Duration(milliseconds: 301));
    expect(avisos, 1);
  });

  testWidgets('el estado final dibuja el logo completo', (tester) async {
    await tester.pumpWidget(app(alTerminar: () {}, reducir: true));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.runAsync(() async {
      // Espera a que flutter_svg cargue el nombre.
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
    final caja = tester.renderObject<RenderRepaintBoundary>(find.byKey(const Key('logo')));
    final bytes = await tester.runAsync(() async {
      final imagen = await caja.toImage(pixelRatio: 2);
      return imagen.toByteData(format: ui.ImageByteFormat.png);
    });
    expect(bytes, isNotNull);
    // Para revisarla a mano: SUBTRACK_CAPTURA=ruta.png flutter test ...
    final ruta = Platform.environment['SUBTRACK_CAPTURA'];
    if (ruta != null) File(ruta).writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}
