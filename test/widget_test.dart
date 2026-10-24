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
          GoRoute(path: '/resumen', builder: (_, _) => const Text('RESUMEN')),
        ]),
      );

  testWidgets('valida y navega al resumen', (tester) async {
    final auth = FakeAuthService();
    await tester.pumpWidget(app(auth));
    await tester.tap(find.text('Iniciar sesión'));
    await tester.pump();
    expect(find.text('Ingresa tu correo electrónico'), findsOneWidget);
    expect(find.text('Ingresa tu contraseña'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).at(0), 'mal');
    await tester.enterText(find.byType(TextFormField).at(1), '123');
    await tester.tap(find.text('Iniciar sesión'));
    await tester.pump();
    expect(find.text('Correo no válido'), findsOneWidget);
    expect(find.text('Mínimo 6 caracteres'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).at(0), 'a@b.co');
    await tester.enterText(find.byType(TextFormField).at(1), '123456');
    await tester.tap(find.text('Iniciar sesión'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 3));
    expect(find.text('RESUMEN'), findsOneWidget);
    expect(auth.ultimaLlamada, ['a@b.co', '123456']);
  });

  testWidgets('muestra el error del servidor en un SnackBar', (tester) async {
    await tester.pumpWidget(
      app(FakeAuthService(error: 'Correo o contraseña incorrectos')),
    );
    await tester.enterText(find.byType(TextFormField).at(0), 'a@b.co');
    await tester.enterText(find.byType(TextFormField).at(1), '123456');
    await tester.tap(find.text('Iniciar sesión'));
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('Correo o contraseña incorrectos'), findsOneWidget);
    expect(find.text('RESUMEN'), findsNothing);
    // El botón vuelve a estar disponible para reintentar.
    expect(find.text('Iniciar sesión'), findsOneWidget);
  });
}
