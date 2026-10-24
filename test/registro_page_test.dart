import 'package:flutter/material.dart';
import 'package:flutter_suscripciones/Common/AppTheme.dart';
import 'package:flutter_suscripciones/Pages/RegistroPage.dart';
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
            builder: (_, _) => RegistroPage(authService: authService),
          ),
          GoRoute(path: '/resumen', builder: (_, _) => const Text('RESUMEN')),
        ]),
      );

  Finder campo(int i) => find.byType(TextFormField).at(i);

  Future<void> crearCuenta(WidgetTester tester) async {
    final boton = find.text('Crear cuenta');
    await tester.ensureVisible(boton);
    await tester.tap(boton);
  }

  testWidgets('valida, registra y navega al resumen', (tester) async {
    final auth = FakeAuthService();
    await tester.pumpWidget(app(auth));

    await crearCuenta(tester);
    await tester.pump();
    expect(find.text('Ingresa tu nombre'), findsOneWidget);
    expect(find.text('Ingresa tu correo electrónico'), findsOneWidget);
    expect(find.text('Ingresa tu contraseña'), findsOneWidget);
    expect(find.text('Confirma tu contraseña'), findsOneWidget);

    await tester.enterText(campo(0), 'Ana');
    await tester.enterText(campo(1), 'ana@correo.com');
    await tester.enterText(campo(2), '123456');
    await tester.enterText(campo(3), '654321');
    await crearCuenta(tester);
    await tester.pump();
    expect(find.text('Las contraseñas no coinciden'), findsOneWidget);
    expect(auth.ultimaLlamada, isNull);

    await tester.enterText(campo(3), '123456');
    await crearCuenta(tester);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 3));
    expect(find.text('RESUMEN'), findsOneWidget);
    expect(auth.ultimaLlamada, ['Ana', 'ana@correo.com', '123456']);
  });

  testWidgets('muestra el error si el correo ya existe', (tester) async {
    await tester.pumpWidget(
      app(FakeAuthService(error: 'Ya existe una cuenta con ese correo')),
    );
    await tester.enterText(campo(0), 'Ana');
    await tester.enterText(campo(1), 'ana@correo.com');
    await tester.enterText(campo(2), '123456');
    await tester.enterText(campo(3), '123456');
    await crearCuenta(tester);
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('Ya existe una cuenta con ese correo'), findsOneWidget);
    expect(find.text('RESUMEN'), findsNothing);
  });
}
