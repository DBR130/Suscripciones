import 'package:flutter/material.dart';
import 'package:flutter_suscripciones/Common/AppTheme.dart';
import 'package:flutter_suscripciones/Pages/SuscripcionFormPage.dart';
import 'package:flutter_suscripciones/models/suscripcion.dart';
import 'package:flutter_suscripciones/services/suscripcion_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'fake_suscripcion_service.dart';

void main() {
  /// Abre el formulario desde una pantalla de inicio que muestra el resultado.
  Widget app(SuscripcionService service, {Suscripcion? inicial}) {
    final resultado = ValueNotifier<String>('');
    return MaterialApp.router(
      theme: AppTheme.dark,
      routerConfig: GoRouter(routes: [
        GoRoute(
          path: '/',
          builder: (context, _) => Scaffold(
            body: Column(
              children: [
                TextButton(
                  onPressed: () async {
                    final s = await context.push<Suscripcion>('/form');
                    if (s != null) resultado.value = 'GUARDADA ${s.nombreServicio}';
                  },
                  child: const Text('ABRIR'),
                ),
                ValueListenableBuilder(
                  valueListenable: resultado,
                  builder: (_, texto, _) => Text(texto),
                ),
              ],
            ),
          ),
        ),
        GoRoute(
          path: '/form',
          builder: (_, _) => SuscripcionFormPage(suscripcionService: service, inicial: inicial),
        ),
      ]),
    );
  }

  Finder campo(String label) => find.widgetWithText(TextFormField, label);

  Future<void> abrir(WidgetTester tester, Widget widget) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(widget);
    await tester.tap(find.text('ABRIR'));
    await tester.pumpAndSettle();
  }

  Future<void> guardar(WidgetTester tester) async {
    await tester.tap(find.text('Guardar suscripción'));
    await tester.pumpAndSettle();
  }

  Future<void> elegirDia(WidgetTester tester, String label, int dia) async {
    await tester.tap(campo(label));
    await tester.pumpAndSettle();
    await tester.tap(find.text('$dia'));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
  }

  testWidgets('valida los campos obligatorios', (tester) async {
    final service = FakeSuscripcionService();
    await abrir(tester, app(service));

    expect(find.text('Agregar suscripción'), findsOneWidget);
    await guardar(tester);
    expect(find.text('Ingresa el nombre del servicio'), findsOneWidget);
    expect(find.text('Ingresa el monto'), findsOneWidget);
    expect(find.text('Elige la fecha del próximo cobro'), findsOneWidget);

    await tester.enterText(campo('Monto (COP)'), '12,345');
    await guardar(tester);
    expect(find.text('Monto no válido (máximo 2 decimales)'), findsOneWidget);
    expect(service.ultimaGuardada, isNull);
  });

  testWidgets('la prueba gratis exige fecha de fin', (tester) async {
    final service = FakeSuscripcionService();
    await abrir(tester, app(service));

    await tester.tap(find.text('Es una prueba gratis'));
    await tester.pumpAndSettle();
    expect(campo('Fin de la prueba'), findsOneWidget);

    await guardar(tester);
    expect(find.text('Elige cuándo termina la prueba'), findsOneWidget);
  });

  testWidgets('crea la suscripción con los datos del formulario', (tester) async {
    final service = FakeSuscripcionService();
    await abrir(tester, app(service));

    await tester.enterText(campo('Servicio'), '  Netflix ');
    await tester.enterText(campo('Monto (COP)'), '38.900');
    await tester.tap(find.text('Anual'));
    await elegirDia(tester, 'Próximo cobro', 15);
    await tester.tap(find.text('7 días'));
    await tester.pump();
    await guardar(tester);

    final s = service.ultimaGuardada!;
    expect(s.nombreServicio, 'Netflix');
    expect(s.monto, 38900);
    expect(s.moneda, 'COP');
    expect(s.frecuencia, Frecuencia.anual);
    expect(s.fechaProximoCobro.day, 15);
    expect(s.esPruebaGratis, isFalse);
    expect(s.diasAviso, 7);

    // Vuelve a la pantalla anterior con la suscripción guardada.
    expect(find.text('GUARDADA Netflix'), findsOneWidget);
  });

  testWidgets('USD acepta decimales con punto', (tester) async {
    final service = FakeSuscripcionService();
    await abrir(tester, app(service));

    await tester.enterText(campo('Servicio'), 'ChatGPT');
    await tester.tap(find.text('USD'));
    await tester.pump();
    await tester.enterText(campo('Monto (USD)'), '19.99');
    await elegirDia(tester, 'Próximo cobro', 20);
    await guardar(tester);

    expect(service.ultimaGuardada!.moneda, 'USD');
    expect(service.ultimaGuardada!.monto, 19.99);
    expect(service.ultimaGuardada!.diasAviso, isNull); // Global
  });

  testWidgets('edita una suscripción existente y muestra errores del servidor', (tester) async {
    final existente = Suscripcion(
      id: 5,
      nombreServicio: 'Spotify',
      monto: 19900,
      frecuencia: Frecuencia.mensual,
      fechaProximoCobro: DateTime(2026, 11, 25),
      diasAviso: 3,
    );
    final service = FakeSuscripcionService(
      iniciales: [existente],
      error: 'El nombre admite máximo 100 caracteres',
    );
    await abrir(tester, app(service, inicial: existente));

    expect(find.text('Editar suscripción'), findsOneWidget);
    expect(find.text('Spotify'), findsOneWidget);
    expect(find.text('19900'), findsOneWidget);
    expect(find.text('25/11/2026'), findsOneWidget);

    await tester.enterText(campo('Monto (COP)'), '21900');
    await guardar(tester);

    expect(service.ultimaGuardada!.id, 5);
    expect(service.ultimaGuardada!.monto, 21900);
    expect(find.text('El nombre admite máximo 100 caracteres'), findsOneWidget);
    expect(find.text('Editar suscripción'), findsOneWidget); // sigue en el formulario
  });
}
