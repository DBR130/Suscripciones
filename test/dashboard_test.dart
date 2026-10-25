import 'package:flutter/material.dart';
import 'package:flutter_suscripciones/Common/AppTheme.dart';
import 'package:flutter_suscripciones/Pages/DashboardPage.dart';
import 'package:flutter_suscripciones/models/suscripcion.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'fake_auth_service.dart';
import 'fake_suscripcion_service.dart';

void main() {
  Widget app(FakeSuscripcionService service) => MaterialApp.router(
        theme: AppTheme.dark,
        routerConfig: GoRouter(routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => DashboardPage(
              authService: FakeAuthService(),
              suscripcionService: service,
            ),
          ),
          GoRoute(path: '/suscripcion/nueva', builder: (_, _) => const Text('FORMULARIO')),
        ]),
      );

  void pantallaAlta(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
  }

  testWidgets('sin suscripciones muestra el estado vacío', (tester) async {
    pantallaAlta(tester);
    await tester.pumpWidget(app(FakeSuscripcionService()));
    await tester.pumpAndSettle();

    expect(find.text('Aún no tienes suscripciones'), findsOneWidget);
    expect(find.textContaining('0 activas'), findsOneWidget);

    expect(find.textContaining('Te avisaremos 3 días antes'), findsOneWidget);
    expect(find.text('Gasto por categoría'), findsNothing);

    await tester.tap(find.text('Agregar suscripción'));
    await tester.pumpAndSettle();
    expect(find.text('FORMULARIO'), findsOneWidget);
  });

  testWidgets('agrupa por próximos 7 días y más adelante', (tester) async {
    pantallaAlta(tester);
    final hoy = DateUtils.dateOnly(DateTime.now());
    Suscripcion sus(int id, String nombre, int dias, {bool prueba = false, String? categoria}) => Suscripcion(
          id: id,
          nombreServicio: nombre,
          categoria: categoria,
          monto: 10000,
          frecuencia: Frecuencia.mensual,
          fechaProximoCobro: hoy.add(Duration(days: dias)),
          esPruebaGratis: prueba,
          fechaFinPrueba: prueba ? hoy.add(Duration(days: dias)) : null,
        );
    final service = FakeSuscripcionService(iniciales: [
      sus(1, 'Canva', 40, categoria: 'Diseño'),
      sus(2, 'Netflix', 1, categoria: 'Streaming'),
      sus(3, 'GeForce', 2, prueba: true),
    ]);

    await tester.pumpWidget(app(service));
    await tester.pumpAndSettle();

    expect(find.text('Próximos 7 días'), findsOneWidget);
    expect(find.text('Más adelante'), findsOneWidget);
    expect(find.text('Se cobra mañana'), findsOneWidget);
    expect(find.textContaining('Prueba gratis: se convierte'), findsOneWidget);
    expect(find.textContaining('3 activas'), findsOneWidget);

    // La categoría reemplaza la línea "Mensual · Registro manual".
    expect(find.text('Streaming'), findsOneWidget);
    expect(find.text('Mensual · Registro manual'), findsOneWidget); // GeForce

    // Gasto por categoría (resumen del backend).
    expect(find.text('Gasto por categoría'), findsOneWidget);
    expect(find.text('Streaming · 1'), findsOneWidget);
    expect(find.text('Sin categoría · 1'), findsOneWidget);
    expect(find.text(r'$10.000/mes'), findsNWidgets(2));

    // Orden: Netflix (1 día), GeForce (2 días), Canva (40 días).
    final y = [
      for (final n in ['Netflix', 'GeForce', 'Canva']) tester.getTopLeft(find.text(n)).dy,
    ];
    expect(y[0] < y[1] && y[1] < y[2], isTrue);
  });
}
