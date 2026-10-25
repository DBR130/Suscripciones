import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../Common/Routers.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../utils/validators.dart';
import '../widgets/app_feedback.dart';
import '../widgets/app_text_field.dart';
import '../widgets/auth_layout.dart';

/// Login (pantalla 02 del diseño, modo "Hola de nuevo").
class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.authService});

  /// Se recibe por parámetro para poder usar uno falso en los tests.
  final AuthService authService;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  bool _loading = false;
  bool _verPassword = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus(); // cierra el teclado
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);
    try {
      final usuario = await widget.authService.login(_emailCtrl.text, _passCtrl.text);
      if (!mounted) return;
      mostrarToast(context, 'Hola, ${primerNombre(usuario.nombre)}');
      // go (no push): reemplaza el historial y "atrás" no vuelve al login.
      context.go(Routers.dashboard);
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
      titulo: 'Hola de nuevo',
      subtitulo: 'Entra para ver tus próximos cobros.',
      error: _error,
      cargando: _loading,
      boton: 'Entrar',
      botonCargando: 'Entrando…',
      onEnviar: _submit,
      enlace: 'No tengo cuenta, quiero registrarme',
      // go (no push): registro queda sobre la bienvenida, no sobre el login.
      onEnlace: () => context.go(Routers.registro),
      campos: [
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
          hint: 'tu contraseña',
          obscureText: !_verPassword,
          textInputAction: TextInputAction.done,
          validator: Validators.password,
          onFieldSubmitted: (_) {
            if (!_loading) _submit();
          },
          suffixIcon: IconButton(
            tooltip: _verPassword ? 'Ocultar contraseña' : 'Mostrar contraseña',
            icon: Icon(_verPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
            onPressed: () => setState(() => _verPassword = !_verPassword),
          ),
        ),
      ],
    );
  }
}
