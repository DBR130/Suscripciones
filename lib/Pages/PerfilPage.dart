import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../Common/AppTheme.dart';
import '../Common/Routers.dart';
import '../models/usuario.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../widgets/app_botones.dart';
import '../widgets/app_card.dart';
import '../widgets/app_header.dart';
import '../widgets/app_text_field.dart';

/// Perfil y configuración (pantalla 14 del diseño): días de anticipación,
/// cerrar sesión y eliminar la cuenta.
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
      _mostrar(e.mensaje);
    }
  }

  void _mostrar(String mensaje) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensaje)));
  }

  Future<void> _cambiarDias(int dias) async {
    final anterior = _dias;
    setState(() {
      _dias = dias;
      _guardando = true;
    });
    try {
      await widget.authService.guardarDiasAnticipacion(dias);
      _mostrar('Te avisaremos ${dias == 1 ? '1 día' : '$dias días'} antes de cada cobro');
    } on ApiException catch (e) {
      if (mounted) setState(() => _dias = anterior);
      _mostrar(e.mensaje);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<void> _cerrarSesion() async {
    await widget.authService.cerrarSesion();
    if (mounted) context.go(Routers.login);
  }

  Future<void> _eliminarCuenta() async {
    final eliminada = await showDialog<bool>(
      context: context,
      builder: (_) => _EliminarCuentaDialog(authService: widget.authService),
    );
    if (eliminada != true || !mounted) return;
    _mostrar('Tu cuenta y todos tus datos fueron eliminados');
    context.go(Routers.login);
  }

  @override
  Widget build(BuildContext context) {
    final u = _usuario;
    return Scaffold(
      body: Column(
        children: [
          AppHeader(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppBotonVolver(onPressed: () => context.pop()),
                const SizedBox(height: 14),
                Row(
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
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
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
                        'Preferencia global. Puedes cambiarla por suscripción.',
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
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Agregar suscripción manual',
                      style: TextStyle(color: AppColors.text, fontSize: 13.5, fontWeight: FontWeight.w700),
                    ),
                    trailing: const Icon(Icons.chevron_right, color: AppColors.muted),
                    onTap: () => context.push(Routers.nuevaSuscripcion),
                  ),
                ),
                const SizedBox(height: 18),
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

/// Pide la contraseña y elimina la cuenta. Devuelve true si se eliminó.
/// El error (contraseña incorrecta) se muestra dentro del diálogo.
class _EliminarCuentaDialog extends StatefulWidget {
  const _EliminarCuentaDialog({required this.authService});

  final AuthService authService;

  @override
  State<_EliminarCuentaDialog> createState() => _EliminarCuentaDialogState();
}

class _EliminarCuentaDialogState extends State<_EliminarCuentaDialog> {
  final _formKey = GlobalKey<FormState>();
  final _passCtrl = TextEditingController();
  bool _eliminando = false;
  String? _error;

  @override
  void dispose() {
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _eliminar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _eliminando = true;
      _error = null;
    });
    try {
      await widget.authService.eliminarCuenta(_passCtrl.text);
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _eliminando = false;
          _error = e.mensaje;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Text('Eliminar cuenta'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Se borrarán tu cuenta, tus suscripciones y todo tu historial. '
              'Esta acción no se puede deshacer.',
              style: TextStyle(color: AppColors.muted, height: 1.4),
            ),
            const SizedBox(height: 16),
            AppTextField(
              controller: _passCtrl,
              label: 'Contraseña',
              icon: Icons.lock_outline,
              obscureText: true,
              validator: (v) => v == null || v.isEmpty ? 'Ingresa tu contraseña' : null,
              onFieldSubmitted: (_) {
                if (!_eliminando) _eliminar();
              },
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.w600),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _eliminando ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        TextButton(
          onPressed: _eliminando ? null : _eliminar,
          style: TextButton.styleFrom(foregroundColor: AppColors.error),
          child: Text(_eliminando ? 'Eliminando…' : 'Eliminar'),
        ),
      ],
    );
  }
}
