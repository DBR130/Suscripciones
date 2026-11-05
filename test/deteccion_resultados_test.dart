import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_suscripciones/Common/AppTheme.dart';
import 'package:flutter_suscripciones/deteccion/catalogo_servicios.dart';
import 'package:flutter_suscripciones/deteccion/resultados_deteccion_page.dart';
import 'package:flutter_suscripciones/models/suscripcion.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'deteccion_flujo_test.dart' show FakeDeteccionService, candidato;

/// Pantalla 05 con procesadores de pago y nombre editable (tickets T4 a T7).
void main() {
  final catalogo = CatalogoServicios.fromJson({
    'guias': jsonDecode(File('backend/db/guias.json').readAsStringSync()),
    'procesadores': jsonDecode(File('backend/db/procesadores.json').readAsStringSync()),
  });

  Future<void> abrir(WidgetTester tester, FakeDeteccionService servicio) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp.router(
      theme: AppTheme.dark,
      routerConfig: GoRouter(initialLocation: '/deteccion', routes: [
        GoRoute(
          path: '/deteccion',
          builder: (_, _) => ResultadosDeteccionPage(servicio: servicio, cargarCatalogo: () async => catalogo),
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
