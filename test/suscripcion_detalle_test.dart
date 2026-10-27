import 'package:flutter/material.dart';
import 'package:flutter_suscripciones/Common/AppTheme.dart';
import 'package:flutter_suscripciones/Pages/SuscripcionDetallePage.dart';
import 'package:flutter_suscripciones/models/suscripcion.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'fake_auth_service.dart';
import 'fake_suscripcion_service.dart';

void main() {
  final netflix = Suscripcion(
    id: 7,
    nombreServicio: 'Netflix',
    categoria: 'Streaming',
    monto: 38900,
    frecuencia: Frecuencia.mensual,
    fechaProximoCobro: DateTime(2026, 11, 20),
    creadoEn: DateTime(2024, 3, 20),
  );

  Widget app(FakeSuscripcionService service) => MaterialApp.router(
        theme: AppTheme.dark,
        routerConfig: GoRouter(initialLocation: '/detalle', routes: [
          GoRoute(path: '/', builder: (_, _) => const Text('INICIO')),
          GoRoute(
            path: '/detalle',
            builder: (_, _) => SuscripcionDetallePage(
              id: 7,
              authService: FakeAuthService(dias: 3),
              suscripcionService: service,
            ),
          ),
        ]),
      );

  Future<void> abrir(WidgetTester tester, FakeSuscripcionService service) async {
    tester.view.physicalSize = const Size(1080, 3200);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(service));
    await tester.pumpAndSettle();
  }

  testWidgets('muestra los datos, la categoría y el historial', (tester) async {
    final service = FakeSuscripcionService(
      iniciales: [netflix],
      pagos: [
        Pago(fecha: DateTime(2026, 10, 20), monto: 38900),
        Pago(fecha: DateTime(2026, 9, 20), monto: 38900),
      ],
    );
    await abrir(tester, service);

    expect(find.text('Netflix'), findsOneWidget);
    expect(find.text('Streaming'), findsOneWidget);
    expect(find.text('Editar'), findsOneWidget);
    expect(find.text('20 nov 2026'), findsOneWidget); // próximo cobro
    expect(find.text('mar 2024'), findsOneWidget); // desde
    expect(find.text(r'$77.800'), findsOneWidget); // pagado en total
    expect(find.text('20 oct'), findsOneWidget);
    expect(find.text('Registro manual'), findsOneWidget); // origen
  });

  testWidgets('sin pagos y con recordatorio propio', (tester) async {
    final service = FakeSuscripcionService(iniciales: [netflix]);
    await abrir(tester, service);

    expect(find.text('Sin pagos registrados aún'), findsOneWidget);

    await tester.tap(find.text('7 días'));
    await tester.pumpAndSettle();
    expect(service.ultimaGuardada!.diasAviso, 7);
  });

  testWidgets('marcar "quiero cancelar" muestra el aviso ámbar', (tester) async {
    final service = FakeSuscripcionService(iniciales: [netflix]);
    await abrir(tester, service);

    await tester.tap(find.text('Marcar como "quiero cancelar"'));
    await tester.pumpAndSettle();

    expect(find.text('Tú marcaste esta suscripción para cancelar.'), findsOneWidget);
    expect(find.text('Quitar marca de "quiero cancelar"'), findsOneWidget);
    expect(service.suscripciones.single.estado, EstadoSuscripcion.marcadaParaCancelar);
  });
}
