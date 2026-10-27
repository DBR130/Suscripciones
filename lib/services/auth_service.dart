import '../models/usuario.dart';
import 'api_client.dart';

/// Autenticación y datos de la cuenta del usuario.
class AuthService {
  AuthService(this._api);

  final ApiClient _api;
  Usuario? _usuario;

  /// Usuario de la sesión actual (se llena al iniciar sesión o con [me]).
  Usuario? get usuario => _usuario;

  /// Inicia sesión y guarda el token. Lanza [ApiException] si falla.
  Future<Usuario> login(String correo, String password) {
    return _autenticar('/api/auth/login', {
      'correo': correo.trim(),
      'password': password,
    });
  }

  /// Crea la cuenta y deja la sesión iniciada. Lanza [ApiException] si falla.
  Future<Usuario> registro(String nombre, String correo, String password) {
    return _autenticar('/api/auth/registro', {
      'nombre': nombre.trim(),
      'correo': correo.trim(),
      'password': password,
    });
  }

  /// Datos del usuario del token guardado, o null si no hay sesión válida.
  /// Si el servidor rechaza el token (vencido o inválido), se borra.
  /// Lanza [ApiException] si no hay conexión.
  Future<Usuario?> me() async {
    if (await _api.leerToken() == null) return _usuario = null;
    try {
      final json = await _api.get('/api/auth/me');
      return _usuario = Usuario.fromJson(json['usuario'] as Map<String, dynamic>);
    } on ApiException catch (e) {
      if (e.statusCode == 401) return _usuario = null;
      rethrow;
    }
  }

  /// true si hay un token guardado y el servidor lo acepta.
  /// Sin conexión devuelve false para que la app abra en el inicio.
  Future<bool> haySesionActiva() async {
    try {
      return await me() != null;
    } on ApiException {
      return false;
    }
  }

  Future<void> cerrarSesion() {
    _usuario = null;
    return _api.borrarToken();
  }

  /// Días de anticipación global para los recordatorios.
  Future<int> obtenerDiasAnticipacion() async {
    final json = await _api.get('/api/usuarios/me/preferencias');
    return _dias(json);
  }

  Future<int> guardarDiasAnticipacion(int dias) async {
    final json = await _api.put('/api/usuarios/me/preferencias', {
      'dias_anticipacion_recordatorio': dias,
    });
    return _dias(json);
  }

  /// Elimina la cuenta y todos sus datos. Exige la contraseña.
  Future<void> eliminarCuenta(String password) async {
    await _api.delete('/api/usuarios/me', body: {'password': password});
    await cerrarSesion();
  }

  int _dias(Map<String, dynamic> json) {
    final preferencias = json['preferencias'] as Map<String, dynamic>;
    return preferencias['dias_anticipacion_recordatorio'] as int;
  }

  Future<Usuario> _autenticar(String ruta, Map<String, String> datos) async {
    final json = await _api.post(ruta, datos, autenticado: false);
    await _api.guardarToken(json['token'] as String);
    return _usuario = Usuario.fromJson(json['usuario'] as Map<String, dynamic>);
  }
}
