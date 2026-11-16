import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../Common/AppTheme.dart';
import '../Common/Routers.dart';
import '../deteccion/aviso_segundo_plano.dart';
import '../deteccion/historial_sms.dart';
import '../deteccion/vigilante_deteccion.dart';
import '../models/ahorro.dart';
import '../models/resumen.dart';
import '../models/usuario.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/recordatorios_service.dart';
import '../services/suscripcion_service.dart';
import '../services/version_app.dart';
import '../utils/formato.dart';
import '../widgets/ajustes.dart';
import '../widgets/app_botones.dart';
import '../widgets/app_feedback.dart';
import '../widgets/app_header.dart';
import '../widgets/app_shell.dart';
import '../widgets/campana_avisos.dart';
import 'perfil_cabecera.dart';

/// Perfil y configuración (pantalla 14 del diseño, pestaña 4). Cabecera con
/// la cuenta y tres datos (activas y gasto mensual) y las opciones agrupadas
/// en secciones: Avisos, Detección automática, Privacidad y legal y Acerca
/// de. Al final, cerrar sesión, eliminar la cuenta y la versión de la app.
class PerfilPage extends StatefulWidget {
  const PerfilPage({
    super.key,
    required this.authService,
    this.suscripcionService,
    this.recordatorios,
    this.vigilante,
    this.historial,
    this.segundoPlano,
    this.version = versionApp,
  });

  final AuthService authService;

  /// Fila "Segundo plano" (guía del encargo C): dice "Revisado" si el usuario
  /// ya tocó "Ya lo activé".
  final RegistroSegundoPlano? segundoPlano;

  /// "Buscar suscripciones en mis SMS": solo si la versión lo incluye
  /// (completa) y en Android.
  final HistorialSms? historial;

  /// Estado real de la detección: el interruptor "Permiso de notificaciones"
  /// distingue permiso concedido de lector conectado. Solo en Android.
  final VigilanteDeteccion? vigilante;

  /// Para reprogramar los recordatorios al cambiar las preferencias, y para
  /// los datos de la cabecera y el ahorro.
  final SuscripcionService? suscripcionService;

  /// null en los tests; en web la sección de recordatorios no se muestra.
  final RecordatoriosService? recordatorios;

  /// Versión de la app, leída del paquete (pie de la pantalla).
  final Future<String?> Function() version;

  @override
  State<PerfilPage> createState() => _PerfilPageState();
}

class _PerfilPageState extends State<PerfilPage> with WidgetsBindingObserver {
  Usuario? _usuario;
  int? _dias;
  Ahorro? _ahorro;
  Resumen? _resumen;
  String? _version;
  bool _guardando = false;

  // Recordatorios (solo Android).
  bool _activos = true;
  bool _resumenMensual = true;
  bool _permiso = false;
  bool _conHistorial = false;
  bool _guiaVista = false;

  VigilanteDeteccion? get _vigilante =>
      widget.vigilante?.lector.disponible ?? false ? widget.vigilante : null;

  RecordatoriosService? get _rec =>
      widget.recordatorios?.disponible ?? false ? widget.recordatorios : null;

  @override
  void initState() {
    super.initState();
    _usuario = widget.authService.usuario;
    WidgetsBinding.instance.addObserver(this);
    _cargar();
    _cargarRecordatorios();
    _cargarAhorro();
    _cargarResumen();
    _vigilante?.verificar(motivo: 'perfil');
    _cargarGuiaVista();
    widget.version().then((v) {
      if (mounted) setState(() => _version = v);
    });
    widget.historial?.disponible().then((si) {
      if (mounted && si) setState(() => _conHistorial = true);
    });
  }

