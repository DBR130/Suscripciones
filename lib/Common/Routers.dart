import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../Pages/DashboardPage.dart';
import '../Pages/HomePage.dart';
import '../Pages/LoginPage.dart';
import '../Pages/PerfilPage.dart';
import '../Pages/RegistroPage.dart';
import '../Pages/SuscripcionDetallePage.dart';
import '../Pages/SuscripcionFormPage.dart';
import '../Pages/SuscripcionesPage.dart';
import '../models/suscripcion.dart';
import '../services/auth_service.dart';
import '../services/suscripcion_service.dart';
import '../widgets/app_shell.dart';

/// Rutas de la aplicación con go_router (ver "Navegación" en
/// design/subtrack-pantallas.md).
/// Para agregar una vista nueva: crear la constante y registrar su GoRoute.
class Routers {
  Routers._();

  static const String home = '/';
  static const String login = '/login';
  static const String registro = '/registro';

  // Con barra de pestañas.
  static const String dashboard = '/resumen';
  static const String suscripciones = '/suscripciones';
  static const String perfil = '/perfil';
  static String detalle(int id) => '/suscripcion/$id';

  // Sin barra de pestañas.
  static const String nuevaSuscripcion = '/suscripcion/nueva';
  static String editarSuscripcion(int id) => '/suscripcion/$id/editar';

  static int _id(GoRouterState state) => int.tryParse(state.pathParameters['id']!) ?? 0;

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
        // El formulario va fuera del shell (sin pestañas). Estas dos rutas
        // van antes que '/suscripcion/:id' para que "nueva" no se lea como id.
        GoRoute(
          path: nuevaSuscripcion,
          builder: (context, state) =>
              SuscripcionFormPage(suscripcionService: suscripcionService),
        ),
        GoRoute(
          path: '/suscripcion/:id/editar',
          builder: (context, state) {
            // La suscripción llega en "extra" desde el detalle. Si no viene
            // (por ejemplo, tras reiniciar la app), se muestra el detalle.
            final suscripcion = state.extra;
            if (suscripcion is Suscripcion) {
              return SuscripcionFormPage(
                suscripcionService: suscripcionService,
                inicial: suscripcion,
              );
            }
            return SuscripcionDetallePage(
              id: _id(state),
              authService: authService,
              suscripcionService: suscripcionService,
            );
          },
        ),
        ShellRoute(
          builder: (context, state, child) => AppShell(child: child),
          routes: [
            GoRoute(
              path: dashboard,
              builder: (context, state) => DashboardPage(
                authService: authService,
                suscripcionService: suscripcionService,
              ),
            ),
            GoRoute(
              path: suscripciones,
              builder: (context, state) => SuscripcionesPage(
                authService: authService,
                suscripcionService: suscripcionService,
              ),
            ),
            GoRoute(
              path: perfil,
              builder: (context, state) => PerfilPage(authService: authService),
            ),
            GoRoute(
              path: '/suscripcion/:id',
              builder: (context, state) => SuscripcionDetallePage(
                id: _id(state),
                authService: authService,
                suscripcionService: suscripcionService,
              ),
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
