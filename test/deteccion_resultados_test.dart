import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_suscripciones/Common/AppTheme.dart';
import 'package:flutter_suscripciones/Common/Routers.dart';
import 'package:flutter_suscripciones/Pages/PerfilPage.dart';
import 'package:flutter_suscripciones/deteccion/candidato_suscripcion.dart';
import 'package:flutter_suscripciones/deteccion/catalogo_servicios.dart';
import 'package:flutter_suscripciones/services/recordatorios_service.dart';
import 'package:flutter_suscripciones/deteccion/descartadas_page.dart';
import 'package:flutter_suscripciones/deteccion/resultados_deteccion_page.dart';
import 'package:flutter_suscripciones/models/suscripcion.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'deteccion_flujo_test.dart' show FakeDeteccionService, candidato;
import 'fake_auth_service.dart';
import 'fake_suscripcion_service.dart';

/// Pantalla 05 con procesadores de pago y nombre editable (tickets T4 a T7).
void main() {
  final catalogo = CatalogoServicios.fromJson({
    'guias': jsonDecode(File('backend/db/guias.json').readAsStringSync()),
    'procesadores': jsonDecode(File('backend/db/procesadores.json').readAsStringSync()),
  });

  Future<void> abrir(WidgetTester tester, FakeDeteccionService servicio, {FakeSuscripcionService? suscripciones}) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp.router(
      theme: AppTheme.dark,
      routerConfig: GoRouter(initialLocation: '/deteccion', routes: [
        GoRoute(
          path: '/deteccion',
          builder: (_, _) => ResultadosDeteccionPage(
            servicio: servicio,
            cargarCatalogo: () async => catalogo,
            suscripcionService: suscripciones,
          ),
        ),
        GoRoute(path: '/resumen', builder: (_, _) => const Scaffold(body: Text('DASHBOARD'))),
      ]),
    ));
    await tester.pumpAndSettle();
  }

  group('procesadores (T4)', () {
    testWidgets('se muestra "Pago procesado por EBANX" y pide el nombre del servicio', (tester) async {
      final servicio = FakeDeteccionService(lista: [candidato(7, 'EBANX', 19900, pagos: 2, procesador: 'EBANX')]);
      await abrir(tester, servicio);
      expect(find.text('Pago procesado por EBANX'), findsOneWidget);
      expect(find.text('¿Qué servicio es?'), findsOneWidget);

      // Confirmar sin nombre abre la hoja para escribirlo.
      await tester.tap(find.text('Confirmar 1 suscripción'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('campo-nombre')), findsOneWidget);
      expect(servicio.confirmados, isEmpty);

      // Sin nombre no se puede guardar.
      await tester.tap(find.text('Guardar corrección'));
      await tester.pumpAndSettle();
      expect(find.text('Escribe qué servicio es'), findsOneWidget);

      // Con el nombre, la confirmación que se pidió sigue sola.
      await tester.enterText(find.byKey(const Key('campo-nombre')), 'Crunchyroll');
      await tester.tap(find.text('Guardar corrección'));
      await tester.pumpAndSettle();
      expect(servicio.confirmados, [(7, 19900.0, Frecuencia.mensual, 'Crunchyroll')]);
      expect(find.text('DASHBOARD'), findsOneWidget);
    });

    testWidgets('"Es mía" en un procesador sin nombre abre la hoja', (tester) async {
      final servicio = FakeDeteccionService(lista: [candidato(7, 'EBANX', 19900, pagos: 2, procesador: 'EBANX')]);
      await abrir(tester, servicio);
      await tester.tap(find.text('Es mía'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('campo-nombre')), findsOneWidget);
    });
  });

  group('unir el mismo servicio (Crunchyroll duplicado, caso real)', () {
    Future<void> nombrarEbanx(WidgetTester tester) async {
      await tester.tap(find.textContaining('Confirmar'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('campo-nombre')), 'Crunchyroll');
      await tester.tap(find.text('Guardar corrección'));
      await tester.pumpAndSettle();
    }

    testWidgets('con otro candidato de la lista: "¿Los unimos?" → Unir', (tester) async {
      final servicio = FakeDeteccionService(lista: [
        candidato(7, 'EBANX', 19900, pagos: 5, procesador: 'EBANX'),
        candidato(1, 'Crunchyroll', 19900),
      ]);
      await abrir(tester, servicio);
      await nombrarEbanx(tester);
      expect(find.text('Ya tienes Crunchyroll en esta lista. ¿Los unimos?'), findsOneWidget);
      await tester.tap(find.text('Unir'));
      await tester.pumpAndSettle();
      // Una sola confirmación, que se lleva al otro candidato.
      expect(servicio.uniones, [(7, 1, null)]);
      expect(servicio.confirmados.map((c) => c.$1), [7]);
    });

    testWidgets('"Son distintas" confirma las dos por separado', (tester) async {
      final servicio = FakeDeteccionService(lista: [
        candidato(7, 'EBANX', 19900, pagos: 5, procesador: 'EBANX'),
        candidato(1, 'Crunchyroll', 19900),
      ]);
      await abrir(tester, servicio);
      await nombrarEbanx(tester);
      await tester.tap(find.text('Son distintas'));
      await tester.pumpAndSettle();
      expect(servicio.uniones, isEmpty);
      expect(servicio.confirmados.map((c) => c.$1), [7, 1]);
    });

    testWidgets('con una suscripción que ya tiene: los pagos se agregan a ella', (tester) async {
      final servicio = FakeDeteccionService(lista: [candidato(7, 'EBANX', 19900, pagos: 5, procesador: 'EBANX')]);
      final suscripciones = FakeSuscripcionService(iniciales: [
        Suscripcion(
          id: 5,
          nombreServicio: 'Crunchyroll',
          monto: 19900,
          frecuencia: Frecuencia.mensual,
          fechaProximoCobro: DateTime(2026, 11, 16),
        ),
      ]);
      await abrir(tester, servicio, suscripciones: suscripciones);
      await nombrarEbanx(tester);
      expect(find.text('Ya tienes Crunchyroll en tus suscripciones. ¿Los unimos?'), findsOneWidget);
      await tester.tap(find.text('Unir'));
      await tester.pumpAndSettle();
      expect(servicio.uniones, [(7, null, 5)]);
    });
  });

  group('sugerencia por monto (T5)', () {
    testWidgets('a ±5 % del precio de referencia sugiere el servicio sin elegirlo', (tester) async {
      final servicio = FakeDeteccionService(lista: [candidato(7, 'EBANX', 19900, pagos: 2, procesador: 'EBANX')]);
      await abrir(tester, servicio);
      await tester.tap(find.text('Es mía'));
      await tester.pumpAndSettle();
      expect(find.text('¿Es Crunchyroll?'), findsOneWidget);
      // No se elige solo: el campo sigue vacío.
      expect(tester.widget<TextField>(find.byKey(const Key('campo-nombre'))).controller!.text, isEmpty);

      await tester.tap(find.text('¿Es Crunchyroll?'));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byKey(const Key('campo-nombre'))).controller!.text, 'Crunchyroll');
    });

    testWidgets('lejos de cualquier precio de referencia no sugiere nada', (tester) async {
      final servicio = FakeDeteccionService(lista: [candidato(8, 'EBANX', 34900, pagos: 2, procesador: 'EBANX')]);
      await abrir(tester, servicio);
      await tester.tap(find.text('Es mía'));
      await tester.pumpAndSettle();
      expect(find.textContaining('¿Es '), findsNothing);
    });
  });

  group('deshacer descartes (T6)', () {
    testWidgets('"No es mía" descarta al instante y "Deshacer" lo restaura', (tester) async {
      final servicio = FakeDeteccionService(lista: [
        candidato(1, 'Crunchyroll', 19900),
        candidato(2, 'Claude', 68139.27),
      ]);
      await abrir(tester, servicio);
      await tester.tap(find.text('No es mía').at(1));
      await tester.pump();
      expect(servicio.descartados, [2]);
      expect(find.text('Descartamos Claude'), findsOneWidget);
      // 5 segundos para alcanzar a deshacer.
      expect(tester.widget<SnackBar>(find.byType(SnackBar)).duration, const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.text('Claude'), findsNothing);
      expect(find.text('Confirmar 1 suscripción'), findsOneWidget);

      await tester.tap(find.text('Deshacer'));
      await tester.pumpAndSettle();
      expect(servicio.restaurados, [2]);
      expect(find.text('Claude'), findsOneWidget);
      expect(find.text('Confirmar 2 suscripciones'), findsOneWidget);
    });

    testWidgets('"Detecciones descartadas" lista y vuelve a proponer', (tester) async {
      final servicio = FakeDeteccionService()
        ..listaDescartadas = [
          candidato(2, 'Claude', 68139.27),
          candidato(9, 'EBANX', 34900, procesador: 'EBANX'),
        ];
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(theme: AppTheme.dark, home: DescartadasPage(servicio: servicio)));
      await tester.pumpAndSettle();

      expect(find.text('Claude'), findsOneWidget);
      expect(find.text('Pago procesado por EBANX'), findsOneWidget);
      expect(find.text(r'$34.900 · Mensual'), findsOneWidget);

      await tester.tap(find.text('Volver a proponer').first);
      await tester.pumpAndSettle();
      expect(servicio.restaurados, [2]);
      expect(find.text('Claude'), findsNothing);
      expect(find.text('Volveremos a proponer Claude'), findsOneWidget);
    });
  });

  group('reapertura (T7)', () {
    final reabierto = CandidatoSuscripcion.fromJson({
      'id': 4,
      'comercio_normalizado': 'Gimnasio La 80',
      'monto': 99900,
      'moneda': 'COP',
      'frecuencia_estimada': 'mensual',
      'fecha_ultimo_pago': '2026-10-05',
      'reabierto': true,
      'motivo': 'Vimos 3 cobros mensuales de \$99.900',
    });

    testWidgets('la tarjeta dice por qué se vuelve a proponer', (tester) async {
      await abrir(tester, FakeDeteccionService(lista: [reabierto]));
      expect(find.text('Vimos 3 cobros mensuales de \$99.900'), findsOneWidget);
    });

    test('el aviso del flujo B también lo dice', () {
      expect(textoAvisoCandidato(reabierto), 'Vimos 3 cobros mensuales de \$99.900. Toca para confirmarla o descartarla.');
    });
  });

  testWidgets('Perfil abre "Detecciones descartadas"', (tester) async {
    tester.view.physicalSize = const Size(1080, 3200);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp.router(
      theme: AppTheme.dark,
      routerConfig: GoRouter(initialLocation: '/perfil', routes: [
        GoRoute(path: '/perfil', builder: (_, _) => PerfilPage(authService: FakeAuthService())),
        GoRoute(path: Routers.deteccionesDescartadas, builder: (_, _) => const Scaffold(body: Text('DESCARTADAS'))),
      ]),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Detecciones descartadas'));
    await tester.pumpAndSettle();
    expect(find.text('DESCARTADAS'), findsOneWidget);
  });

  group('nombre editable (T4)', () {
    testWidgets('el lápiz permite cambiar el nombre de cualquier candidato, con sugerencias del catálogo',
        (tester) async {
      final servicio = FakeDeteccionService(lista: [candidato(3, 'Gimnasio La 80', 99900, pagos: 2)]);
      await abrir(tester, servicio);
      await tester.tap(find.byTooltip('Corregir nombre, monto y frecuencia'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('campo-nombre')), 'Smart');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Smart Fit'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guardar corrección'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Confirmar 1 suscripción'));
      await tester.pumpAndSettle();
      expect(servicio.confirmados, [(3, 99900.0, Frecuencia.mensual, 'Smart Fit')]);
    });
  });
}
