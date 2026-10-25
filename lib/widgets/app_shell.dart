import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../Common/AppTheme.dart';
import '../Common/Routers.dart';

/// Barra de pestañas inferior de las pantallas con sesión (diseño: Resumen,
/// Suscripciones, Avisos, Perfil).
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  static const _pestanas = [
    (ruta: Routers.dashboard, icono: Icons.home_outlined, texto: 'Resumen'),
    (ruta: Routers.suscripciones, icono: Icons.format_list_bulleted, texto: 'Suscripciones'),
    (ruta: Routers.avisos, icono: Icons.notifications_none, texto: 'Avisos'),
    (ruta: Routers.perfil, icono: Icons.person_outline, texto: 'Perfil'),
  ];

  bool _activa(String ruta, String ubicacion) {
    // El detalle (/suscripcion/:id) pertenece a la pestaña Suscripciones.
    if (ruta == Routers.suscripciones) {
      return ubicacion.startsWith(Routers.suscripciones) || ubicacion.startsWith('/suscripcion/');
    }
    return ubicacion.startsWith(ruta);
  }

  @override
  Widget build(BuildContext context) {
    // Ruta visible (también las abiertas con push, como el detalle), para
    // marcar la pestaña activa.
    final delegado = GoRouter.of(context).routerDelegate;
    return ListenableBuilder(
      listenable: delegado,
      builder: (context, _) => _construir(context, delegado.currentConfiguration.uri.path),
    );
  }

  Widget _construir(BuildContext context, String ubicacion) {
    return Scaffold(
      body: child,
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppColors.panel,
          border: Border(top: BorderSide(color: AppColors.divider)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 9, 6, 8),
            child: Row(
              children: [
                for (final p in _pestanas)
                  Expanded(
                    child: _Pestana(
                      icono: p.icono,
                      texto: p.texto,
                      activa: _activa(p.ruta, ubicacion),
                      onTap: () => context.go(p.ruta),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Pestana extends StatelessWidget {
  const _Pestana({
    required this.icono,
    required this.texto,
    required this.activa,
    required this.onTap,
  });

  final IconData icono;
  final String texto;
  final bool activa;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = activa ? AppColors.link : AppColors.muted;
    return Semantics(
      selected: activa,
      button: true,
      child: InkResponse(
        onTap: onTap,
        radius: 40,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icono, size: 20, color: color),
              const SizedBox(height: 4),
              Text(
                texto,
                style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
