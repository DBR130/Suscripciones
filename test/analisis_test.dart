import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_suscripciones/Common/AppTheme.dart';
import 'package:flutter_suscripciones/Common/Routers.dart';
import 'package:flutter_suscripciones/Pages/AnalisisPage.dart';
import 'package:flutter_suscripciones/models/analisis.dart';
import 'package:flutter_suscripciones/models/aviso.dart';
import 'package:flutter_suscripciones/models/suscripcion.dart';
import 'package:flutter_suscripciones/services/avisos_nuevos.dart';
import 'package:flutter_suscripciones/widgets/app_shell.dart';
import 'package:flutter_suscripciones/widgets/campana_avisos.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'fake_suscripcion_service.dart';

/// Respuesta de GET /api/analisis con dos monedas, una prueba gratis que pasa
/// a pago y una cancelada.
Map<String, dynamic> respuesta() => {
      'totales': [
        {'moneda': 'COP', 'gasto_mensual': 120700, 'proyeccion_anual': 1448400, 'cantidad': 4},
        {'moneda': 'USD', 'gasto_mensual': 20, 'proyeccion_anual': 240, 'cantidad': 1},
      ],
      'cantidad_activas': 5,
      'gasto_mensual': [
        {
          'moneda': 'COP',
          'meses': [
            for (final (i, t) in [80000, 95000, 0, 110000, 120700, 64900].indexed)
              {'mes': '2026-${(6 + i).toString().padLeft(2, '0')}', 'total': t},
          ],
        },
        {
          'moneda': 'USD',
          'meses': [
            for (var i = 0; i < 6; i++) {'mes': '2026-${(6 + i).toString().padLeft(2, '0')}', 'total': i == 5 ? 20 : 0},
          ],
        },
      ],
      'por_categoria': [
        {'categoria': 'Streaming', 'moneda': 'COP', 'gasto_mensual': 64900, 'cantidad': 2},
        {'categoria': 'Música', 'moneda': 'COP', 'gasto_mensual': 16900, 'cantidad': 1},
        {'categoria': null, 'moneda': 'COP', 'gasto_mensual': 38900, 'cantidad': 1},
        {'categoria': 'Software', 'moneda': 'USD', 'gasto_mensual': 20, 'cantidad': 1},
      ],
      'proximos_cobros': [
        {
          'suscripcion_id': 3,
          'nombre_servicio': 'Max',
          'monto': 19900,
          'moneda': 'COP',
          'fecha': '2026-11-03',
          'dias_restantes': 2,
          'fin_de_prueba': true,
        },
        {
          'suscripcion_id': 1,
          'nombre_servicio': 'Netflix',
          'monto': 38900,
          'moneda': 'COP',
          'fecha': '2026-11-10',
          'dias_restantes': 9,
          'fin_de_prueba': false,
        },
      ],
      'mas_caras': [
        {
          'id': 1,
          'nombre_servicio': 'Netflix',
          'categoria': 'Streaming',
          'moneda': 'COP',
          'monto': 38900,
          'frecuencia': 'mensual',
          'gasto_mensual': 38900,
        },
        {
          'id': 2,
          'nombre_servicio': 'Gimnasio',
          'categoria': null,
          'moneda': 'COP',
          'monto': 360000,
          'frecuencia': 'anual',
          'gasto_mensual': 30000,
        },
      ],
      'ahorro': {
        'totales': [
          {'moneda': 'COP', 'ahorro_anual': 262800, 'ahorro_mensual': 21900, 'cantidad': 1},
        ],
        'cantidad_canceladas': 1,
        'canceladas': [
          {
            'id': 9,
            'nombre_servicio': 'Paramount+',
            'categoria': 'Streaming',
            'moneda': 'COP',
            'fecha_cancelacion': '2026-10-11',
            'ahorro_proyectado_anual': 262800,
          },
        ],
      },
    };

