import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../Pages/AhorroPage.dart';
import '../Pages/AnalisisPage.dart';
import '../deteccion/depuracion_deteccion_page.dart';
import '../deteccion/deteccion_service.dart';
import '../deteccion/compartir_page.dart';
import '../deteccion/escaneo_page.dart';
import '../deteccion/historial_sms.dart';
import '../deteccion/historial_sms_page.dart';
import '../deteccion/lector_notificaciones.dart';
import '../deteccion/permisos_page.dart';
import '../deteccion/procesador_detecciones.dart';
import '../deteccion/resultados_deteccion_page.dart';
import '../deteccion/vigilante_deteccion.dart';
import '../services/api_client.dart';
import '../services/avisos_nuevos.dart';
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
  static const String analisis = '/analisis';
  static const String perfil = '/perfil';
  static const String ahorro = '/ahorro';
  static String detalle(int id) => '/suscripcion/$id';

  // Sin barra de pestañas.
  static const String avisos = '/avisos'; // campana del encabezado
  static const String preferencias = '/preferencias';
  static const String depuracionDeteccion = '/depuracion/deteccion';

  // Detección automática (pantallas 03, 04 y 05). "?inicio=1" = vienen del
  // registro: al terminar sigue la preferencia de recordatorio (06).
  static const String permisos = '/permisos';
  static const String escaneo = '/escaneo';
  static const String deteccion = '/deteccion';
  static String rutaPermisos({bool inicio = false}) => inicio ? '$permisos?inicio=1' : permisos;
  static String rutaDeteccion({bool inicio = false}) => inicio ? '$deteccion?inicio=1' : deteccion;

  /// [historial]: además de las notificaciones, busca en los SMS (con permiso).
  static String rutaEscaneo({bool inicio = false, bool historial = false}) =>
      _conParametros(escaneo, {'inicio': inicio, 'historial': historial});

  /// "¿Buscamos suscripciones que ya pagas?" (divulgación antes de READ_SMS).
  /// [trasPermisos]: viene de la pantalla 03 ("Ahora no" sigue al escaneo).
  static const String historialSms = '/historial-sms';
  static String rutaHistorialSms({bool inicio = false, bool trasPermisos = false}) =>
      _conParametros(historialSms, {'inicio': inicio, 'tras': trasPermisos});

  /// Un SMS compartido con SubTrack desde la app de mensajes (texto en "extra").
  static const String compartir = '/compartir';

  static String _conParametros(String ruta, Map<String, bool> banderas) {
    final activas = [for (final MapEntry(:key, :value) in banderas.entries) if (value) '$key=1'];
    return activas.isEmpty ? ruta : '$ruta?${activas.join('&')}';
  }

  static bool _bandera(GoRouterState state, String nombre) => state.uri.queryParameters[nombre] == '1';
  static bool _inicio(GoRouterState state) => _bandera(state, 'inicio');
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
    VigilanteDeteccion? vigilante,
    HistorialSms? historial,
    String initialLocation = home,
    bool depuracion = kDebugMode,
  }) {
    final lectorNotificaciones = lector ?? LectorNotificaciones();
    final servicioDeteccion = deteccionService ?? DeteccionService(ApiClient());
    final vigilanteDeteccion = vigilante ?? VigilanteDeteccion(lectorNotificaciones);
    final procesadorDetecciones = procesador ??
        ProcesadorDetecciones(
          lector: lectorNotificaciones,
          servicio: servicioDeteccion,
          cargarCatalogo: suscripcionService.catalogoServicios,
          historial: historial,
        );
    final historialSmsApp = historial ?? procesadorDetecciones.historial;
    // Número de la campana de avisos (encabezados de las pestañas).
    final avisosNuevos = AvisosNuevos(suscripcionService);
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
            vigilante: vigilanteDeteccion,
            historial: historialSmsApp,
            recordatorios: recordatorios,
            inicio: _inicio(state),
          ),
        ),
        GoRoute(
          path: escaneo,
          builder: (context, state) => EscaneoPage(
            procesador: procesadorDetecciones,
            inicio: _inicio(state),
            historial: _bandera(state, 'historial'),
          ),
        ),
        GoRoute(
          path: historialSms,
          builder: (context, state) => HistorialSmsPage(
            historial: historialSmsApp,
            inicio: _inicio(state),
            trasPermisos: _bandera(state, 'tras'),
          ),
        ),
        GoRoute(
          path: compartir,
          builder: (context, state) => CompartirPage(
            texto: state.extra is String ? state.extra as String : '',
            servicio: servicioDeteccion,
            cargarCatalogo: suscripcionService.catalogoServicios,
            almacen: procesadorDetecciones.almacen,
            authService: authService,
          ),
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
        // Avisos: se abre desde la campana, encima de la pestaña (sin barra).
        GoRoute(
          path: avisos,
          builder: (context, state) =>
              AvisosPage(suscripcionService: suscripcionService, avisosNuevos: avisosNuevos),
        ),
        ShellRoute(
          builder: (context, state, child) => AppShell(avisosNuevos: avisosNuevos, child: child),
          routes: [
            GoRoute(
              path: dashboard,
              builder: (context, state) => DashboardPage(
                authService: authService,
                suscripcionService: suscripcionService,
                recordatorios: recordatorios,
                vigilante: vigilanteDeteccion,
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
              path: analisis,
              builder: (context, state) => AnalisisPage(suscripcionService: suscripcionService),
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
                vigilante: vigilanteDeteccion,
                historial: historialSmsApp,
              ),
            ),
            GoRoute(
              path: '/suscripcion/:id',
              builder: (context, state) => SuscripcionDetallePage(
                id: _id(state),
                // Desde una tarjeta llega la suscripción: se muestra mientras carga.
                inicial: state.extra is Suscripcion ? state.extra as Suscripcion : null,
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
