import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

/// Error que las vistas muestran tal cual en un SnackBar.
class ApiException implements Exception {
  const ApiException(this.mensaje, {this.statusCode});

  final String mensaje;

  /// Código HTTP de la respuesta, o null si no hubo conexión.
  final int? statusCode;

  @override
  String toString() => mensaje;
}

/// Cliente HTTP compartido por todos los servicios: URL base, token guardado
/// y conversión de errores en [ApiException].
///
/// La URL base se cambia al ejecutar la app:
///   flutter run --dart-define=API_URL=http://192.168.1.50:3000
/// Por defecto usa 10.0.2.2, que es el "localhost" del PC visto desde el
/// emulador de Android.
class ApiClient {
  ApiClient({http.Client? client, FlutterSecureStorage? storage})
      : _client = client ?? http.Client(),
        _storage = storage ?? const FlutterSecureStorage();

  static const String baseUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'http://10.0.2.2:3000',
  );

  static const String errorConexion = 'No se pudo conectar con el servidor';
  static const String errorSesionExpirada =
      'Tu sesión expiró. Inicia sesión de nuevo.';

  static const String _tokenKey = 'auth_token';
  static const Duration _timeout = Duration(seconds: 10);

  final http.Client _client;
  final FlutterSecureStorage _storage;

  /// Se llama cuando el servidor rechaza el token en una petición con sesión
  /// (por ejemplo, venció). main.dart lo usa para volver al login.
  void Function()? onSesionExpirada;

  Future<String?> leerToken() => _storage.read(key: _tokenKey);

  Future<void> guardarToken(String token) =>
      _storage.write(key: _tokenKey, value: token);

  Future<void> borrarToken() => _storage.delete(key: _tokenKey);

  Future<Map<String, dynamic>> get(
    String ruta, {
    Map<String, String>? query,
    bool autenticado = true,
  }) =>
      _enviar('GET', ruta, query: query, autenticado: autenticado);

  Future<Map<String, dynamic>> post(
    String ruta,
    Object body, {
    bool autenticado = true,
  }) =>
      _enviar('POST', ruta, body: body, autenticado: autenticado);

  Future<Map<String, dynamic>> put(String ruta, Object body) =>
      _enviar('PUT', ruta, body: body);

  Future<Map<String, dynamic>> patch(String ruta, Object body) =>
      _enviar('PATCH', ruta, body: body);

  Future<Map<String, dynamic>> delete(String ruta, {Object? body}) =>
      _enviar('DELETE', ruta, body: body);

  /// Hace la petición y devuelve el JSON de la respuesta ({} si viene vacía).
  /// Lanza [ApiException] con el mensaje del servidor o de conexión.
  Future<Map<String, dynamic>> _enviar(
    String metodo,
    String ruta, {
    Object? body,
    Map<String, String>? query,
    bool autenticado = true,
  }) async {
    final request = http.Request(
      metodo,
      Uri.parse('$baseUrl$ruta').replace(queryParameters: query),
    );
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    if (autenticado) {
      final token = await leerToken();
      if (token == null) await _sesionExpirada();
      request.headers['Authorization'] = 'Bearer $token';
    }

    final http.Response res;
    try {
      final streamed = await _client.send(request).timeout(_timeout);
      res = await http.Response.fromStream(streamed).timeout(_timeout);
    } on http.ClientException {
      throw const ApiException(errorConexion);
    } on TimeoutException {
      throw const ApiException(errorConexion);
    }

    if (autenticado && res.statusCode == 401) await _sesionExpirada();
    return _decodificar(res);
  }

  Future<Never> _sesionExpirada() async {
    await borrarToken();
    onSesionExpirada?.call();
    throw const ApiException(errorSesionExpirada, statusCode: 401);
  }

  /// Devuelve el JSON si la respuesta es 2xx; si no, lanza el mensaje
  /// de error que envió el servidor ({"error": "..."}).
  Map<String, dynamic> _decodificar(http.Response res) {
    final exito = res.statusCode >= 200 && res.statusCode < 300;
    if (exito && res.bodyBytes.isEmpty) return {}; // 204 sin contenido

    Object? cuerpo;
    try {
      cuerpo = jsonDecode(utf8.decode(res.bodyBytes));
    } on FormatException {
      cuerpo = null; // la respuesta no era JSON
    }
    final json = cuerpo is Map<String, dynamic> ? cuerpo : null;

    if (exito && json != null) return json;
    final error = json?['error'];
    throw ApiException(
      error is String ? error : 'Error del servidor (${res.statusCode})',
      statusCode: res.statusCode,
    );
  }
}
