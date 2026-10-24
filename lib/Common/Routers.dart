import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../Pages/DashboardPage.dart';
import '../Pages/HomePage.dart';
import '../Pages/LoginPage.dart';
import '../Pages/RegistroPage.dart';
import '../services/auth_service.dart';

/// Rutas de la aplicación con go_router.
/// Para agregar una vista nueva: crear la constante y registrar su GoRoute.
class Routers {
  Routers._();

  static const String home = '/';
  static const String login = '/login';
  static const String registro = '/registro';
  static const String dashboard = '/resumen';

  /// Crea el router. [initialLocation] permite abrir directo en el resumen
  /// cuando ya hay una sesión guardada (ver main.dart).
  static GoRouter crear(AuthService authService, {String initialLocation = home}) {
    return GoRouter(
      initialLocation: initialLocation,
      routes: [
        GoRoute(
          path: home,
          builder: (context, state) => const HomePage(),
        ),
        GoRoute(
          path: login,
          builder: (context, state) => LoginPage(authService: authService),
        ),
        GoRoute(
          path: registro,
          builder: (context, state) => RegistroPage(authService: authService),
        ),
        GoRoute(
          path: dashboard,
          builder: (context, state) => DashboardPage(authService: authService),
        ),
      ],
      // Se muestra cuando se navega a una ruta que no existe.
      errorBuilder: (context, state) => Scaffold(
        appBar: AppBar(title: const Text('Error')),
        body: Center(
          child: Text('No existe la ruta: ${state.uri}'),
        ),
      ),
    );
  }
}
