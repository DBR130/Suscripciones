import 'package:flutter/material.dart';
import 'package:flutter_suscripciones/Common/AppTheme.dart';
import 'package:flutter_suscripciones/Pages/AhorroPage.dart';
import 'package:flutter_suscripciones/Pages/GuiaCancelacionPage.dart';
import 'package:flutter_suscripciones/Pages/SuscripcionDetallePage.dart';
import 'package:flutter_suscripciones/models/ahorro.dart';
import 'package:flutter_suscripciones/models/guia.dart';
import 'package:flutter_suscripciones/models/suscripcion.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'fake_auth_service.dart';
import 'fake_suscripcion_service.dart';

void main() {
  void pantallaAlta(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 3000);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
  }

  Suscripcion netflix({EstadoSuscripcion estado = EstadoSuscripcion.activa}) => Suscripcion(
        id: 7,
        nombreServicio: 'Netflix Estándar',
        monto: 38900,
        frecuencia: Frecuencia.mensual,
        fechaProximoCobro: DateTime(2026, 12, 20),
        estado: estado,
      );

  const guiaNetflix = Guia(
    nombreServicio: 'Netflix',
    pasos: ['Abre netflix.com.', 'Entra a tu cuenta.', 'Cancela la membresía.'],
    enlaceDirecto: 'https://www.netflix.com/cancelplan',
    duracionMinutos: 3,
  );

  group('modelos', () {
    test('Guia lee los pasos y arma el resumen', () {
      final g = GuiaDeSuscripcion.fromJson({
        'suscripcion': {'id': 7, 'nombre_servicio': 'Netflix Estándar'},
        'guia': {
          'nombre_servicio': 'Netflix',
          'pasos': ['a', 'b', 'c', 'd'],
          'enlace_directo': null,
          'duracion_minutos': 3,
          'alias': <String>[],
          'es_generica': false,
        },
        'es_generica': false,
      });
      expect(g.nombreServicio, 'Netflix Estándar');
      expect(g.guia.pasos, ['a', 'b', 'c', 'd']);
      expect(g.guia.resumen, '4 pasos · unos 3 minutos');
      expect(const Guia(nombreServicio: 'X', pasos: ['a']).resumen, '1 paso');
    });

    test('Ahorro lee totales, canceladas y la evolución', () {
      final a = Ahorro.fromJson({
        'totales': [
          {'moneda': 'COP', 'ahorro_anual': 465600, 'ahorro_mensual': 38800, 'cantidad': 2},
        ],
        'cantidad_canceladas': 2,
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
        'evolucion': [
          {
            'moneda': 'COP',
            'meses': [
              {'mes': '2026-09', 'total': 0},
              {'mes': '2026-10', 'total': 58800},
            ],
          },
        ],
      });
      expect(a.totales.single.mensual, 38800);
      expect(a.canceladas.single.fecha, DateTime(2026, 10, 11));
      expect(a.evolucion.single.meses.last.mes, DateTime(2026, 10));
      expect(a.evolucion.single.tieneDatos, isTrue);
    });
  });

  Widget appGuia(FakeSuscripcionService service, {List<Uri>? abiertas}) => MaterialApp.router(
        theme: AppTheme.dark,
        routerConfig: GoRouter(routes: [
          // La guía siempre se abre encima de otra pantalla (el detalle).
          GoRoute(
            path: '/',
            builder: (context, _) => Scaffold(
              body: Column(children: [
                const Text('INICIO'),
                TextButton(onPressed: () => context.push('/guia'), child: const Text('ABRIR GUIA')),
              ]),
            ),
          ),
          GoRoute(
            path: '/guia',
            builder: (_, _) => GuiaCancelacionPage(
              id: 7,
              suscripcionService: service,
              abrirEnlace: (url) async {
                abiertas?.add(url);
                return true;
              },
            ),
          ),
          GoRoute(
            path: '/ahorro',
            builder: (_, s) => AhorroPage(
              suscripcionService: service,
              recienCancelada: s.extra as String?,
            ),
          ),
        ]),
      );

  Future<void> abrirGuia(WidgetTester tester, FakeSuscripcionService service, {List<Uri>? abiertas}) async {
    await tester.pumpWidget(appGuia(service, abiertas: abiertas));
    await tester.tap(find.text('ABRIR GUIA'));
    await tester.pumpAndSettle();
  }

  testWidgets('la guía muestra los pasos, abre el sitio y confirma la cancelación', (tester) async {
    pantallaAlta(tester);
    final abiertas = <Uri>[];
    final service = FakeSuscripcionService(iniciales: [netflix()], guiaFija: guiaNetflix);
    await abrirGuia(tester, service, abiertas: abiertas);

    expect(find.text('Cómo cancelar Netflix Estándar'), findsOneWidget);
    expect(find.text('3 pasos · unos 3 minutos'), findsOneWidget);
    expect(find.text('Entra a tu cuenta.'), findsOneWidget);
    expect(find.text('2'), findsOneWidget); // número del paso
    expect(find.textContaining('No tenemos una guía específica'), findsNothing);
    expect(find.textContaining('El catálogo de guías se actualiza'), findsOneWidget);

    await tester.tap(find.text('Abrir sitio de Netflix'));
    await tester.pump();
    expect(abiertas, [Uri.parse('https://www.netflix.com/cancelplan')]);

    await tester.tap(find.text('Ya cancelé, confirmar'));
    await tester.pumpAndSettle();
    expect(service.suscripciones.single.estado, EstadoSuscripcion.cancelada);
    // Llega a Ahorro con el aviso azul.
    expect(find.text('Ahorro proyectado al año'.toUpperCase()), findsOneWidget);
    expect(
      find.text('Netflix Estándar quedó en canceladas. Sumamos el ahorro proyectado y apagamos sus recordatorios.'),
      findsOneWidget,
    );
  });

  testWidgets('la guía genérica lo dice claramente y no tiene enlace propio', (tester) async {
    pantallaAlta(tester);
    final service = FakeSuscripcionService(iniciales: [netflix()]);
    await abrirGuia(tester, service);

    expect(find.textContaining('No tenemos una guía específica para Netflix Estándar'), findsOneWidget);
    expect(find.textContaining('Abrir sitio de'), findsNothing);

    await tester.tap(find.text('Lo haré después'));
    await tester.pumpAndSettle();
    expect(find.text('INICIO'), findsOneWidget);
    expect(service.suscripciones.single.estado, EstadoSuscripcion.activa);
  });

  testWidgets('Ahorro: totales por moneda, gráfica y canceladas', (tester) async {
    pantallaAlta(tester);
    GastoMes m(int mes, double total) => GastoMes(mes: DateTime(2026, mes), total: total);
    final service = FakeSuscripcionService(
      ahorroFijo: Ahorro(
        totales: const [
          TotalAhorro(moneda: 'COP', anual: 465600, mensual: 38800, cantidad: 2),
          TotalAhorro(moneda: 'USD', anual: 120, mensual: 10, cantidad: 1),
        ],
        canceladas: [
          Cancelada(id: 1, nombreServicio: 'Paramount+', moneda: 'COP', fecha: DateTime(2026, 10, 11), ahorroAnual: 262800),
          Cancelada(id: 2, nombreServicio: 'ChatGPT', moneda: 'USD', fecha: DateTime(2026, 9, 1), ahorroAnual: 120),
        ],
        evolucion: [
          EvolucionMoneda(moneda: 'COP', meses: [m(5, 250000), m(6, 240000), m(7, 0), m(8, 230000), m(9, 220000), m(10, 200000)]),
          EvolucionMoneda(moneda: 'USD', meses: [m(5, 0), m(6, 0), m(7, 0), m(8, 0), m(9, 0), m(10, 0)]),
        ],
      ),
    );
    await tester.pumpWidget(MaterialApp(theme: AppTheme.dark, home: AhorroPage(suscripcionService: service)));
    await tester.pumpAndSettle();

    expect(find.text(r'$465.600'), findsOneWidget);
    expect(find.text(r'+ US$120,00 al año'), findsOneWidget);
    expect(find.text(r'2 suscripciones canceladas · $38.800 + US$10,00 menos al mes'), findsOneWidget);
    expect(find.text('Evolución del gasto mensual'), findsOneWidget);
    // La serie USD sin pagos no se dibuja.
    expect(find.text('Evolución del gasto mensual (USD)'), findsNothing);
    expect(find.byType(GraficaGasto), findsOneWidget);
    for (final mes in ['may', 'jun', 'jul', 'ago', 'sep', 'oct']) {
      expect(find.text(mes), findsOneWidget);
    }
    expect(find.text(r'+$262.800'), findsOneWidget);
    expect(find.text('Cancelada el 11 oct'), findsOneWidget);
    expect(find.text(r'+US$120,00'), findsOneWidget);
  });

  testWidgets('Ahorro vacío', (tester) async {
    pantallaAlta(tester);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark,
      home: AhorroPage(suscripcionService: FakeSuscripcionService()),
    ));
    await tester.pumpAndSettle();
    expect(find.text(r'$0'), findsOneWidget);
    expect(find.text('Aún no has cancelado suscripciones'), findsOneWidget);
  });

  Widget appDetalle(FakeSuscripcionService service) => MaterialApp.router(
        theme: AppTheme.dark,
        routerConfig: GoRouter(routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => SuscripcionDetallePage(
              id: 7,
              authService: FakeAuthService(),
              suscripcionService: service,
            ),
          ),
          GoRoute(path: '/suscripcion/:id/cancelar', builder: (_, s) => Text('GUIA ${s.pathParameters['id']}')),
        ]),
      );

  testWidgets('"Cancelar esta suscripción" abre la guía', (tester) async {
    pantallaAlta(tester);
    await tester.pumpWidget(appDetalle(FakeSuscripcionService(iniciales: [netflix()])));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar esta suscripción'));
    await tester.pumpAndSettle();
    expect(find.text('GUIA 7'), findsOneWidget);
  });

  testWidgets('una cancelada se reactiva con confirmación', (tester) async {
    pantallaAlta(tester);
    final service = FakeSuscripcionService(iniciales: [netflix(estado: EstadoSuscripcion.cancelada)]);
    await tester.pumpWidget(appDetalle(service));
    await tester.pumpAndSettle();

    expect(find.text('Esta suscripción está cancelada.'), findsOneWidget);
    expect(find.text('Cancelar esta suscripción'), findsNothing);
    await tester.tap(find.text('Reactivar suscripción'));
    await tester.pumpAndSettle();
    expect(find.text('¿Reactivar Netflix Estándar?'), findsOneWidget);

    await tester.tap(find.text('No, volver'));
    await tester.pumpAndSettle();
    expect(service.suscripciones.single.estado, EstadoSuscripcion.cancelada);

    await tester.tap(find.text('Reactivar suscripción'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Reactivar suscripción'));
    await tester.pumpAndSettle();
    expect(service.suscripciones.single.estado, EstadoSuscripcion.activa);
    expect(find.text('Cancelar esta suscripción'), findsOneWidget);
  });
}
