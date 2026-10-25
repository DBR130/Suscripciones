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
          GoRoute(
            path: '/preferencias',
            builder: (_, _) => const Scaffold(body: Text('PREFERENCIAS')),
          ),
        ]),
      );

  Finder campo(int i) => find.byType(TextFormField).at(i);

  Future<void> abrir(WidgetTester tester, AuthService auth) async {
    tester.view.physicalSize = const Size(1080, 2600);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(auth));
  }

  Future<void> crearCuenta(WidgetTester tester) async {
    final boton = find.text('Crear cuenta');
    await tester.ensureVisible(boton);
    await tester.tap(boton);
  }

  testWidgets('valida, registra y sigue a la preferencia de avisos', (tester) async {
    final auth = FakeAuthService();
    await abrir(tester, auth);

    expect(find.text('Crea tu cuenta'), findsOneWidget);
    expect(find.text('Con tu correo empezamos a ordenar tus cobros.'), findsOneWidget);
    expect(find.text('¿Ya tienes cuenta? Inicia sesión'), findsOneWidget);

    await crearCuenta(tester);
    await tester.pump();
    expect(find.text('Ingresa tu nombre'), findsOneWidget);
    expect(find.text('Ingresa tu correo electrónico'), findsOneWidget);
    expect(find.text('Ingresa tu contraseña'), findsOneWidget);

    await tester.enterText(campo(0), 'Ana María');
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
    expect(find.text('Creando cuenta…'), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 3));
    expect(find.text('PREFERENCIAS'), findsOneWidget);
    expect(find.text('Hola, Ana'), findsOneWidget);
    expect(auth.ultimaLlamada, ['Ana María', 'ana@correo.com', '123456']);
  });

  testWidgets('muestra en el banner el error si el correo ya existe', (tester) async {
    await abrir(tester, FakeAuthService(error: 'Ya existe una cuenta con ese correo'));
    await tester.enterText(campo(0), 'Ana');
    await tester.enterText(campo(1), 'ana@correo.com');
    await tester.enterText(campo(2), '123456');
    await tester.enterText(campo(3), '123456');
    await crearCuenta(tester);
    await tester.pump(const Duration(seconds: 2));

    expect(find.text('Ya existe una cuenta con ese correo'), findsOneWidget);
    expect(find.text('PREFERENCIAS'), findsNothing);
  });
}
