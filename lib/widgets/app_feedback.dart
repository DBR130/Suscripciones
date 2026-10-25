import 'package:flutter/material.dart';

import '../Common/AppTheme.dart';
import 'app_text_field.dart';

/// Toast del diseño: tarjeta flotante con ✓ que dura 2,4 s.
void mostrarToast(BuildContext context, String mensaje) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        duration: const Duration(milliseconds: 2400),
        content: Row(
          children: [
            const Icon(Icons.check, size: 18, color: AppColors.accent),
            const SizedBox(width: 10),
            Expanded(child: Text(mensaje)),
          ],
        ),
      ),
    );
}

/// Banner rojo con el mensaje de error del servidor.
class BannerError extends StatelessWidget {
  const BannerError(this.mensaje, {super.key});

  final String mensaje;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.errorBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.errorLine),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 18, color: AppColors.errorSoft),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              mensaje,
              style: const TextStyle(
                color: AppColors.errorSoft,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Hoja inferior de confirmación del diseño (título, texto, botón rojo y
/// "No, volver"). Devuelve true si el usuario confirma.
Future<bool> confirmarAccion(
  BuildContext context, {
  required String titulo,
  required String texto,
  required String boton,
}) async {
  final ok = await showModalBottomSheet<bool>(
    context: context,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0xB8050912), // rgba(5,9,18,.72)
    builder: (context) => _HojaConfirmacion(
      titulo: titulo,
      texto: texto,
      boton: boton,
      onConfirmar: () async => Navigator.pop(context, true),
    ),
  );
  return ok ?? false;
}

/// Como [confirmarAccion], pero pide la contraseña y ejecuta [accion] con
/// ella. Si [accion] lanza un error, se muestra en la hoja y no se cierra.
/// Devuelve true si la acción terminó bien.
Future<bool> confirmarConContrasena(
  BuildContext context, {
  required String titulo,
  required String texto,
  required String boton,
  required Future<void> Function(String password) accion,
  required String Function(Object error) mensajeDeError,
}) async {
  final ok = await showModalBottomSheet<bool>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0xB8050912),
    builder: (context) => _HojaConfirmacion(
      titulo: titulo,
      texto: texto,
      boton: boton,
      pedirContrasena: true,
      accion: accion,
      mensajeDeError: mensajeDeError,
    ),
  );
  return ok ?? false;
}

class _HojaConfirmacion extends StatefulWidget {
  const _HojaConfirmacion({
    required this.titulo,
    required this.texto,
    required this.boton,
    this.onConfirmar,
    this.pedirContrasena = false,
    this.accion,
    this.mensajeDeError,
  });

  final String titulo;
  final String texto;
  final String boton;
  final Future<void> Function()? onConfirmar;
  final bool pedirContrasena;
  final Future<void> Function(String password)? accion;
  final String Function(Object error)? mensajeDeError;

  @override
  State<_HojaConfirmacion> createState() => _HojaConfirmacionState();
}

class _HojaConfirmacionState extends State<_HojaConfirmacion> {
  final _formKey = GlobalKey<FormState>();
  final _passCtrl = TextEditingController();
  bool _ocupado = false;
  String? _error;

  @override
  void dispose() {
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _confirmar() async {
    if (!widget.pedirContrasena) {
      await widget.onConfirmar!();
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _ocupado = true;
      _error = null;
    });
    try {
      await widget.accion!(_passCtrl.text);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _ocupado = false;
        _error = widget.mensajeDeError!(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Sube la hoja cuando aparece el teclado.
      padding: EdgeInsets.fromLTRB(12, 0, 12, 12 + MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppColors.lineStrong),
          ),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.titulo,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  widget.texto,
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                    height: 1.5,
                  ),
                ),
                if (widget.pedirContrasena) ...[
                  const SizedBox(height: 14),
                  AppTextField(
                    controller: _passCtrl,
                    label: 'Contraseña',
                    hint: 'tu contraseña',
                    obscureText: true,
                    validator: (v) => v == null || v.isEmpty ? 'Ingresa tu contraseña' : null,
                    onFieldSubmitted: (_) {
                      if (!_ocupado) _confirmar();
                    },
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  BannerError(_error!),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _ocupado ? null : _confirmar,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.danger,
                    disabledBackgroundColor: AppColors.danger.withValues(alpha: 0.6),
                  ),
                  child: _ocupado
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Text(widget.boton),
                ),
                const SizedBox(height: 4),
                TextButton(
                  onPressed: _ocupado ? null : () => Navigator.pop(context, false),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.muted,
                    minimumSize: const Size.fromHeight(44),
                    textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                  child: const Text('No, volver'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