  /// Según el estado real: sin permiso abre la pantalla de permisos (03);
  /// pausada abre el ajuste para apagar y encender el acceso; activa abre los
  /// ajustes para quitarlo (solo se puede quitar ahí).
  Future<void> _cambiarDeteccion(EstadoDeteccion estado) async {
    final vigilante = _vigilante!;
    switch (estado) {
      case EstadoDeteccion.sinPermiso:
        await context.push(Routers.permisos);
      case EstadoDeteccion.pausada:
        mostrarToast(context, 'Desactiva y vuelve a activar el acceso de SubTrack');
        await vigilante.lector.abrirAjustesAcceso();
      case EstadoDeteccion.activa:
        await vigilante.lector.abrirAjustesAcceso();
      case EstadoDeteccion.comprobando || EstadoDeteccion.noDisponible:
        return;
    }
    vigilante.verificar(motivo: 'perfil');
  }

  Future<void> _cargarGuiaVista() async {
    final vista = await widget.segundoPlano?.guiaVista();
    if (mounted) setState(() => _guiaVista = vista != null);
  }

  Future<void> _abrirSegundoPlano() async {
    await context.push(Routers.segundoPlano);
    _cargarGuiaVista();
  }

  Future<void> _cargarAhorro() async {
    try {
      final ahorro = await widget.suscripcionService?.ahorro();
      if (mounted && ahorro != null) setState(() => _ahorro = ahorro);
    } on ApiException {
      // No es crítico: la fila muestra solo la flecha.
    }
  }

  /// Los datos de la cabecera salen del mismo resumen que usa Inicio.
  Future<void> _cargarResumen() async {
    try {
      final resumen = await widget.suscripcionService?.resumen();
      if (mounted && resumen != null) setState(() => _resumen = resumen);
    } on ApiException {
      // No es crítico: la cabecera muestra guiones.
    }
  }

  /// El ahorro por cancelaciones vive en la pestaña Análisis; esta fila es
  /// un acceso directo.
  void _abrirAhorro() => context.go(Routers.analisis);

