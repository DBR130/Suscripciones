import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../Common/Routers.dart';
import '../services/auth_service.dart';

/// Pantalla temporal: aquí irá el dashboard del mockup.
class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key, required this.authService});

  final AuthService authService;

  Future<void> _cerrarSesion(BuildContext context) async {
    await authService.cerrarSesion();
    if (!context.mounted) return;
    context.go(Routers.login);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: 'Cerrar sesión',
            icon: const Icon(Icons.logout),
            onPressed: () => _cerrarSesion(context),
          ),
        ],
      ),
      body: const Center(child: Text('Resumen')),
    );
  }
}
