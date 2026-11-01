import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../Pages/AhorroPage.dart';
import '../deteccion/depuracion_deteccion_page.dart';
import '../deteccion/deteccion_service.dart';
import '../deteccion/escaneo_page.dart';
import '../deteccion/lector_notificaciones.dart';
import '../deteccion/permisos_page.dart';
import '../deteccion/procesador_detecciones.dart';
import '../deteccion/resultados_deteccion_page.dart';
import '../services/api_client.dart';
import '../Pages/AvisosPage.dart';
import '../Pages/BienvenidaPage.dart';
import '../Pages/DashboardPage.dart';
import '../Pages/GuiaCancelacionPage.dart';
import '../Pages/LoginPage.dart';
import '../Pages/PerfilPage.dart';
import '../Pages/PreferenciasPage.dart';
import '../Pages/RegistroPage.dart';
import '../Pages/SuscripcionDetallePage.dart';
import '../Pages/SuscripcionFormPage.dart';
import '../Pages/SuscripcionesPage.dart';
import '../models/suscripcion.dart';
import '../services/auth_service.dart';
import '../services/recordatorios_service.dart';
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
  static const String avisos = '/avisos';
  static const String perfil = '/perfil';
  static const String ahorro = '/ahorro';
  static String detalle(int id) => '/suscripcion/$id';

  // Sin barra de pestañas.
  static const String preferencias = '/preferencias';
  static const String depuracionDeteccion = '/depuracion/deteccion';

  // Detección automática (pantallas 03, 04 y 05). "?inicio=1" = vienen del
  // registro: al terminar sigue la preferencia de recordatorio (06).
  static const String permisos = '/permisos';
  static const String escaneo = '/escaneo';
  static const String deteccion = '/deteccion';
  static String rutaPermisos({bool inicio = false}) => inicio ? '$permisos?inicio=1' : permisos;
  static String rutaEscaneo({bool inicio = false}) => inicio ? '$escaneo?inicio=1' : escaneo;
  static String rutaDeteccion({bool inicio = false}) => inicio ? '$deteccion?inicio=1' : deteccion;
  static bool _inicio(GoRouterState state) => state.uri.queryParameters['inicio'] == '1';
  static const String nuevaSuscripcion = '/suscripcion/nueva';
  static String editarSuscripcion(int id) => '/suscripcion/$id/editar';
  static String cancelar(int id) => '/suscripcion/$id/cancelar';

  static int _id(GoRouterState state) => int.tryParse(state.pathParameters['id']!) ?? 0;

  /// Crea el router. [initialLocation] permite abrir directo en el resumen
  /// cuando ya hay una sesión guardada (ver main.dart). [depuracion] agrega
  /// la pantalla de depuración de la detección: por defecto solo en debug, así
  /// en release la ruta no existe y el compilador elimina la pantalla.
  static GoRouter crear(
    AuthService authService,
    SuscripcionService suscripcionService, {
    RecordatoriosService? recordatorios,
    LectorNotificaciones? lector,
    DeteccionService? deteccionService,
    ProcesadorDetecciones? procesador,
    String initialLocation = home,
    bool depuracion = kDebugMode,
  }) {
    final lectorNotificaciones = lector ?? LectorNotificaciones();
    final servicioDeteccion = deteccionService ?? DeteccionService(ApiClient());
    final procesadorDetecciones = procesador ??
        ProcesadorDetecciones(
          lector: lectorNotificaciones,
          servicio: servicioDeteccion,
          cargarCatalogo: suscripcionService.catalogoServicios,
        );
    return GoRouter(
      initialLocation: initialLocation,
      routes: [
        // Login y registro son hijas de la bienvenida: aunque se llegue con
        // context.go (por ejemplo, al cerrar sesión), quedan encima de ella y
        // el botón "atrás" de Android vuelve a la bienvenida en vez de cerrar
        // la app.
        GoRoute(
          path: home,
          builder: (context, state) => const BienvenidaPage(),
          routes: [
            GoRoute(
              path: 'login',
              builder: (context, state) => LoginPage(authService: authService),
            ),
            GoRoute(
              path: 'registro',
              builder: (context, state) => RegistroPage(authService: authService),
            ),
          ],
        ),
        // Solo en debug: en release esta ruta no se registra.
        if (depuracion)
          GoRoute(
            path: depuracionDeteccion,
            builder: (context, state) => DepuracionDeteccionPage(
              lector: lectorNotificaciones,
              recordatorios: recordatorios,
              cargarCatalogo: suscripcionService.catalogoServicios,
            ),
          ),
        GoRoute(
          path: permisos,
          builder: (context, state) => PermisosPage(
            lector: lectorNotificaciones,
            recordatorios: recordatorios,
            inicio: _inicio(state),
          ),
        ),
        GoRoute(
          path: escaneo,
          builder: (context, state) => EscaneoPage(procesador: procesadorDetecciones, inicio: _inicio(state)),
        ),
        GoRoute(
          path: deteccion,
          builder: (context, state) => ResultadosDeteccionPage(
            servicio: servicioDeteccion,
            inicio: _inicio(state),
            recordatorios: recordatorios,
            suscripcionService: suscripcionService,
          ),
        ),
        GoRoute(
          path: preferencias,
          builder: (context, state) =>
              PreferenciasPage(authService: authService, recordatorios: recordatorios),
        ),
        // El formulario va fuera del shell (sin pestañas). Estas dos rutas
        // van antes que '/suscripcion/:id' para que "nueva" no se lea como id.
        GoRoute(
          path: nuevaSuscripcion,
          builder: (context, state) =>
              SuscripcionFormPage(suscripcionService: suscripcionService, recordatorios: recordatorios),
        ),
        GoRoute(
          path: '/suscripcion/:id/cancelar',
          builder: (context, state) => GuiaCancelacionPage(
            id: _id(state),
            suscripcionService: suscripcionService,
            recordatorios: recordatorios,
          ),
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
                recordatorios: recordatorios,
                inicial: suscripcion,
              );
            }
            return SuscripcionDetallePage(
              id: _id(state),
              authService: authService,
              suscripcionService: suscripcionService,
              recordatorios: recordatorios,
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
                recordatorios: recordatorios,
              ),
            ),
            GoRoute(
              path: suscripciones,
              builder: (context, state) => SuscripcionesPage(
                authService: authService,
                suscripcionService: suscripcionService,
                recordatorios: recordatorios,
              ),
            ),
            GoRoute(
              path: avisos,
              builder: (context, state) => AvisosPage(suscripcionService: suscripcionService),
            ),
            GoRoute(
              path: ahorro,
              // "extra": nombre de la suscripción recién cancelada (desde la guía).
              builder: (context, state) => AhorroPage(
                suscripcionService: suscripcionService,
                recienCancelada: state.extra is String ? state.extra as String : null,
              ),
            ),
            GoRoute(
              path: perfil,
              builder: (context, state) => PerfilPage(
                authService: authService,
                suscripcionService: suscripcionService,
                recordatorios: recordatorios,
                lector: lectorNotificaciones,
              ),
            ),
            GoRoute(
              path: '/suscripcion/:id',
              builder: (context, state) => SuscripcionDetallePage(
                id: _id(state),
                authService: authService,
                suscripcionService: suscripcionService,
                recordatorios: recordatorios,
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