  /// "$465.600 ahorrados al año" (o "$465.600 + US$119,88 …" en dos monedas).
  String get _textoAhorro {
    final totales = _ahorro?.totales ?? const <TotalAhorro>[];
    final monto = totales.isEmpty
        ? Formato.moneda(0, 'COP')
        : totales.map((t) => Formato.moneda(t.anual, t.moneda)).join(' + ');
    return '$monto ahorrados al año';
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Al volver de los ajustes del sistema, el permiso pudo cambiar.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _cargarRecordatorios();
      _vigilante?.verificar(motivo: 'perfil');
    }
  }

  Future<void> _cargarRecordatorios() async {
    final rec = _rec;
    if (rec == null) return;
    final activos = await rec.activos();
    final resumen = await rec.resumenMensual();
    final permiso = await rec.tienePermiso();
    if (!mounted) return;
    setState(() {
      _activos = activos;
      _resumenMensual = resumen;
      _permiso = permiso;
    });
  }

  void _sincronizar() {
    final servicio = widget.suscripcionService;
    if (servicio != null) _rec?.sincronizar(servicio);
  }

  Future<void> _cambiarActivos(bool activos) async {
    setState(() => _activos = activos);
    await _rec!.cambiarActivos(activos);
    if (activos) _sincronizar();
  }

  Future<void> _cambiarResumen(bool activo) async {
    setState(() => _resumenMensual = activo);
    await _rec!.cambiarResumenMensual(activo);
    _sincronizar();
  }

  Future<void> _pedirPermiso() async {
    final concedido = await _rec!.pedirPermiso();
    if (!mounted) return;
    setState(() => _permiso = concedido);
    if (concedido) {
      _sincronizar();
      mostrarToast(context, 'Listo: te avisaremos antes de cada cobro');
    } else {
      // Si ya lo rechazó antes, Android no vuelve a mostrar el diálogo:
      // se abren los ajustes de la app para activarlo a mano.
      mostrarToast(context, 'Actívalas en Notificaciones, dentro de los ajustes de la app');
      await _rec!.abrirAjustesApp();
    }
  }

  Future<void> _probarAviso() async {
    await _rec!.probarAviso();
    if (mounted) {
      mostrarToast(context, 'Te llegará un aviso en unos 10 segundos. Puedes salir de la app.');
    }
  }

  Future<void> _cargar() async {
    try {
      final resultados = await Future.wait([
        widget.authService.me(),
        widget.authService.obtenerDiasAnticipacion(),
      ]);
      if (!mounted) return;
      setState(() {
        _usuario = resultados[0] as Usuario? ?? _usuario;
        _dias = resultados[1] as int;
      });
    } on ApiException catch (e) {
      if (mounted) mostrarToast(context, e.mensaje);
    }
  }

  Future<void> _cambiarDias(int dias) async {
    final anterior = _dias;
    setState(() {
      _dias = dias;
      _guardando = true;
    });
    try {
      await widget.authService.guardarDiasAnticipacion(dias);
      _sincronizar();
      if (mounted) {
        mostrarToast(context, 'Te avisaremos ${dias == 1 ? '1 día' : '$dias días'} antes de cada cobro');
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _dias = anterior);
        mostrarToast(context, e.mensaje);
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _cerrarSesion() async {
    await widget.authService.cerrarSesion();
    // Los avisos son de esta cuenta: no deben seguir llegando.
    await widget.recordatorios?.cancelarTodo();
    if (mounted) context.go(Routers.login);
  }

  Future<void> _eliminarCuenta() async {
    final eliminada = await confirmarConContrasena(
      context,
      titulo: '¿Eliminar tu cuenta?',
      texto: 'Borramos tu cuenta, tus suscripciones, el historial y los recordatorios. '
          'Esto no se puede deshacer.',
      boton: 'Eliminar cuenta y datos',
      accion: widget.authService.eliminarCuenta,
      mensajeDeError: (e) => e is ApiException ? e.mensaje : ApiClient.errorConexion,
    );
    if (!eliminada || !mounted) return;
    await widget.recordatorios?.cancelarTodo();
    if (!mounted) return;
    mostrarToast(context, 'Tu cuenta y todos tus datos fueron eliminados');
    context.go(Routers.login);
  }

  // ─── Secciones ────────────────────────────────────────────────────────

  String get _textoDias => switch (_dias) {
        null => 'Cargando…',
        1 => '1 día antes',
        final d => '$d días antes',
      };

  String get _textoRecordatorios => !_activos
      ? 'Desactivados'
      : _permiso
          ? 'Activos · 9:00 a. m.'
          : 'Sin permiso de notificaciones';

  Widget _seccionAvisos() {
    final rec = _rec;
    return SeccionAjustes(
      titulo: 'Avisos',
      filas: [
        FilaAjuste(
          icono: Icons.schedule_rounded,
          color: ColoresAjustes.celeste,
          titulo: 'Avisarme antes de cada cobro',
          subtitulo: _textoDias,
          debajo: AppPills<int>(
            opciones: const [(1, '1 día'), (3, '3 días'), (7, '7 días')],
            seleccion: _dias,
            onChanged: _dias == null || _guardando ? null : _cambiarDias,
          ),
        ),
        if (rec != null) ...[
          FilaAjuste.interruptor(
            icono: Icons.notifications_active_outlined,
            color: ColoresAjustes.ambar,
            titulo: 'Recordatorios',
            subtitulo: _textoRecordatorios,
            valor: _activos,
            onCambiar: _cambiarActivos,
          ),
          if (_activos && !_permiso)
            FilaAjuste(
              icono: Icons.lock_open_rounded,
              color: ColoresAjustes.dorado,
              titulo: 'Permitir notificaciones',
              subtitulo: 'Necesario para recibir los recordatorios',
              colorSubtitulo: AppColors.amber,
              onTap: _pedirPermiso,
            ),
          FilaAjuste.interruptor(
            icono: Icons.calendar_month_outlined,
            color: ColoresAjustes.lavanda,
            titulo: 'Resumen mensual',
            subtitulo: 'Cada 1 del mes',
            valor: _resumenMensual,
            onCambiar: _activos ? _cambiarResumen : null,
          ),
          FilaAjuste(
            icono: Icons.notifications_outlined,
            color: ColoresAjustes.azul,
            titulo: 'Probar aviso',
            subtitulo: 'Llega en unos 10 segundos',
            onTap: _probarAviso,
          ),
        ],
      ],
    );
  }

  Widget _seccionDeteccion(EstadoDeteccion? estado) {
    return SeccionAjustes(
      titulo: 'Detección automática',
      filas: [
        if (estado != null) ...[
          FilaAjuste.interruptor(
            icono: Icons.mark_email_unread_outlined,
            color: ColoresAjustes.azul,
            titulo: 'Permiso de notificaciones',
            subtitulo: textoInterruptorDeteccion(estado),
            // "Activo" solo si el lector está conectado de verdad.
            valor: estado == EstadoDeteccion.activa || estado == EstadoDeteccion.comprobando,
            onCambiar: estado == EstadoDeteccion.comprobando ? null : (_) => _cambiarDeteccion(estado),
          ),
          // Guía de segundo plano (encargo C), para todas las marcas.
          FilaAjuste(
            icono: Icons.battery_charging_full_rounded,
            color: ColoresAjustes.ambar,
            titulo: 'Segundo plano',
            subtitulo: _guiaVista ? 'Revisado' : 'Para avisarte aunque la app esté cerrada',
            onTap: _abrirSegundoPlano,
          ),
        ],
        // Repetible: lo ya enviado no se duplica (huella y AnalizadorPagos).
        if (_conHistorial)
          FilaAjuste(
            icono: Icons.sms_outlined,
            color: ColoresAjustes.celeste,
            titulo: 'Buscar suscripciones en mis SMS',
            subtitulo: 'Revisa los últimos 6 meses',
            onTap: () => context.push(Routers.historialSms),
          ),
        FilaAjuste(
          icono: Icons.block_rounded,
          color: ColoresAjustes.rosa,
          titulo: 'Detecciones descartadas',
          subtitulo: 'Las que marcaste como «No es mía»',
          onTap: () => context.push(Routers.deteccionesDescartadas),
        ),
        FilaAjuste(
          icono: Icons.add_rounded,
          color: ColoresAjustes.primario,
          titulo: 'Agregar suscripción manual',
          subtitulo: 'Sin esperar una detección',
          onTap: () => context.push(Routers.nuevaSuscripcion),
        ),
        // Solo en modo debug y en Android: lector de notificaciones (hito 1).
        if (kDebugMode && _rec != null)
          FilaAjuste(
            icono: Icons.bug_report_outlined,
            color: ColoresAjustes.gris,
            titulo: 'Depuración: detección',
            subtitulo: 'Solo en la versión de pruebas',
            onTap: () => context.push(Routers.depuracionDeteccion),
          ),
      ],
    );
  }

  Widget _seccionLegal() => SeccionAjustes(
        titulo: 'Privacidad y legal',
        filas: [
          FilaAjuste(
            icono: Icons.shield_outlined,
            color: ColoresAjustes.azul,
            titulo: 'Política de privacidad',
            subtitulo: 'Ley 1581 de 2012',
            onTap: () => context.push(Routers.privacidad),
          ),
          FilaAjuste(
            icono: Icons.description_outlined,
            color: ColoresAjustes.lavanda,
            titulo: 'Términos de uso',
            onTap: () => context.push(Routers.terminos),
          ),
          FilaAjuste(
            icono: Icons.storage_rounded,
            color: ColoresAjustes.celeste,
            titulo: 'Qué datos guardamos',
            subtitulo: 'En el servidor y en tu celular',
            onTap: () => context.push(Routers.datosGuardados),
          ),
        ],
      );

  Widget _seccionAcercaDe() => SeccionAjustes(
        titulo: 'Acerca de',
        filas: [
          FilaAjuste(
            icono: Icons.info_outline_rounded,
            color: ColoresAjustes.gris,
            titulo: 'Acerca de SubTrack',
            subtitulo: _version,
            onTap: () => context.push(Routers.acercaDe),
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    const separacion = SizedBox(height: 20);
    return Scaffold(
      body: ListView(
        padding: AppShell.rellenoInferior(context),
        children: [
          _Cabecera(usuario: _usuario, datos: datosCabeceraPerfil(_resumen)),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Acceso directo a la pestaña Análisis (estaba en el Perfil).
                if (widget.suscripcionService != null) ...[
                  SeccionAjustes(
                    filas: [
                      FilaAjuste(
                        icono: Icons.savings_outlined,
                        color: ColoresAjustes.celeste,
                        titulo: 'Análisis y ahorro',
                        subtitulo: _textoAhorro,
                        colorSubtitulo: AppColors.link,
                        onTap: _abrirAhorro,
                      ),
                    ],
                  ),
                  separacion,
                ],
                _seccionAvisos(),
                separacion,
                if (_vigilante != null)
                  ValueListenableBuilder<EstadoDeteccion>(
                    valueListenable: _vigilante!.estado,
                    builder: (context, estado, _) => _seccionDeteccion(estado),
                  )
                else
                  _seccionDeteccion(null),
                separacion,
                _seccionLegal(),
                separacion,
                _seccionAcercaDe(),
                separacion,
                SeccionAjustes(
                  filas: [
                    InkWell(
                      onTap: _cerrarSesion,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.logout_rounded, size: 19, color: AppColors.error),
                            SizedBox(width: 8),
                            Text(
                              'Cerrar sesión',
                              style: TextStyle(color: AppColors.error, fontSize: 14.5, fontWeight: FontWeight.w800),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 11),
                AppBotonSecundario(
                  texto: 'Eliminar cuenta y todos mis datos',
                  ambar: true,
                  onPressed: _eliminarCuenta,
                ),
                if (_version != null) ...[
                  const SizedBox(height: 18),
                  Text(
                    'SubTrack · $_version',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Texto del interruptor "Permiso de notificaciones" según el estado real.
String textoInterruptorDeteccion(EstadoDeteccion estado) => switch (estado) {
      EstadoDeteccion.activa => 'Activo · detección automática encendida',
      EstadoDeteccion.pausada => 'Detección pausada · toca para reactivarla',
      EstadoDeteccion.comprobando => 'Comprobando la detección…',
      EstadoDeteccion.sinPermiso || EstadoDeteccion.noDisponible => 'Desactivado · solo registro manual',
    };

/// Cabecera: avatar con la inicial, nombre, correo y país/moneda, y debajo
/// los datos de [datosCabeceraPerfil].
class _Cabecera extends StatelessWidget {
  const _Cabecera({required this.usuario, required this.datos});

  final Usuario? usuario;
  final List<DatoCabecera> datos;

  @override
  Widget build(BuildContext context) {
    final u = usuario;
    return AppHeader(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.avatar,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.lineStrong, width: 1.5),
                ),
                child: Text(
                  u?.iniciales ?? '',
                  style: const TextStyle(color: Color(0xFFCFE0FF), fontSize: 19, fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      u?.nombre ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.text,
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      u?.correo ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.mutedOnGradient, fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 1),
                    const Text(
                      'Colombia · COP',
                      style: TextStyle(color: AppColors.mutedOnGradient, fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const CampanaAvisos(),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
            ),
            child: IntrinsicHeight(
              child: Row(
                children: [
                  for (final (i, d) in datos.indexed) ...[
                    if (i > 0) VerticalDivider(width: 1, thickness: 1, color: Colors.white.withValues(alpha: 0.16)),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Column(
                          children: [
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                d.valor,
                                style: const TextStyle(
                                  color: AppColors.text,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                  fontFeatures: [FontFeature.tabularFigures()],
                                ),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              d.etiqueta,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: AppColors.mutedHero, fontSize: 11, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
