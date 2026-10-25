import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';

import 'Common/AppTheme.dart';
import 'Common/Routers.dart';
import 'services/api_client.dart';
import 'services/auth_service.dart';
import 'services/suscripcion_service.dart';

Future<void> main() async {
  // Necesario para usar plugins (secure storage) antes de runApp.
  WidgetsFlutterBinding.ensureInitialized();

  // Un solo ApiClient (URL base y token) compartido por todos los servicios.
  final api = ApiClient();
  final authService = AuthService(api);
  final suscripcionService = SuscripcionService(api);

  // Si hay un token guardado y el servidor lo acepta, se abre directo el resumen.
  final haySesion = await authService.haySesionActiva();

  final router = Routers.crear(
    authService,
    suscripcionService,
    initialLocation: haySesion ? Routers.dashboard : Routers.home,
  );
  // Si el token vence mientras se usa la app, se vuelve al login.
  api.onSesionExpirada = () => router.go(Routers.login);

  runApp(MyApp(router: router));
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
      // Textos de Material (calendario, botones) en español de Colombia.
      locale: const Locale('es', 'CO'),
      supportedLocales: const [Locale('es', 'CO'), Locale('es')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
    );
  }
}
