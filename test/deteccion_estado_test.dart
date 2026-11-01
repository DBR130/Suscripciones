import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_suscripciones/Common/AppTheme.dart';
import 'package:flutter_suscripciones/Pages/DashboardPage.dart';
import 'package:flutter_suscripciones/Pages/PerfilPage.dart';
import 'package:flutter_suscripciones/deteccion/aviso_deteccion_pausada.dart';
import 'package:flutter_suscripciones/deteccion/lector_notificaciones.dart';
import 'package:flutter_suscripciones/deteccion/notificacion_capturada.dart';
import 'package:flutter_suscripciones/deteccion/permisos_page.dart';
import 'package:flutter_suscripciones/deteccion/vigilante_deteccion.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'fake_auth_service.dart';
import 'fake_suscripcion_service.dart';

/// Permiso concedido ≠ lector conectado (HyperOS no siempre reconecta el
/// lector tras reinstalar o actualizar la app). Sin celular: la parte nativa
/// se simula con el MethodChannel.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const metodos = MethodChannel('subtrack/deteccion');
  final mensajero = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late bool permiso;
  late bool conectado;
  /// Si es true, el lector se conecta al pedir la reconexión.
  late bool reconectaAlPedir;
  late List<MethodCall> llamadas;

  setUp(() {
    permiso = true;
    conectado = false;
    reconectaAlPedir = false;
    llamadas = [];
    mensajero.setMockMethodCallHandler(metodos, (call) async {
      llamadas.add(call);
      switch (call.method) {
        case 'estado':
          return {'permiso': permiso, 'conectado': conectado, 'es_debug': true, 'modo_descubrimiento': false};
        case 'reconectar':
          if (reconectaAlPedir) conectado = true;
          return null;
        case 'abrirAjustesAcceso':
          return true;
      }
      return null;
    });
  });

  tearDown(() => mensajero.setMockMethodCallHandler(metodos, null));

  VigilanteDeteccion vigilante({bool disponible = true}) => VigilanteDeteccion(
        LectorNotificaciones(disponible: disponible),
        espera: const Duration(milliseconds: 200),
        intervalo: const Duration(milliseconds: 50),
      );

  int veces(String metodo) => llamadas.where((c) => c.method == metodo).length;

  group('regla del estado', () {
    EstadoLector lector({required bool permiso, required bool conectado}) =>
        EstadoLector(permiso: permiso, conectado: conectado, esDebug: false, modoDescubrimiento: false);

    test('permiso sí y lector no: comprobando y, tras los intentos, pausada', () {
      final e = lector(permiso: true, conectado: false);
      expect(estadoDeteccion(e, esperaTerminada: false), EstadoDeteccion.comprobando);
      expect(estadoDeteccion(e, esperaTerminada: true), EstadoDeteccion.pausada);
    });

    test('permiso y lector conectado: activa', () {
      expect(estadoDeteccion(lector(permiso: true, conectado: true), esperaTerminada: true), EstadoDeteccion.activa);
    });

    test('sin permiso: sin permiso, esté o no conectado', () {
      expect(estadoDeteccion(lector(permiso: false, conectado: false), esperaTerminada: true), EstadoDeteccion.sinPermiso);
      expect(estadoDeteccion(lector(permiso: false, conectado: true), esperaTerminada: false), EstadoDeteccion.sinPermiso);
    });
  });

  group('VigilanteDeteccion', () {
    test('permiso sí y lector que no reconecta: intenta reconectar y queda pausada', () async {
      final v = vigilante();
      expect(await v.verificar(motivo: 'prueba'), EstadoDeteccion.pausada);
      expect(v.estado.value, EstadoDeteccion.pausada);
      final reconectar = llamadas.singleWhere((c) => c.method == 'reconectar');
      expect(reconectar.arguments, {'motivo': 'prueba'});
      expect(veces('estado'), greaterThan(2)); // siguió consultando mientras esperaba
    });

    test('si la reconexión funciona, queda activa', () async {
      reconectaAlPedir = true;
      expect(await vigilante().verificar(), EstadoDeteccion.activa);
    });

    test('ya conectado: activa, sin pedir reconexión', () async {
      conectado = true;
      expect(await vigilante().verificar(), EstadoDeteccion.activa);
      expect(veces('reconectar'), 0);
    });

    test('sin permiso: no intenta reconectar', () async {
      permiso = false;
      expect(await vigilante().verificar(), EstadoDeteccion.sinPermiso);
      expect(veces('reconectar'), 0);
    });

    test('fuera de Android: no disponible', () async {
      final v = vigilante(disponible: false);
      expect(v.estado.value, EstadoDeteccion.noDisponible);
      expect(await v.verificar(), EstadoDeteccion.noDisponible);
      expect(llamadas, isEmpty);
    });

    test('dos verificaciones a la vez comparten la misma', () async {
      final v = vigilante();
      await Future.wait([v.verificar(), v.verificar()]);
      expect(veces('reconectar'), 1);
    });
  });

  // ─── Pantallas ──────────────────────────────────────────────────────────

  /// En los widget tests el tiempo es simulado: hay que avanzarlo para que
  /// el vigilante termine de esperar al lector.
  Future<void> esperar(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  }


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
    await esperar(tester);
  }

  group('Perfil', () {
    testWidgets('permiso sí y lector no: no dice "Activo", dice que está pausada', (tester) async {
      final v = vigilante();
      await abrir(tester, '/perfil', {'/perfil': () => PerfilPage(authService: FakeAuthService(), vigilante: v)});
      expect(find.text('Detección pausada · toca para reactivarla'), findsOneWidget);
      expect(find.text('Activo · detección automática encendida'), findsNothing);

      // Tocarlo abre el ajuste para apagar y encender el acceso.
      await tester.tap(find.text('Permiso de notificaciones'));
      await tester.pumpAndSettle();
      expect(veces('abrirAjustesAcceso'), 1);
      expect(find.text('Desactiva y vuelve a activar el acceso de SubTrack'), findsOneWidget);
    });

    testWidgets('si se reconecta, dice "Activo"', (tester) async {
      reconectaAlPedir = true;
      await abrir(tester, '/perfil', {'/perfil': () => PerfilPage(authService: FakeAuthService(), vigilante: vigilante())});
      expect(find.text('Activo · detección automática encendida'), findsOneWidget);
    });

    test('textos del interruptor', () {
      expect(textoInterruptorDeteccion(EstadoDeteccion.activa), 'Activo · detección automática encendida');
      expect(textoInterruptorDeteccion(EstadoDeteccion.pausada), 'Detección pausada · toca para reactivarla');
      expect(textoInterruptorDeteccion(EstadoDeteccion.sinPermiso), 'Desactivado · solo registro manual');
    });
  });

  group('aviso en el dashboard', () {
    testWidgets('aparece solo con la detección pausada y abre el ajuste', (tester) async {
      final v = vigilante();
      await abrir(tester, '/resumen', {
        '/resumen': () => DashboardPage(
              authService: FakeAuthService(),
              suscripcionService: FakeSuscripcionService(),
              vigilante: v,
            ),
      });
      expect(find.text(AvisoDeteccionPausada.titulo), findsNothing); // aún comprobando

      v.verificar();
      await esperar(tester);
      expect(find.text(AvisoDeteccionPausada.titulo), findsOneWidget);
      expect(find.text(AvisoDeteccionPausada.texto), findsOneWidget);

      await tester.tap(find.text('Abrir el ajuste'));
      await tester.pumpAndSettle();
      expect(veces('abrirAjustesAcceso'), 1);

      // Al volver con el lector conectado, el aviso desaparece.
      conectado = true;
      v.verificar();
      await esperar(tester);
      expect(find.text(AvisoDeteccionPausada.titulo), findsNothing);
    });
  });

  group('pantalla 03', () {
    testWidgets('permiso sí y lector no: guía a apagar y encender el acceso, y al conectar sigue', (tester) async {
      await abrir(tester, '/permisos', {
        '/permisos': () => PermisosPage(vigilante: vigilante()),
        '/escaneo': () => const Scaffold(body: Text('ESCANEO')),
      });

      await tester.tap(find.text('Dar permiso y detectar'));
      await esperar(tester);
      expect(find.text('ESCANEO'), findsNothing);
      expect(find.text(AvisoDeteccionPausada.titulo), findsOneWidget);
      expect(veces('abrirAjustesAcceso'), 0); // el permiso ya estaba: primero intenta reconectar

      await tester.tap(find.text('Abrir el ajuste'));
      await tester.pumpAndSettle();
      expect(veces('abrirAjustesAcceso'), 1);

      // El usuario apaga y enciende el acceso: el lector conecta.
      conectado = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await esperar(tester);
      expect(find.text('ESCANEO'), findsOneWidget);
    });
  });
}
