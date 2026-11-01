import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';

import 'Common/AppTheme.dart';
import 'Common/Routers.dart';
import 'deteccion/deteccion_service.dart';
import 'deteccion/lector_notificaciones.dart';
import 'deteccion/procesador_detecciones.dart';
import 'services/api_client.dart';
import 'services/auth_service.dart';
import 'services/recordatorios_service.dart';
import 'services/suscripcion_service.dart';

Future<void> main() async {
  // Necesario para usar plugins (secure storage, notificaciones) antes de runApp.
  WidgetsFlutterBinding.ensureInitialized();

  // Licencia de la fuente Inter (SIL OFL): aparece en la pantalla de licencias.
  LicenseRegistry.addLicense(() async* {
    final texto = await rootBundle.loadString('assets/fonts/OFL.txt');
    yield LicenseEntryWithLineBreaks(['Inter'], texto);
  });

  // Un solo ApiClient (URL base y token) compartido por todos los servicios.
  final api = ApiClient();
  final authService = AuthService(api);
  final suscripcionService = SuscripcionService(api);

  // Recordatorios locales (solo Android; en web no hace nada).
  final recordatorios = RecordatoriosService();
  await recordatorios.inicializar();
  final payloadInicial = await recordatorios.payloadQueAbrioLaApp();

  // Detección automática: lector nativo, backend y el procesador que los une.
  final lector = LectorNotificaciones();
  final deteccionService = DeteccionService(api);
  final procesador = ProcesadorDetecciones(
    lector: lector,
    servicio: deteccionService,
    cargarCatalogo: suscripcionService.catalogoServicios,
  );

  // Si hay un token guardado y el servidor lo acepta, se abre directo el resumen.
  final haySesion = await authService.haySesionActiva();

  final router = Routers.crear(
    authService,
    suscripcionService,
    recordatorios: recordatorios,
    lector: lector,
    deteccionService: deteccionService,
    procesador: procesador,
    initialLocation: haySesion ? Routers.dashboard : Routers.home,
  );
  // Si el token vence mientras se usa la app, se vuelve al login.
  api.onSesionExpirada = () => router.go(Routers.login);

  // Al tocar un aviso con la app abierta: el detalle de esa suscripción
  // (o el dashboard, para el resumen mensual).
  recordatorios.onAbrir = (id) {
    if (id == null) {
      router.go(Routers.dashboard);
    } else {
      router.push(Routers.detalle(id));
    }
  };

  // Flujo B: al tocar "¿Tienes una suscripción a…?", los resultados (05).
  recordatorios.onAbrirCandidato = (_) => router.push(Routers.deteccion);

  final deteccion = _DeteccionEnSegundoPlano(api, lector, procesador, recordatorios, router);
  WidgetsBinding.instance.addObserver(deteccion);

  runApp(MyApp(router: router));

  WidgetsBinding.instance.addPostFrameCallback((_) {
    // La app estaba cerrada y se abrió tocando un aviso.
    if (haySesion && payloadInicial != null) {
      final candidato = RecordatoriosService.candidatoDelPayload(payloadInicial);
      final suscripcion = int.tryParse(payloadInicial);
      if (candidato != null) {
        router.push(Routers.deteccion);
      } else if (suscripcion != null) {
        router.push(Routers.detalle(suscripcion));
      }
    }
    deteccion.ejecutar();
  });
}

/// Al abrir la app y cada vez que vuelve a primer plano: reconecta el lector
/// (MIUI lo detiene) y, si hay sesión y permiso, procesa la cola de cobros y
/// avisa de las suscripciones nuevas que detectó el backend (flujo B).
class _DeteccionEnSegundoPlano with WidgetsBindingObserver {
  _DeteccionEnSegundoPlano(this.api, this.lector, this.procesador, this.recordatorios, this.router);

  final ApiClient api;
  final LectorNotificaciones lector;
  final ProcesadorDetecciones procesador;
  final RecordatoriosService recordatorios;
  final GoRouter router;

  /// En estas pantallas no se procesa aquí: la propia pantalla lo hace (03,
  /// 04, 05), o se está revisando la cola (depuración).
  static const _rutasPropias = {
    Routers.permisos,
    Routers.escaneo,
    Routers.deteccion,
    Routers.depuracionDeteccion,
  };

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) ejecutar();
  }

  Future<void> ejecutar() async {
    try {
      final ruta = router.routerDelegate.currentConfiguration.uri.path;
      final haySesion = await api.leerToken() != null;
      if (_rutasPropias.contains(ruta) || !haySesion || !(await lector.estado()).permiso) {
        await lector.sincronizar();
        return;
      }
      final resultado = await procesador.procesar();
      for (final c in resultado.candidatosNuevos) {
        await recordatorios.avisarCandidato(c);
      }
    } catch (e) {
      // Sin conexión con el backend: la cola queda para la próxima vez.
      debugPrint('Detección en segundo plano: $e');
    }
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.router});

  final GoRouter router;

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'SubTrack',
      theme: AppTheme.dark,
      routerConfig: router,
      // Textos de Material (calendario, botones) en español de Colombia.
      locale: const Locale('es', 'CO'),
      supportedLocales: const [Locale('es', 'CO'), Locale('es')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
    );
  }
}
