import 'package:flutter/material.dart';
import 'package:flutter_suscripciones/Common/AppTheme.dart';
import 'package:flutter_suscripciones/Pages/LoginPage.dart';
import 'package:flutter_suscripciones/services/auth_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'fake_auth_service.dart';

void main() {
  Widget app(AuthService authService) => MaterialApp.router(
        theme: AppTheme.dark,
        routerConfig: GoRouter(routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => LoginPage(authService: authService),
          ),
          GoRoute(
            path: '/resumen',
            builder: (_, _) => const Scaffold(body: Text('RESUMEN')),
          ),
        ]),
      );

  testWidgets('pantalla 02: textos, validación y entra al resumen', (tester) async {
    final auth = FakeAuthService();
    await tester.pumpWidget(app(auth));

    expect(find.text('Hola de nuevo'), findsOneWidget);
    expect(find.text('Entra para ver tus próximos cobros.'), findsOneWidget);
    expect(find.text('No tengo cuenta, quiero registrarme'), findsOneWidget);
    expect(find.textContaining('Habeas Data'), findsOneWidget);

    await tester.tap(find.text('Entrar'));
    await tester.pump();
    expect(find.text('Ingresa tu correo electrónico'), findsOneWidget);
    expect(find.text('Ingresa tu contraseña'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).at(0), 'mal');
    await tester.enterText(find.byType(TextFormField).at(1), '123');
    await tester.tap(find.text('Entrar'));
    await tester.pump();
    expect(find.text('Correo no válido'), findsOneWidget);
    expect(find.text('Mínimo 6 caracteres'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).at(0), 'a@b.co');
    await tester.enterText(find.byType(TextFormField).at(1), '123456');
    await tester.tap(find.text('Entrar'));
    await tester.pump();
    // Estado de carga: botón deshabilitado con spinner y "Entrando…".
    expect(find.text('Entrando…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpAndSettle(const Duration(seconds: 3));
    expect(find.text('RESUMEN'), findsOneWidget);
    expect(find.text('Hola, Ana'), findsOneWidget); // toast con el primer nombre
    expect(auth.ultimaLlamada, ['a@b.co', '123456']);
  });

  testWidgets('el error del servidor aparece en el banner rojo', (tester) async {
    await tester.pumpWidget(
      app(FakeAuthService(error: 'Correo o contraseña incorrectos')),
    );
    await tester.enterText(find.byType(TextFormField).at(0), 'a@b.co');
    await tester.enterText(find.byType(TextFormField).at(1), '123456');
    await tester.tap(find.text('Entrar'));
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('Correo o contraseña incorrectos'), findsOneWidget);
    expect(find.byIcon(Icons.info_outline), findsOneWidget); // ícono del banner
    expect(find.text('RESUMEN'), findsNothing);
    // El botón vuelve a estar disponible para reintentar.
    expect(find.text('Entrar'), findsOneWidget);

    // Al reintentar, el banner se quita mientras valida.
    await tester.tap(find.text('Entrar'));
    await tester.pump();
    expect(find.text('Correo o contraseña incorrectos'), findsNothing);
    await tester.pumpAndSettle(const Duration(seconds: 2));
  });
}
