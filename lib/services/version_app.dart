import 'package:package_info_plus/package_info_plus.dart';

/// "Versión 1.0.0 (1)", leída del paquete instalado (pubspec.yaml →
/// versionName y versionCode). null si no se puede leer (tests, web).
Future<String?> versionApp() async {
  try {
    final info = await PackageInfo.fromPlatform();
    return 'Versión ${info.version} (${info.buildNumber})';
  } catch (_) {
    return null;
  }
}
