import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_suscripciones/Common/AppTheme.dart';
import 'package:flutter_suscripciones/Common/Routers.dart';
import 'package:flutter_suscripciones/Pages/DashboardPage.dart';
import 'package:flutter_suscripciones/Pages/PerfilPage.dart';
import 'package:flutter_suscripciones/deteccion/aviso_segundo_plano.dart';
import 'package:flutter_suscripciones/deteccion/depuracion_deteccion_page.dart';
import 'package:flutter_suscripciones/deteccion/guia_segundo_plano.dart';
import 'package:flutter_suscripciones/deteccion/lector_notificaciones.dart';
import 'package:flutter_suscripciones/deteccion/vigilante_deteccion.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'fake_auth_service.dart';
import 'fake_suscripcion_service.dart';

/// Encargo C: guía "Mantén SubTrack activa en segundo plano", aviso en Inicio
/// y fila en Perfil. La parte nativa (canal subtrack/sistema) se simula.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const sistema = MethodChannel('subtrack/sistema');
  const deteccion = MethodChannel('subtrack/deteccion');
  final mensajero = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late String grupo;
  late bool bateria;
  late List<String> llamadas;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    grupo = 'xiaomi';
    bateria = false;
    llamadas = [];
    mensajero.setMockMethodCallHandler(sistema, (call) async {
      llamadas.add(call.method);
      return switch (call.method) {
        'segundoPlano' => {'fabricante': 'Xiaomi', 'grupo': grupo, 'bateria_sin_restricciones': bateria},
        _ => true,
      };
    });
    mensajero.setMockMethodCallHandler(deteccion, (call) async {
      if (call.method == 'estado') {
        return {'permiso': true, 'conectado': true, 'es_debug': true, 'modo_descubrimiento': false};
      }
      return null;
    });
  });

  tearDown(() {
    mensajero.setMockMethodCallHandler(sistema, null);
    mensajero.setMockMethodCallHandler(deteccion, null);
  });

  SistemaSegundoPlano sistemaFalso() => SistemaSegundoPlano(disponible: true);

  Future<void> abrir(WidgetTester tester, String inicial, Map<String, Widget Function()> rutas) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp.router(
      theme: AppTheme.dark,
      routerConfig: GoRouter(initialLocation: inicial, routes: [
        for (final MapEntry(key: ruta, value: pantalla) in rutas.entries)
          GoRoute(path: ruta, builder: (_, _) => pantalla()),
      ]),
    ));
    await tester.pumpAndSettle();
  }

  group('instrucciones por marca', () {
    test('Xiaomi conserva los textos que ya se probaron', () {
      final i = instruccionesSegundoPlano('xiaomi');
      expect(i.ajuste, 'Inicio automático');
      expect(i.pasos.join(' '), contains('Inicio automático: actívalo para SubTrack.'));
      expect(i.bateria, contains('"Ahorro de batería"'));
      expect(i.bateria, contains('"Sin restricciones"'));
    });

    test('cada grupo dice qué interruptor buscar', () {
      for (final g in ['samsung', 'oppo', 'vivo', 'huawei']) {
        final i = instruccionesSegundoPlano(g);
        expect(i.ajuste, isNotNull, reason: g);
        expect(i.pasos, isNotEmpty, reason: g);
      }
    });

    test('otras marcas: solo la batería', () {
      final i = instruccionesSegundoPlano('otra');
      expect(i.ajuste, isNull);
      expect(i.pasos, isEmpty);
    });

    test('sin emojis', () {
      final emoji = RegExp(r'[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}]', unicode: true);
      for (final g in ['xiaomi', 'samsung', 'oppo', 'vivo', 'huawei', 'otra']) {
        final i = instruccionesSegundoPlano(g);
        expect(emoji.hasMatch([i.ajuste ?? '', ...i.pasos, i.bateria].join()), isFalse, reason: g);
      }
      expect(emoji.hasMatch(textoAvisoSegundoPlano), isFalse);
    });
  });

  group('guía', () {
    testWidgets('Xiaomi: explica por qué, abre la pantalla de la marca y la de batería', (tester) async {
      await abrir(tester, '/guia', {
        '/guia': () => GuiaSegundoPlanoPage(sistema: sistemaFalso(), registro: RegistroSegundoPlano()),
      });
      expect(find.text('Mantén SubTrack activa en segundo plano'), findsOneWidget);
      expect(find.textContaining('aunque la app esté cerrada'), findsOneWidget);
      expect(find.text('Inicio automático: actívalo para SubTrack.'), findsOneWidget);
      expect(find.text('Pendiente'), findsOneWidget);

      await tester.tap(find.text('Abrir ajustes'));
      await tester.pumpAndSettle();
      expect(llamadas, contains('abrirSegundoPlano'));

      await tester.tap(find.text('Abrir ajustes de batería'));
      await tester.pumpAndSettle();
      expect(llamadas, contains('abrirBateria'));
    });

    testWidgets('al volver de los ajustes muestra la batería ya activa', (tester) async {
      await abrir(tester, '/guia', {
        '/guia': () => GuiaSegundoPlanoPage(sistema: sistemaFalso(), registro: RegistroSegundoPlano()),
      });
      bateria = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('Activo'), findsOneWidget);
    });

    testWidgets('otras marcas: sin "Abrir ajustes", solo la batería', (tester) async {
      grupo = 'otra';
      await abrir(tester, '/guia', {
        '/guia': () => GuiaSegundoPlanoPage(sistema: sistemaFalso(), registro: RegistroSegundoPlano()),
      });
      expect(find.text('Abrir ajustes'), findsNothing);
      expect(find.text('Abrir ajustes de batería'), findsOneWidget);
    });

    testWidgets('"Ya lo activé" guarda que la vio y vuelve', (tester) async {
      await abrir(tester, '/', {
        '/': () => Builder(
              builder: (context) => TextButton(
                onPressed: () => context.push('/guia'),
                child: const Text('IR'),
              ),
            ),
        '/guia': () => GuiaSegundoPlanoPage(
              sistema: sistemaFalso(),
              registro: RegistroSegundoPlano(),
              ahora: () => DateTime(2026, 11, 6),
            ),
      });
      await tester.tap(find.text('IR'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ya lo activé'));
      await tester.pumpAndSettle();
      expect(find.text('IR'), findsOneWidget);
      expect(await RegistroSegundoPlano().guiaVista(), DateTime(2026, 11, 6));
    });
  });

  group('aviso en Inicio', () {
    testWidgets('se ve si el control lo publica, lleva a la guía y se puede cerrar', (tester) async {
      final control = ControlSegundoPlano();
      await abrir(tester, '/resumen', {
        '/resumen': () => DashboardPage(
              authService: FakeAuthService(),
              suscripcionService: FakeSuscripcionService(),
              segundoPlano: control,
            ),
        Routers.segundoPlano: () => const Scaffold(body: Text('GUIA')),
      });
      expect(find.text(textoAvisoSegundoPlano), findsNothing);

      control.avisoVisible.value = true;
      await tester.pumpAndSettle();
      expect(find.text(textoAvisoSegundoPlano), findsOneWidget);

      await tester.tap(find.byTooltip('Cerrar aviso'));
      await tester.pumpAndSettle();
      expect(find.text(textoAvisoSegundoPlano), findsNothing);

      control.avisoVisible.value = true;
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cómo activarlo'));
      await tester.pumpAndSettle();
      expect(find.text('GUIA'), findsOneWidget);
    });
  });

  group('Depuración', () {
    testWidgets('muestra marca, batería y último aviso, y puede forzar el aviso', (tester) async {
      final control = ControlSegundoPlano(ahora: () => DateTime(2026, 11, 6, 8, 30));
      tester.view.physicalSize = const Size(1080, 8000);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark,
        home: DepuracionDeteccionPage(
          lector: LectorNotificaciones(disponible: true),
          segundoPlano: control,
          sistema: sistemaFalso(),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Xiaomi (xiaomi)'), findsOneWidget);
      expect(find.text('Batería sin restricciones'), findsOneWidget);
      expect(find.text('Último aviso de falla'), findsOneWidget);
      expect(find.text('Nunca'), findsWidgets);

      await tester.tap(find.text('Forzar aviso de falla'));
      await tester.pumpAndSettle();
      expect(control.avisoVisible.value, isTrue);
      expect(find.text('06/11 08:30:00'), findsOneWidget);
    });
  });

  group('Perfil', () {
    testWidgets('la fila "Segundo plano" abre la guía y dice si ya se revisó', (tester) async {
      await RegistroSegundoPlano().marcarGuiaVista(DateTime(2026, 11, 1));
      await abrir(tester, '/perfil', {
        '/perfil': () => PerfilPage(
              authService: FakeAuthService(),
              vigilante: VigilanteDeteccion(LectorNotificaciones(disponible: true)),
              segundoPlano: RegistroSegundoPlano(),
            ),
        Routers.segundoPlano: () => const Scaffold(body: Text('GUIA')),
      });
      expect(find.text('Segundo plano'), findsOneWidget);
      expect(find.text('Revisado ›'), findsOneWidget);
      await tester.tap(find.text('Segundo plano'));
      await tester.pumpAndSettle();
      expect(find.text('GUIA'), findsOneWidget);
    });
  });
}

