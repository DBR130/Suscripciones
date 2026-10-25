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
        GoRoute(
          path: '/resumen',
          builder: (_, _) => const Scaffold(body: Text('DASHBOARD')),
        ),
      ]),
    );
  }

  // Las etiquetas van fuera del campo, así que se busca por el texto de ayuda.
  final servicio = find.widgetWithText(TextFormField, 'ej. HBO Max');
  Finder monto(String moneda) =>
      find.widgetWithText(TextFormField, moneda == 'COP' ? '24900' : '9.99');
  Finder fecha(int i) => find.widgetWithText(TextFormField, 'Elige una fecha').at(i);

  Future<void> abrir(WidgetTester tester, Widget widget) async {
    tester.view.physicalSize = const Size(1080, 2600);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(widget);
    await tester.tap(find.text('ABRIR'));
    await tester.pumpAndSettle();
  }

  Future<void> tocar(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> guardar(WidgetTester tester, {bool editando = false}) =>
      tocar(tester, find.text(editando ? 'Guardar cambios' : 'Guardar suscripción'));

  Future<void> elegirDia(WidgetTester tester, Finder campo, int dia) async {
    await tocar(tester, campo);
    await tester.tap(find.text('$dia'));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
  }

  testWidgets('valida los campos obligatorios', (tester) async {
    final service = FakeSuscripcionService();
    await abrir(tester, app(service));

    expect(find.text('Agregar suscripción'), findsOneWidget);
    expect(find.text('SERVICIO'), findsOneWidget); // etiqueta arriba, en mayúsculas
    expect(find.text('Eliminar suscripción'), findsNothing);
    await guardar(tester);
    expect(find.text('Ingresa el nombre del servicio'), findsOneWidget);
    expect(find.text('Ingresa un monto mayor a 0'), findsOneWidget);
    expect(find.text('Elige la fecha del próximo cobro'), findsOneWidget);

    await tester.enterText(monto('COP'), '0');
    await guardar(tester);
    expect(find.text('Ingresa un monto mayor a 0'), findsOneWidget);

    await tester.enterText(monto('COP'), '12,345');
    await guardar(tester);
    expect(find.text('Monto no válido (máximo 2 decimales)'), findsOneWidget);
    expect(service.ultimaGuardada, isNull);
  });

  testWidgets('la prueba gratis cambia la etiqueta y exige fecha de fin', (tester) async {
    final service = FakeSuscripcionService();
    await abrir(tester, app(service));

    expect(find.text('PRÓXIMO COBRO'), findsOneWidget);
    await tocar(tester, find.text('Es una prueba gratis'));
    expect(find.text('PRIMER COBRO (AL TERMINAR LA PRUEBA)'), findsOneWidget);
    expect(find.text('FIN DE LA PRUEBA'), findsOneWidget);

    await guardar(tester);
    expect(find.text('Elige cuándo termina la prueba'), findsOneWidget);
  });

  testWidgets('crea la suscripción con categoría', (tester) async {
    final service = FakeSuscripcionService();
    await abrir(tester, app(service));

    await tester.enterText(servicio, '  Netflix ');
    await tocar(tester, find.text('Streaming'));
    await tester.enterText(monto('COP'), '38.900');
    await tocar(tester, find.text('Anual'));
    await elegirDia(tester, fecha(0), 15);
    await guardar(tester);

    final s = service.ultimaGuardada!;
    expect(s.nombreServicio, 'Netflix');
    expect(s.categoria, 'Streaming');
    expect(s.monto, 38900);
    expect(s.moneda, 'COP');
    expect(s.frecuencia, Frecuencia.anual);
    expect(s.fechaProximoCobro.day, 15);
    expect(s.esPruebaGratis, isFalse);
    expect(s.diasAviso, isNull);

    // Vuelve a la pantalla anterior con la suscripción guardada.
    expect(find.text('GUARDADA Netflix'), findsOneWidget);
  });

  testWidgets('USD acepta decimales con punto y sin categoría', (tester) async {
    final service = FakeSuscripcionService();
    await abrir(tester, app(service));

    await tester.enterText(servicio, 'ChatGPT');
    await tocar(tester, find.text('USD'));
    await tester.enterText(monto('USD'), '19.99');
    await elegirDia(tester, fecha(0), 20);
    await guardar(tester);

    expect(service.ultimaGuardada!.moneda, 'USD');
    expect(service.ultimaGuardada!.monto, 19.99);
    expect(service.ultimaGuardada!.categoria, isNull);
  });

  final spotify = Suscripcion(
    id: 5,
    nombreServicio: 'Spotify',
    categoria: 'Música',
    monto: 19900,
    frecuencia: Frecuencia.mensual,
    fechaProximoCobro: DateTime(2026, 11, 25),
    diasAviso: 7,
  );

  testWidgets('edita conservando los días de aviso y muestra el error del servidor', (tester) async {
    final service = FakeSuscripcionService(
      iniciales: [spotify],
      error: 'El nombre admite máximo 100 caracteres',
    );
    await abrir(tester, app(service, inicial: spotify));

    expect(find.text('Editar suscripción'), findsOneWidget);
    expect(find.text('Spotify'), findsOneWidget);
    expect(find.text('19900'), findsOneWidget);
    expect(find.text('25 nov 2026'), findsOneWidget);

    await tester.enterText(monto('COP'), '21900');
    await tocar(tester, find.text('Sin categoría'));
    await guardar(tester, editando: true);

    final s = service.ultimaGuardada!;
    expect(s.id, 5);
    expect(s.monto, 21900);
    expect(s.categoria, isNull);
    expect(s.diasAviso, 7);
    // El error aparece en el banner y sigue en el formulario.
    expect(find.text('El nombre admite máximo 100 caracteres'), findsOneWidget);
    expect(find.text('Editar suscripción'), findsOneWidget);
  });

  testWidgets('eliminar pide confirmación y va al dashboard', (tester) async {
    final service = FakeSuscripcionService(iniciales: [spotify]);
    await abrir(tester, app(service, inicial: spotify));

    await tocar(tester, find.text('Eliminar suscripción'));
    expect(find.text('¿Eliminar Spotify?'), findsOneWidget);
    await tocar(tester, find.text('No, volver'));
    expect(service.eliminadas, isEmpty);

    await tocar(tester, find.text('Eliminar suscripción'));
    // El botón de la hoja también dice "Eliminar suscripción".
    await tocar(tester, find.widgetWithText(FilledButton, 'Eliminar suscripción'));
    expect(service.eliminadas, [5]);
    expect(find.text('DASHBOARD'), findsOneWidget);
    expect(find.text('Spotify se eliminó de tu lista'), findsOneWidget);
  });
}
