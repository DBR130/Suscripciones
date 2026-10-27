import 'package:flutter/material.dart';

import '../Common/AppTheme.dart';
import 'app_feedback.dart';
import 'app_marca.dart';

/// Estructura común de login y registro (pantalla 02 del diseño): marca,
/// título, banner de error del servidor, campos, botón con estado de carga,
/// enlace al otro modo y pie legal abajo.
class AuthLayout extends StatelessWidget {
  const AuthLayout({
    super.key,
    required this.formKey,
    required this.titulo,
    required this.subtitulo,
    required this.campos,
    required this.boton,
    required this.botonCargando,
    required this.cargando,
    required this.onEnviar,
    required this.enlace,
    required this.onEnlace,
    this.error,
  });

  final GlobalKey<FormState> formKey;
  final String titulo;
  final String subtitulo;
  final List<Widget> campos;
  final String boton;

  /// Texto del botón mientras espera al servidor ("Entrando…").
  final String botonCargando;
  final bool cargando;
  final VoidCallback onEnviar;
  final String enlace;
  final VoidCallback onEnlace;

  /// Mensaje del servidor para el banner rojo.
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        // SliverFillRemaining: el pie legal queda abajo si sobra espacio, y
        // todo hace scroll si no cabe (pantallas pequeñas o con teclado).
        child: CustomScrollView(
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 26, 24, 24),
                child: Form(
                  key: formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Align(alignment: Alignment.centerLeft, child: AppMarca.fila()),
                      const SizedBox(height: 26),
                      Text(
                        titulo,
                        style: const TextStyle(
                          color: AppColors.text,
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.6,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        subtitulo,
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 22),
                      if (error != null) ...[BannerError(error!), const SizedBox(height: 14)],
                      for (final (i, campo) in campos.indexed) ...[
                        if (i > 0) const SizedBox(height: 14),
                        campo,
                      ],
                      const SizedBox(height: 18),
                      FilledButton(
                        onPressed: cargando ? null : onEnviar,
                        child: cargando
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(botonCargando),
                                ],
                              )
                            : Text(boton),
                      ),
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: cargando ? null : onEnlace,
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.link,
                          shape: const StadiumBorder(),
                          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                        ),
                        child: Text(enlace, textAlign: TextAlign.center),
                      ),
                      const Spacer(),
                      const Padding(
                        padding: EdgeInsets.only(top: 20),
                        child: Text(
                          'Al continuar aceptas el tratamiento de datos descrito en la política de '
                          'privacidad (Habeas Data). Puedes eliminar tu cuenta y todos tus datos en '
                          'cualquier momento.',
                          style: TextStyle(color: AppColors.muted, fontSize: 11, height: 1.55),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Hola, Daniela": el primer nombre para el toast de bienvenida.
String primerNombre(String nombre) {
  final partes = nombre.trim().split(RegExp(r'\s+'));
  return partes.isEmpty ? nombre : partes.first;
}
