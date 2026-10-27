import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../Common/Routers.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../utils/validators.dart';
import '../widgets/app_feedback.dart';
import '../widgets/app_text_field.dart';
import '../widgets/auth_layout.dart';

/// Registro (pantalla 02 del diseño, modo "Crea tu cuenta"). Al terminar
/// continúa a la preferencia de recordatorio (pantalla 06).
class RegistroPage extends StatefulWidget {
  const RegistroPage({super.key, required this.authService});

  /// Se recibe por parámetro para poder usar uno falso en los tests.
  final AuthService authService;

  @override
  State<RegistroPage> createState() => _RegistroPageState();
}

class _RegistroPageState extends State<RegistroPage> {
  final _formKey = GlobalKey<FormState>();
  final _nombreCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmarCtrl = TextEditingController();

  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confirmarCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus(); // cierra el teclado
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);
    try {
      final usuario = await widget.authService.registro(
        _nombreCtrl.text,
        _emailCtrl.text,
        _passCtrl.text,
      );
      if (!mounted) return;
      mostrarToast(context, 'Hola, ${primerNombre(usuario.nombre)}');
      // El registro deja la sesión iniciada; sigue la preferencia de avisos.
      context.go(Routers.preferencias);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.mensaje; // banner rojo con el mensaje del servidor
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthLayout(
      formKey: _formKey,
      titulo: 'Crea tu cuenta',
      subtitulo: 'Con tu correo empezamos a ordenar tus cobros.',
      error: _error,
      cargando: _loading,
      boton: 'Crear cuenta',
      botonCargando: 'Creando cuenta…',
      onEnviar: _submit,
      enlace: '¿Ya tienes cuenta? Inicia sesión',
      // go: el login queda sobre la bienvenida (ver Routers).
      onEnlace: () => context.go(Routers.login),
      campos: [
        AppTextField(
          controller: _nombreCtrl,
          label: 'Nombre',
          hint: 'Tu nombre',
          keyboardType: TextInputType.name,
          textInputAction: TextInputAction.next,
          validator: Validators.nombre,
        ),
        AppTextField(
          controller: _emailCtrl,
          label: 'Correo',
          hint: 'tucorreo@ejemplo.com',
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          validator: Validators.email,
        ),
        AppTextField(
          controller: _passCtrl,
          label: 'Contraseña',
          hint: 'mínimo 6 caracteres',
          obscureText: true,
          textInputAction: TextInputAction.next,
          validator: Validators.password,
        ),
        AppTextField(
          controller: _confirmarCtrl,
          label: 'Confirmar contraseña',
          hint: 'repite la contraseña',
          obscureText: true,
          textInputAction: TextInputAction.done,
          validator: (v) => v != _passCtrl.text ? 'Las contraseñas no coinciden' : null,
          onFieldSubmitted: (_) {
            if (!_loading) _submit();
          },
        ),
      ],
    );
  }
}
