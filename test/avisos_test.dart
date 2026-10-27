import 'package:flutter/material.dart';
import 'package:flutter_suscripciones/Common/AppTheme.dart';
import 'package:flutter_suscripciones/Pages/AvisosPage.dart';
import 'package:flutter_suscripciones/Pages/DashboardPage.dart';
import 'package:flutter_suscripciones/Pages/PreferenciasPage.dart';
import 'package:flutter_suscripciones/Pages/SuscripcionDetallePage.dart';
import 'package:flutter_suscripciones/models/aviso.dart';
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

  final hoy = DateUtils.dateOnly(DateTime.now());

  group('Aviso (textos)', () {
    Aviso aviso(TipoAviso tipo, {int dias = 3, double? anterior}) => Aviso(
          tipo: tipo,
          suscripcionId: 1,
          nombreServicio: 'Netflix',
          monto: 38900,
          moneda: 'COP',
          frecuencia: Frecuencia.mensual,
          fecha: DateTime(2026, 9, 20),
          fechaAviso: DateTime(2026, 9, 17),
          diasRestantes: dias,
          montoAnterior: anterior,
        );

    test('próximo cobro, fin de prueba y cambio de precio', () {
      final cobro = aviso(TipoAviso.proximoCobro);
      expect(cobro.titulo, 'Netflix se cobra en 3 días');
      expect(cobro.cuerpo, r'$38.900 el 20 de septiembre.');

      expect(aviso(TipoAviso.proximoCobro, dias: 1).titulo, 'Netflix se cobra mañana');

      final prueba = aviso(TipoAviso.finPrueba, dias: 2);
      expect(prueba.titulo, 'Tu prueba de Netflix termina en 2 días');
      expect(prueba.cuerpo, r'El 20 de septiembre pasa a $38.900/mes.');

      final precio = aviso(TipoAviso.cambioPrecio, anterior: 35900);
      expect(precio.titulo, 'Netflix subió de precio');
      expect(precio.cuerpo, r'De $35.900 a $38.900/mes.');
      expect(aviso(TipoAviso.cambioPrecio, anterior: 45900).titulo, 'Netflix bajó de precio');
    });

    test('fecha relativa: hoy, ayer o "14 sep"', () {
      final h = DateTime(2026, 9, 17);
      expect(fechaRelativa(h, h), 'hoy');
      expect(fechaRelativa(DateTime(2026, 9, 16), h), 'ayer');
      expect(fechaRelativa(DateTime(2026, 9, 14), h), '14 sep');
    });
  });

  testWidgets('la pestaña Avisos muestra los avisos y abre el detalle', (tester) async {
    pantallaAlta(tester);
    final service = FakeSuscripcionService(listaAvisos: [
      Aviso(
        tipo: TipoAviso.proximoCobro,
        suscripcionId: 7,
        nombreServicio: 'Netflix',
        monto: 38900,
        moneda: 'COP',
        frecuencia: Frecuencia.mensual,
        fecha: hoy.add(const Duration(days: 3)),
        fechaAviso: hoy,
        diasRestantes: 3,
      ),
    ]);
    await tester.pumpWidget(MaterialApp.router(
      theme: AppTheme.dark,
      routerConfig: GoRouter(routes: [
        GoRoute(path: '/', builder: (_, _) => AvisosPage(suscripcionService: service)),
        GoRoute(path: '/suscripcion/:id', builder: (_, s) => Text('DETALLE ${s.pathParameters['id']}')),
      ]),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Avisos'), findsOneWidget);
    expect(find.text('Recordatorios enviados · 3 días antes de cada cobro'), findsOneWidget);
    expect(find.text('PRÓXIMO COBRO'), findsOneWidget);
    expect(find.text('hoy'), findsOneWidget);
    expect(find.text('Netflix se cobra en 3 días'), findsOneWidget);

    await tester.tap(find.text('Netflix se cobra en 3 días'));
    await tester.pumpAndSettle();
    expect(find.text('DETALLE 7'), findsOneWidget);
  });

  testWidgets('Avisos vacío', (tester) async {
    pantallaAlta(tester);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark,
      home: AvisosPage(suscripcionService: FakeSuscripcionService()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('No tienes avisos por ahora'), findsOneWidget);
  });

  testWidgets('el detalle muestra el cambio de precio', (tester) async {
    pantallaAlta(tester);
    final service = FakeSuscripcionService(
      iniciales: [
        Suscripcion(
          id: 7,
          nombreServicio: 'Adobe',
          monto: 47900,
          frecuencia: Frecuencia.mensual,
          fechaProximoCobro: DateTime(2026, 12, 2),
        ),
      ],
      cambioPrecio: CambioPrecio(anterior: 41900, nuevo: 47900, fecha: DateTime(2026, 10, 3)),
    );
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark,
      home: SuscripcionDetallePage(id: 7, authService: FakeAuthService(), suscripcionService: service),
    ));
    await tester.pumpAndSettle();
    expect(find.text(r'El precio subió de $41.900 a $47.900 el 3 oct'), findsOneWidget);
  });

  testWidgets('pantalla 06: elige los días y va al dashboard', (tester) async {
    pantallaAlta(tester);
    final auth = FakeAuthService();
    await tester.pumpWidget(MaterialApp.router(
      theme: AppTheme.dark,
      routerConfig: GoRouter(routes: [
        GoRoute(path: '/', builder: (_, _) => PreferenciasPage(authService: auth)),
        GoRoute(path: '/resumen', builder: (_, _) => const Text('DASHBOARD')),
      ]),
    ));

    expect(find.text('¿Cuántos días antes te avisamos?'), findsOneWidget);
    expect(find.text('Recomendado: alcanzas a cancelar'), findsOneWidget);
    expect(find.text('Resumen mensual'), findsOneWidget);

    await tester.tap(find.text('7 días antes'));
    await tester.pump();
    await tester.tap(find.text('Ir a mi dashboard'));
    await tester.pumpAndSettle();

    expect(auth.dias, 7);
    expect(find.text('DASHBOARD'), findsOneWidget);
  });

  group('"por cobrar" de los próximos 7 días', () {
    Suscripcion sus(double monto, int diasCobro, {String moneda = 'COP', int? diasFinPrueba}) => Suscripcion(
          id: 1,
          nombreServicio: 'X',
          monto: monto,
          moneda: moneda,
          frecuencia: Frecuencia.mensual,
          fechaProximoCobro: hoy.add(Duration(days: diasCobro)),
          esPruebaGratis: diasFinPrueba != null,
          fechaFinPrueba: diasFinPrueba == null ? null : hoy.add(Duration(days: diasFinPrueba)),
        );

    test('incluye pruebas gratis cuyo primer cobro cae en el rango, por moneda', () {
      final texto = porCobrar([
        sus(26900, 1),
        sus(89900, 3, diasFinPrueba: 3), // primer cobro en 3 días: suma
        sus(50000, 6, diasFinPrueba: 2), // termina en 2, cobra en 6: suma
        sus(15000, 10, diasFinPrueba: 5), // primer cobro fuera del rango
        sus(20, 4, moneda: 'USD'),
        sus(99999, 8), // fuera del rango
      ], hoy);
      expect(texto, r'$166.800 + US$20,00 por cobrar');
    });

    test('sin cobros en el rango queda vacío', () {
      expect(porCobrar([sus(1000, 30)], hoy), '');
    });
  });
}
