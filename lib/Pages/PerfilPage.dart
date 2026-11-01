import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../Common/AppTheme.dart';
import '../Common/Routers.dart';
import '../deteccion/historial_sms.dart';
import '../deteccion/vigilante_deteccion.dart';
import '../models/ahorro.dart';
import '../models/usuario.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/recordatorios_service.dart';
import '../services/suscripcion_service.dart';
import '../utils/formato.dart';
import '../widgets/app_botones.dart';
import '../widgets/app_card.dart';
import '../widgets/app_feedback.dart';
import '../widgets/app_header.dart';
import '../widgets/guia_xiaomi.dart';

/// Perfil y configuración (pantalla 14 del diseño, pestaña 4): días de
/// anticipación, recordatorios en el celular, cerrar sesión y eliminar la
/// cuenta.
class PerfilPage extends StatefulWidget {
  const PerfilPage({
    super.key,
    required this.authService,
    this.suscripcionService,
    this.recordatorios,
    this.vigilante,
    this.historial,
  });

  final AuthService authService;

  /// "Buscar suscripciones en mis SMS": solo si la versión lo incluye
  /// (completa) y en Android.
  final HistorialSms? historial;

  /// Estado real de la detección: el interruptor "Permiso de notificaciones"
  /// distingue permiso concedido de lector conectado. Solo en Android.
  final VigilanteDeteccion? vigilante;

  /// Para reprogramar los recordatorios al cambiar las preferencias.
  final SuscripcionService? suscripcionService;

  /// null en los tests; en web la sección de recordatorios no se muestra.
  final RecordatoriosService? recordatorios;

  @override
  State<PerfilPage> createState() => _PerfilPageState();
}

class _PerfilPageState extends State<PerfilPage> with WidgetsBindingObserver {
  Usuario? _usuario;
  int? _dias;
  Ahorro? _ahorro;
  bool _guardando = false;

  // Recordatorios (solo Android).
  bool _activos = true;
  bool _resumen = true;
  bool _permiso = false;
  bool _xiaomi = false;
  bool _conHistorial = false;

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
    _vigilante?.verificar(motivo: 'perfil');
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

  Future<void> _cargarAhorro() async {
    try {
      final ahorro = await widget.suscripcionService?.ahorro();
      if (mounted && ahorro != null) setState(() => _ahorro = ahorro);
    } on ApiException {
      // No es crítico: la fila muestra solo la flecha.
    }
  }

  Future<void> _abrirAhorro() async {
    await context.push(Routers.ahorro);
    if (mounted) _cargarAhorro();
  }

