import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../Common/AppTheme.dart';
import '../Common/Routers.dart';
import '../models/usuario.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../widgets/app_botones.dart';
import '../widgets/app_card.dart';
import '../widgets/app_feedback.dart';
import '../widgets/app_header.dart';

/// Perfil y configuración (pantalla 14 del diseño, pestaña 4): días de
/// anticipación, cerrar sesión y eliminar la cuenta.
class PerfilPage extends StatefulWidget {
  const PerfilPage({super.key, required this.authService});

  final AuthService authService;

  @override
  State<PerfilPage> createState() => _PerfilPageState();
}

class _PerfilPageState extends State<PerfilPage> {
  Usuario? _usuario;
  int? _dias;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _usuario = widget.authService.usuario;
    _cargar();
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
    mostrarToast(context, 'Tu cuenta y todos tus datos fueron eliminados');
    context.go(Routers.login);
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
