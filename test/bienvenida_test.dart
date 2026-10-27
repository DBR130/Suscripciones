import 'package:flutter/material.dart';
import 'package:flutter_suscripciones/Common/AppTheme.dart';
import 'package:flutter_suscripciones/Common/Routers.dart';
import 'package:flutter_suscripciones/services/api_client.dart';
import 'package:flutter_suscripciones/services/auth_service.dart';
import 'package:flutter_suscripciones/services/suscripcion_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Router real de la app: así se prueba también que login y registro
  // quedan encima de la bienvenida.
  Widget app() {
    final api = ApiClient();
    return MaterialApp.router(
      theme: AppTheme.dark,
      routerConfig: Routers.crear(AuthService(api), SuscripcionService(api)),
    );
  }

  Future<void> abrir(
    WidgetTester tester, {
    Size tamano = const Size(1080, 2400),
    double densidad = 3,
  }) async {
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = densidad;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
  }

  testWidgets('recorre los 3 slides con "Siguiente" y termina en registro', (tester) async {
    await abrir(tester);

    expect(find.text('SubTrack'), findsOneWidget);
    expect(find.text('Todo lo que pagas cada mes, en una sola lista.'), findsOneWidget);

    await tester.tap(find.text('Siguiente'));
    await tester.pumpAndSettle();
    expect(find.text('Te avisamos antes del cobro, no después.'), findsOneWidget);
    expect(find.text('Siguiente'), findsOneWidget);

    await tester.tap(find.text('Siguiente'));
    await tester.pumpAndSettle();
    expect(find.text('No adivinamos qué usas. Tú decides.'), findsOneWidget);
    expect(find.text('Siguiente'), findsNothing);
    expect(find.text('Ya tengo cuenta'), findsOneWidget);

    await tester.tap(find.text('Crear mi cuenta'));
    await tester.pumpAndSettle();
    expect(find.text('Crea tu cuenta'), findsOneWidget); // RegistroPage

    // "Atrás" vuelve a la bienvenida.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Ya tengo cuenta'), findsOneWidget);
  });

  testWidgets('los slides también se pasan con el dedo', (tester) async {
    await abrir(tester);

    await tester.drag(find.byType(PageView), const Offset(-400, 0));
    await tester.pumpAndSettle();
    expect(find.text('Te avisamos antes del cobro, no después.'), findsOneWidget);
  });

  testWidgets('"Ya tengo cuenta" lleva al login y "atrás" vuelve', (tester) async {
    await abrir(tester);

    await tester.tap(find.text('Ya tengo cuenta'));
    await tester.pumpAndSettle();
    expect(find.text('Hola de nuevo'), findsOneWidget); // LoginPage

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Todo lo que pagas cada mes, en una sola lista.'), findsOneWidget);
  });

  testWidgets('del login al registro y "atrás" vuelve a la bienvenida', (tester) async {
    await abrir(tester);

    await tester.tap(find.text('Ya tengo cuenta'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('No tengo cuenta, quiero registrarme'));
    await tester.pumpAndSettle();
    expect(find.text('Crea tu cuenta'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Ya tengo cuenta'), findsOneWidget);
  });

  testWidgets('no se desborda en una pantalla pequeña con letra grande', (tester) async {
    // 320×568 (como un iPhone SE de primera generación) y texto al 130 %.
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await abrir(tester, tamano: const Size(640, 1136), densidad: 2);

    // Un desborde ("RenderFlex overflowed") haría fallar el test.
    expect(tester.takeException(), isNull);
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.text('Siguiente'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    expect(find.text('Crear mi cuenta'), findsOneWidget);
  });
}
