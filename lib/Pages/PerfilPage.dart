import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../Common/AppTheme.dart';
import '../Common/Routers.dart';
import '../models/usuario.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/recordatorios_service.dart';
import '../services/suscripcion_service.dart';
import '../widgets/app_botones.dart';
import '../widgets/app_card.dart';
import '../widgets/app_feedback.dart';
import '../widgets/app_header.dart';

/// Perfil y configuración (pantalla 14 del diseño, pestaña 4): días de
/// anticipación, recordatorios en el celular, cerrar sesión y eliminar la
/// cuenta.
class PerfilPage extends StatefulWidget {
  const PerfilPage({
    super.key,
    required this.authService,
    this.suscripcionService,
    this.recordatorios,
  });

  final AuthService authService;

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
  bool _guardando = false;

  // Recordatorios (solo Android).
  bool _activos = true;
  bool _resumen = true;
  bool _permiso = false;
  bool _xiaomi = false;

  RecordatoriosService? get _rec =>
      widget.recordatorios?.disponible ?? false ? widget.recordatorios : null;

  @override
  void initState() {
    super.initState();
    _usuario = widget.authService.usuario;
    WidgetsBinding.instance.addObserver(this);
    _cargar();
    _cargarRecordatorios();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Al volver de los ajustes del sistema, el permiso pudo cambiar.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _cargarRecordatorios();
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
          _GuiaXiaomi(
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
                if (_rec != null) ...[
                  _seccionRecordatorios(),
                  const SizedBox(height: 14),
                ],
                AppCard(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: InkWell(
                    onTap: () => context.push(Routers.nuevaSuscripcion),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 15),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Agregar suscripción manual',
                              style: TextStyle(color: AppColors.text, fontSize: 13.5, fontWeight: FontWeight.w700),
                            ),
                          ),
                          Text('›', style: TextStyle(color: AppColors.muted, fontSize: 16)),
                        ],
                      ),
                    ),
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

/// HyperOS/MIUI cierra las apps en segundo plano y puede bloquear los
/// avisos programados. Estos dos ajustes lo evitan.
class _GuiaXiaomi extends StatelessWidget {
  const _GuiaXiaomi({required this.onInicioAutomatico, required this.onAjustes});

  final VoidCallback onInicioAutomatico;
  final VoidCallback onAjustes;

  @override
  Widget build(BuildContext context) {
    const estiloPaso = TextStyle(color: AppColors.text2, fontSize: 13, fontWeight: FontWeight.w600, height: 1.45);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'En Xiaomi, activa esto para que lleguen los avisos',
            style: TextStyle(color: AppColors.text, fontSize: 13.5, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          const Text('1. Inicio automático: actívalo para SubTrack.', style: estiloPaso),
          const SizedBox(height: 6),
          const Text(
            '2. Ahorro de batería: en los ajustes de la app, entra a "Ahorro de batería" '
            'y elige "Sin restricciones".',
            style: estiloPaso,
          ),
          const SizedBox(height: 12),
          AppBotonSecundario(texto: 'Abrir Inicio automático', onPressed: onInicioAutomatico),
          const SizedBox(height: 9),
          AppBotonSecundario(texto: 'Abrir ajustes de la app', onPressed: onAjustes),
        ],
      ),
    );
  }
}
