import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../Pages/HomePage.dart';
import '../Pages/LoginPage.dart';

/// Rutas de la aplicación con go_router.
/// Para agregar una vista nueva: crear la constante y registrar su GoRoute.
class Routers {
  Routers._();

  static const String home = '/';
  static const String login = '/login';

  static final GoRouter router = GoRouter(
    initialLocation: home,
    routes: [
      GoRoute(
        path: home,
        builder: (context, state) => const HomePage(),
      ),
      GoRoute(
        path: login,
        builder: (context, state) => const LoginPage(),
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
