import 'package:flutter/material.dart';
import 'package:flutter_suscripciones/Common/AppTheme.dart';
import 'package:flutter_suscripciones/Pages/LoginPage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  Widget app() => MaterialApp.router(
        theme: AppTheme.dark,
        routerConfig: GoRouter(routes: [
          GoRoute(path: '/', builder: (_, _) => const LoginPage()),
          GoRoute(path: '/resumen', builder: (_, _) => const Text('RESUMEN')),
        ]),
      );

  testWidgets('valida y navega al resumen', (tester) async {
    await tester.pumpWidget(app());
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
  });
}