  /// "$465.600 ›" (o "$465.600 + US$119,88 ›" si hay en dos monedas).
  String get _textoAhorro {
    final totales = _ahorro?.totales ?? const <TotalAhorro>[];
    final monto = totales.isEmpty
        ? Formato.moneda(0, 'COP')
        : totales.map((t) => Formato.moneda(t.anual, t.moneda)).join(' + ');
    return '$monto ›';
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
    final xiaomi = await rec.esXiaomi();
    if (!mounted) return;
    setState(() {
      _activos = activos;
      _resumen = resumen;
      _permiso = permiso;
      _xiaomi = xiaomi;
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
    setState(() => _resumen = activo);
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


  Widget _seccionRecordatorios() {
    final estado = !_activos
        ? 'Desactivados'
        : _permiso
            ? 'Activos · a las 9:00 a. m. en este celular'
            : 'Sin permiso de notificaciones';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Column(
            children: [
              _FilaInterruptor(
                titulo: 'Recordatorios',
                descripcion: estado,
                valor: _activos,
                onChanged: _cambiarActivos,
              ),
              const Divider(height: 1, color: AppColors.divider),
              _FilaInterruptor(
                titulo: 'Resumen mensual',
                descripcion: 'Cada 1 del mes',
                valor: _resumen,
                onChanged: _activos ? _cambiarResumen : null,
              ),
            ],
          ),
        ),
        if (_activos && !_permiso) ...[
          const SizedBox(height: 9),
          AppBotonSecundario(
            texto: 'Permitir notificaciones',
            icon: Icons.notifications_active_outlined,
            onPressed: _pedirPermiso,
          ),
        ],
        const SizedBox(height: 9),
        AppBotonSecundario(
          texto: 'Probar aviso',
          icon: Icons.notifications_outlined,
          onPressed: _probarAviso,
        ),
        if (_xiaomi) ...[
          const SizedBox(height: 14),
          GuiaXiaomi(
            onInicioAutomatico: _rec!.abrirInicioAutomatico,
            onAjustes: _rec!.abrirAjustesApp,
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final u = _usuario;
    return Scaffold(
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          AppHeader(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 22),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.avatar,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.lineStrong),
                  ),
                  child: Text(
                    u?.iniciales ?? '',
                    style: const TextStyle(
                      color: Color(0xFFCFE0FF),
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        u?.nombre ?? '',
                        style: const TextStyle(
                          color: AppColors.text,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${u?.correo ?? ''} · Colombia (COP)',
                        style: const TextStyle(
                          color: AppColors.mutedOnGradient,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Avisarme antes de cada cobro',
                        style: TextStyle(color: AppColors.text, fontSize: 13.5, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Preferencia global',
                        style: TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 12),
                      AppPills<int>(
                        opciones: const [(1, '1 día'), (3, '3 días'), (7, '7 días')],
                        seleccion: _dias,
                        onChanged: _dias == null || _guardando ? null : _cambiarDias,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                if (_vigilante != null) ...[
                  ValueListenableBuilder<EstadoDeteccion>(
                    valueListenable: _vigilante!.estado,
                    builder: (context, estado, _) => AppCard(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: _FilaInterruptor(
                        titulo: 'Permiso de notificaciones',
                        descripcion: textoInterruptorDeteccion(estado),
                        // "Activo" solo si el lector está conectado de verdad.
                        valor: estado == EstadoDeteccion.activa || estado == EstadoDeteccion.comprobando,
                        onChanged: estado == EstadoDeteccion.comprobando ? null : (_) => _cambiarDeteccion(estado),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                if (_rec != null) ...[
                  _seccionRecordatorios(),
                  const SizedBox(height: 14),
                ],
                AppCard(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Column(
                    children: [
                      if (widget.suscripcionService != null) ...[
                        _FilaEnlace(
                          texto: 'Historial y ahorro',
                          detalle: _textoAhorro,
                          colorDetalle: AppColors.link,
                          onTap: _abrirAhorro,
                        ),
                        const Divider(height: 1, color: AppColors.divider),
                      ],
                      // Repetible: lo ya enviado no se duplica (huella y AnalizadorPagos).
                      if (_conHistorial) ...[
                        _FilaEnlace(
                          texto: 'Buscar suscripciones en mis SMS',
                          detalle: '›',
                          colorDetalle: AppColors.muted,
                          onTap: () => context.push(Routers.historialSms),
                        ),
                        const Divider(height: 1, color: AppColors.divider),
                      ],
                      _FilaEnlace(
                        texto: 'Agregar suscripción manual',
                        detalle: '›',
                        colorDetalle: AppColors.muted,
                        onTap: () => context.push(Routers.nuevaSuscripcion),
                      ),
                      // Solo en modo debug y en Android: lector de notificaciones (hito 1).
                      if (kDebugMode && _rec != null) ...[
                        const Divider(height: 1, color: AppColors.divider),
                        _FilaEnlace(
                          texto: 'Depuración: detección',
                          detalle: '›',
                          colorDetalle: AppColors.muted,
                          onTap: () => context.push(Routers.depuracionDeteccion),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                AppBotonSecundario(texto: 'Cerrar sesión', onPressed: _cerrarSesion),
                const SizedBox(height: 9),
                AppBotonSecundario(
                  texto: 'Eliminar cuenta y todos mis datos',
                  ambar: true,
                  onPressed: _eliminarCuenta,
                ),
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

class _FilaInterruptor extends StatelessWidget {
  const _FilaInterruptor({
    required this.titulo,
    required this.descripcion,
    required this.valor,
    required this.onChanged,
  });

  final String titulo;
  final String descripcion;
  final bool valor;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      value: valor,
      onChanged: onChanged,
      activeTrackColor: AppColors.primary,
      title: Text(
        titulo,
        style: const TextStyle(color: AppColors.text, fontSize: 13.5, fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        descripcion,
        style: const TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// Fila tocable con texto a la izquierda y un detalle a la derecha.
class _FilaEnlace extends StatelessWidget {
  const _FilaEnlace({
    required this.texto,
    required this.detalle,
    required this.colorDetalle,
    required this.onTap,
  });

  final String texto;
  final String detalle;
  final Color colorDetalle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 15),
        child: Row(
          children: [
            Expanded(
              child: Text(
                texto,
                style: const TextStyle(color: AppColors.text, fontSize: 13.5, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 12),
            // El texto de la izquierda usa el espacio libre; el detalle va a la
            // derecha y, si es muy largo (dos monedas), se parte en líneas.
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 170),
              child: Text(
                detalle,
                textAlign: TextAlign.right,
                style: TextStyle(color: colorDetalle, fontSize: 13.5, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