/// Inter para las capturas (en los tests las letras salen como cuadros).
Future<void> cargarInter() async {
  final fuente = FontLoader('Inter');
  for (final peso in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
    fuente.addFont(rootBundle.load('assets/fonts/Inter-$peso.ttf'));
  }
  await fuente.load();
}

/// SUBTRACK_CAPTURA=carpeta flutter test test/analisis_test.dart guarda PNG.
Future<void> capturar(WidgetTester tester, String nombre) async {
  final carpeta = Platform.environment['SUBTRACK_CAPTURA'];
  if (carpeta == null) return;
  final caja = tester.renderObject<RenderRepaintBoundary>(find.byKey(const Key('captura')));
  final bytes = await tester.runAsync(() async {
    final imagen = await caja.toImage(pixelRatio: 1.5);
    return imagen.toByteData(format: ui.ImageByteFormat.png);
  });
  File('$carpeta/$nombre.png').writeAsBytesSync(bytes!.buffer.asUint8List());
}

void main() {
  FlutterSecureStorage.setMockInitialValues({});

  void telefono(WidgetTester tester, {double alto = 2400}) {
    tester.view.physicalSize = Size(1080, alto);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
  }

  test('lee GET /api/analisis', () {
    final a = Analisis.fromJson(respuesta());
    expect(a.monedas, ['COP', 'USD']);
    expect(a.vacio, isFalse);
    expect(a.proximosCobros.first.finDePrueba, isTrue);
    expect(a.proximosCobros.first.fecha, DateTime(2026, 11, 3));
    expect(a.masCaras[1].frecuencia, Frecuencia.anual);
    expect(a.canceladas.single.nombreServicio, 'Paramount+');
    expect(a.ahorroTotales.single.anual, 262800);
    expect(a.gastoMensual.first.meses.last.total, 64900);
  });

  group('pestaña Análisis', () {
    Widget app(FakeSuscripcionService servicio) => MaterialApp(
          theme: AppTheme.dark,
          home: RepaintBoundary(
            key: const Key('captura'),
            child: AnalisisPage(suscripcionService: servicio),
          ),
        );

    testWidgets('muestra proyección, más caras, gráficas, cobros y ahorro', (tester) async {
      telefono(tester, alto: 6400);
      await tester.runAsync(cargarInter);
      await tester.pumpWidget(app(FakeSuscripcionService(analisisFijo: Analisis.fromJson(respuesta()))));
      await tester.pumpAndSettle();

      expect(find.text('Análisis'), findsOneWidget);
      expect(find.text(r'$1.448.400'), findsOneWidget); // proyección anual (ya terminó de contar)
      expect(find.text(r'+ US$240,00 al año'), findsOneWidget);
      expect(find.text('Las más caras'), findsOneWidget);
      expect(find.text('Gimnasio'), findsOneWidget);
      expect(find.text('Gasto de los últimos 6 meses'), findsOneWidget);
      expect(find.text('Pagado este mes'), findsOneWidget);
      expect(find.text('Gasto mensual por categoría'), findsOneWidget);
      expect(find.text('Sin categoría'), findsOneWidget);
      expect(find.text('54 %'), findsOneWidget); // 64.900 de 120.700
      expect(find.text('Próximos 30 días'), findsOneWidget);
      expect(find.text('Termina la prueba gratis'), findsOneWidget);
      expect(find.text('Ahorro por cancelaciones'), findsOneWidget);
      expect(find.text(r'+$262.800'), findsOneWidget);
      await capturar(tester, 'analisis');

      // Con dos monedas aparece el selector: en USD cambia la dona.
      await tester.tap(find.text('USD'));
      await tester.pumpAndSettle();
      expect(find.text('Software'), findsOneWidget);
      expect(find.text('Streaming'), findsNothing);
    });

    testWidgets('sin datos muestra el estado vacío', (tester) async {
      telefono(tester);
      await tester.pumpWidget(app(FakeSuscripcionService()));
      await tester.pumpAndSettle();
      expect(find.text('Aún no hay nada que analizar'), findsOneWidget);
      expect(find.text('Agregar suscripción'), findsOneWidget);
    });

    testWidgets('mientras carga muestra el esqueleto, no un círculo girando', (tester) async {
      telefono(tester);
      await tester.pumpWidget(app(FakeSuscripcionService()));
      expect(find.bySemanticsLabel('Cargando'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.pumpAndSettle();
    });

    testWidgets('en pantalla pequeña y letra grande no se desborda', (tester) async {
      tester.view.physicalSize = const Size(720, 5200);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(size: Size(360, 2600), textScaler: TextScaler.linear(1.3)),
        child: app(FakeSuscripcionService(analisisFijo: Analisis.fromJson(respuesta()))),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('barra flotante y campana', () {
    Aviso aviso(int id) => Aviso(
          tipo: TipoAviso.proximoCobro,
          suscripcionId: id,
          nombreServicio: 'Servicio $id',
          monto: 10000,
          moneda: 'COP',
          frecuencia: Frecuencia.mensual,
          fecha: DateTime(2026, 11, 10),
          fechaAviso: DateTime(2026, 11, 7),
          diasRestantes: 3,
        );

    test('cuenta solo los avisos que no se han visto', () {
      final contador = AvisosNuevos(FakeSuscripcionService());
      final avisos = [aviso(1), aviso(2), aviso(3)];
      contador.contar(avisos, {AvisosNuevos.clave(avisos[0])});
      expect(contador.value, 2);
    });

    testWidgets('4 pestañas, "+" abre el formulario y la campana muestra los nuevos', (tester) async {
      telefono(tester);
      await tester.runAsync(cargarInter);
      final servicio = FakeSuscripcionService(listaAvisos: [aviso(1), aviso(2)]);
      final contador = AvisosNuevos(servicio);
      final router = GoRouter(
        initialLocation: Routers.analisis,
        routes: [
          GoRoute(path: Routers.nuevaSuscripcion, builder: (_, _) => const Scaffold(body: Text('FORMULARIO'))),
          GoRoute(path: Routers.avisos, builder: (_, _) => const Scaffold(body: Text('AVISOS'))),
          ShellRoute(
            builder: (context, state, child) => AppShell(avisosNuevos: contador, child: child),
            routes: [
              for (final ruta in [Routers.dashboard, Routers.suscripciones, Routers.perfil])
                GoRoute(path: ruta, builder: (_, _) => Scaffold(body: Text('PESTAÑA $ruta'))),
              GoRoute(
                path: Routers.analisis,
                builder: (_, _) => AnalisisPage(suscripcionService: servicio),
              ),
            ],
          ),
        ],
      );
      await tester.pumpWidget(RepaintBoundary(
        key: const Key('captura'),
        child: MaterialApp.router(theme: AppTheme.dark, routerConfig: router),
      ));
      await tester.pumpAndSettle();

      for (final texto in ['Resumen', 'Suscripciones', 'Análisis', 'Perfil']) {
        expect(find.text(texto), findsWidgets);
      }
      expect(find.bySemanticsLabel('Avisos, 2 nuevos'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      await capturar(tester, 'barra');

      await tester.tap(find.text('Perfil'));
      await tester.pumpAndSettle();
      expect(find.text('PESTAÑA ${Routers.perfil}'), findsOneWidget);

      final cambiosAntes = AppShell.cambios.value;
      await tester.tap(find.bySemanticsLabel('Agregar suscripción'));
      await tester.pumpAndSettle();
      expect(find.text('FORMULARIO'), findsOneWidget);
      router.pop();
      await tester.pumpAndSettle();
      expect(AppShell.cambios.value, cambiosAntes + 1);

      // Al ver los avisos, el contador vuelve a 0.
      await tester.tap(find.text('Análisis'));
      await tester.pumpAndSettle();
      await contador.marcarVistos(servicio.listaAvisos);
      await tester.pumpAndSettle();
      expect(find.byType(CampanaAvisos), findsOneWidget);
      expect(find.bySemanticsLabel('Avisos'), findsOneWidget);
    });
  });
}
