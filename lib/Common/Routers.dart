import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../Pages/DashboardPage.dart';
import '../Pages/HomePage.dart';
import '../Pages/LoginPage.dart';
import '../Pages/PerfilPage.dart';
import '../Pages/RegistroPage.dart';
import '../Pages/SuscripcionDetallePage.dart';
import '../Pages/SuscripcionFormPage.dart';
import '../models/suscripcion.dart';
import '../services/auth_service.dart';
import '../services/suscripcion_service.dart';

/// Rutas de la aplicación con go_router.
/// Para agregar una vista nueva: crear la constante y registrar su GoRoute.
class Routers {
  Routers._();

  static const String home = '/';
  static const String login = '/login';
  static const String registro = '/registro';
  static const String dashboard = '/resumen';
  static const String perfil = '/perfil';
  static const String nuevaSuscripcion = '/suscripciones/nueva';

  static String detalle(int id) => '/suscripciones/$id';
  static String editarSuscripcion(int id) => '/suscripciones/$id/editar';

  /// Crea el router. [initialLocation] permite abrir directo en el resumen
  /// cuando ya hay una sesión guardada (ver main.dart).
  static GoRouter crear(
    AuthService authService,
    SuscripcionService suscripcionService, {
    String initialLocation = home,
  }) {
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
          builder: (context, state) => DashboardPage(
            authService: authService,
            suscripcionService: suscripcionService,
          ),
        ),
        GoRoute(
          path: perfil,
          builder: (context, state) => PerfilPage(authService: authService),
        ),
        // "nueva" va antes de ":id" para que no se confunda con un id.
        GoRoute(
          path: nuevaSuscripcion,
          builder: (context, state) =>
              SuscripcionFormPage(suscripcionService: suscripcionService),
        ),
        GoRoute(
          path: '/suscripciones/:id',
          builder: (context, state) => SuscripcionDetallePage(
            id: int.tryParse(state.pathParameters['id']!) ?? 0,
            suscripcionService: suscripcionService,
          ),
          routes: [
            // La suscripción a editar llega en "extra" desde el detalle.
            // Si no viene (por ejemplo, tras reiniciar la app), se muestra
            // el detalle, que la vuelve a cargar.
            GoRoute(
              path: 'editar',
              builder: (context, state) {
                final suscripcion = state.extra;
                if (suscripcion is Suscripcion) {
                  return SuscripcionFormPage(
                    suscripcionService: suscripcionService,
                    inicial: suscripcion,
                  );
                }
                return SuscripcionDetallePage(
                  id: int.tryParse(state.pathParameters['id']!) ?? 0,
                  suscripcionService: suscripcionService,
                );
              },
            ),
          ],
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
