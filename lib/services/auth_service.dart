import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../models/usuario.dart';

/// Error que las vistas muestran tal cual en un SnackBar.
class AuthException implements Exception {
  const AuthException(this.mensaje);

  final String mensaje;

  @override
  String toString() => mensaje;
}

/// Llamadas de autenticación al backend y manejo del token.
///
/// La URL base se cambia al ejecutar la app:
///   flutter run --dart-define=API_URL=http://192.168.1.50:3000
/// Por defecto usa 10.0.2.2, que es el "localhost" del PC visto desde el
/// emulador de Android.
class AuthService {
  AuthService({http.Client? client, FlutterSecureStorage? storage})
      : _client = client ?? http.Client(),
        _storage = storage ?? const FlutterSecureStorage();

  static const String baseUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'http://10.0.2.2:3000',
  );

  static const String _tokenKey = 'auth_token';
  static const Duration _timeout = Duration(seconds: 10);
  static const String errorConexion = 'No se pudo conectar con el servidor';

  final http.Client _client;
  final FlutterSecureStorage _storage;

  /// Inicia sesión y guarda el token. Lanza [AuthException] si falla.
  Future<Usuario> login(String correo, String password) {
    return _autenticar('/api/auth/login', {
      'correo': correo.trim(),
      'password': password,
    });
  }

  /// Crea la cuenta y deja la sesión iniciada. Lanza [AuthException] si falla.
  Future<Usuario> registro(String nombre, String correo, String password) {
    return _autenticar('/api/auth/registro', {
      'nombre': nombre.trim(),
      'correo': correo.trim(),
      'password': password,
    });
  }

  /// Datos del usuario del token guardado, o null si no hay sesión válida.
  /// Si el servidor rechaza el token (vencido o inválido), se borra.
  /// Lanza [AuthException] si no hay conexión.
  Future<Usuario?> me() async {
    final token = await _storage.read(key: _tokenKey);
    if (token == null) return null;

    final res = await _enviar(
      () => _client.get(
        Uri.parse('$baseUrl/api/auth/me'),
        headers: {'Authorization': 'Bearer $token'},
      ),
    );
    if (res.statusCode == 401) {
      await cerrarSesion();
      return null;
    }
    final json = _decodificar(res);
    return Usuario.fromJson(json['usuario'] as Map<String, dynamic>);
  }

  /// true si hay un token guardado y el servidor lo acepta.
  /// Sin conexión devuelve false para que la app abra en el inicio.
  Future<bool> haySesionActiva() async {
    try {
      return await me() != null;
    } on AuthException {
      return false;
    }
  }

  Future<void> cerrarSesion() => _storage.delete(key: _tokenKey);

  Future<Usuario> _autenticar(String ruta, Map<String, String> datos) async {
    final res = await _enviar(
      () => _client.post(
        Uri.parse('$baseUrl$ruta'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(datos),
      ),
    );
    final json = _decodificar(res);
    await _storage.write(key: _tokenKey, value: json['token'] as String);
    return Usuario.fromJson(json['usuario'] as Map<String, dynamic>);
  }

  /// Ejecuta la petición y convierte los fallos de red en [AuthException].
  Future<http.Response> _enviar(Future<http.Response> Function() peticion) async {
    try {
      return await peticion().timeout(_timeout);
    } on http.ClientException {
      throw const AuthException(errorConexion);
    } on TimeoutException {
      throw const AuthException(errorConexion);
    }
  }

  /// Devuelve el JSON si la respuesta es 2xx; si no, lanza el mensaje
  /// de error que envió el servidor ({"error": "..."}).
  Map<String, dynamic> _decodificar(http.Response res) {
    Object? cuerpo;
    try {
      cuerpo = jsonDecode(utf8.decode(res.bodyBytes));
    } on FormatException {
      cuerpo = null; // la respuesta no era JSON
    }
    final json = cuerpo is Map<String, dynamic> ? cuerpo : null;

    if (res.statusCode >= 200 && res.statusCode < 300 && json != null) {
      return json;
    }
    final error = json?['error'];
    throw AuthException(
      error is String ? error : 'Error del servidor (${res.statusCode})',
    );
  }
}
