import 'dart:async';

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
import 'deteccion/receptor_compartir.dart';
import 'deteccion/vigilante_deteccion.dart';
import 'services/api_client.dart';
import 'services/auth_service.dart';
import 'services/recordatorios_service.dart';
import 'services/suscripcion_service.dart';
import 'widgets/animacion_inicio.dart';
import 'widgets/aviso_despertando.dart';

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
  // Estado real de la detección (permiso + lector conectado), para Perfil,
  // el dashboard y la pantalla de permisos.
  final vigilante = VigilanteDeteccion(lector);
  // Los pagos detectados que viven solo en el celular son del usuario de la
  // sesión: se borran al cerrarla.
  authService.alCerrarSesion = procesador.almacen.borrarTodo;

  // Si hay un token guardado y el servidor lo acepta, se abre directo el resumen.
  // Con el servidor dormido (Render) esto puede tardar cerca de 1 minuto:
  // mientras tanto se muestra la pantalla de arranque con el aviso.
  final animacion = Completer<void>();
  runApp(PantallaArranque(
    despertando: api.despertando,
    alTerminar: () => animacion.isCompleted ? null : animacion.complete(),
  ));
  final haySesion = await authService.haySesionActiva();

  final router = Routers.crear(
    authService,
    suscripcionService,
    recordatorios: recordatorios,
    lector: lector,
    deteccionService: deteccionService,
    procesador: procesador,
    vigilante: vigilante,
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

  // "Compartir" un SMS con SubTrack desde la app de mensajes.
  final compartir = ReceptorCompartir();
  compartir.escuchar((texto) => router.push(Routers.compartir, extra: texto));

  final deteccion = _DeteccionEnSegundoPlano(api, vigilante, procesador, recordatorios, router);
  WidgetsBinding.instance.addObserver(deteccion);

  // La animación de inicio termina antes de pasar a la app (si la sesión
  // tarda más, el anillo sigue girando hasta aquí).
  await animacion.future;
  runApp(MyApp(router: router, despertando: api.despertando));

  WidgetsBinding.instance.addPostFrameCallback((_) async {
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
    // La app se abrió compartiendo un SMS.
    final texto = await compartir.textoPendiente();
    if (texto != null) router.push(Routers.compartir, extra: texto);
  });
}

/// Al abrir la app y cada vez que vuelve a primer plano: comprueba que el
/// lector esté conectado (y si no, intenta reconectarlo: MIUI lo detiene y
/// HyperOS a veces no lo reenlaza tras actualizar la app) y, si hay sesión y
/// permiso, procesa la cola de cobros y avisa de las suscripciones nuevas que
/// detectó el backend (flujo B).
class _DeteccionEnSegundoPlano with WidgetsBindingObserver {
  _DeteccionEnSegundoPlano(this.api, this.vigilante, this.procesador, this.recordatorios, this.router);

  final ApiClient api;
  final VigilanteDeteccion vigilante;
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
    Routers.historialSms,
  };

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) ejecutar();
  }

  Future<void> ejecutar() async {
    try {
      final ruta = router.routerDelegate.currentConfiguration.uri.path;
      // Reconecta si hace falta y publica el estado (activa / pausada / sin permiso).
      final estado = await vigilante.verificar(motivo: 'app abierta o en primer plano');
      final haySesion = await api.leerToken() != null;
      final conPermiso = estado == EstadoDeteccion.activa || estado == EstadoDeteccion.pausada;
      if (_rutasPropias.contains(ruta) || !haySesion || !conPermiso) return;
      // También en pausa: la cola puede tener cobros guardados antes.
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
  const MyApp({super.key, required this.router, this.despertando});

  final GoRouter router;

  /// true mientras el servidor despierta: se muestra un aviso sobre cualquier pantalla.
  final ValueListenable<bool>? despertando;

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'SubTrack',
      theme: AppTheme.dark,
      routerConfig: router,
      builder: (context, child) {
        final pantalla = _EntradaSuave(child: child ?? const SizedBox.shrink());
        final aviso = despertando;
        return aviso == null ? pantalla : AvisoDespertando(despertando: aviso, child: pantalla);
      },
      // Textos de Material (calendario, botones) en español de Colombia.
      locale: const Locale('es', 'CO'),
      supportedLocales: const [Locale('es', 'CO'), Locale('es')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
    );
  }
}

/// Mientras se comprueba la sesión guardada al abrir la app: la animación del
/// logo y, si el servidor está dormido, el aviso "Despertando el servidor…".
/// [alTerminar] avisa cuando la animación y su pausa acabaron.
class PantallaArranque extends StatelessWidget {
  const PantallaArranque({super.key, required this.despertando, this.alTerminar});

  final ValueListenable<bool> despertando;
  final VoidCallback? alTerminar;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SubTrack',
      theme: AppTheme.dark,
      home: AvisoDespertando(
        despertando: despertando,
        child: Scaffold(
          // Mismo fondo que el splash nativo: sin salto entre los dos.
          backgroundColor: ColoresLogo.fondo,
          body: Center(child: AnimacionInicio(alTerminar: alTerminar)),
        ),
      ),
    );
  }
}

/// La primera pantalla aparece con un fundido corto tras la animación de
/// inicio (sin animación si el sistema las tiene reducidas).
class _EntradaSuave extends StatefulWidget {
  const _EntradaSuave({required this.child});

  final Widget child;

  @override
  State<_EntradaSuave> createState() => _EntradaSuaveState();
}

class _EntradaSuaveState extends State<_EntradaSuave> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 350));
  late final Animation<double> _opacidad = CurvedAnimation(parent: _controller, curve: Curves.easeOut);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller.isDismissed) {
      if (MediaQuery.of(context).disableAnimations) {
        _controller.value = 1;
      } else {
        _controller.forward();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.bg,
      child: FadeTransition(
        opacity: _opacidad,
        child: widget.child,
      ),
    );
  }
}
