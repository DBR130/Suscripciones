import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'Common/AppTheme.dart';
import 'Common/Routers.dart';
import 'services/auth_service.dart';

Future<void> main() async {
  // Necesario para usar plugins (secure storage) antes de runApp.
  WidgetsFlutterBinding.ensureInitialized();

  // Si hay un token guardado y el servidor lo acepta, se abre directo el resumen.
  final authService = AuthService();
  final haySesion = await authService.haySesionActiva();

  runApp(MyApp(
    router: Routers.crear(
      authService,
      initialLocation: haySesion ? Routers.dashboard : Routers.home,
    ),
  ));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.router});

  final GoRouter router;

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'SubTrack',
      theme: AppTheme.dark,
      routerConfig: router,
    );
  }
}
