import 'package:flutter_suscripciones/models/usuario.dart';
import 'package:flutter_suscripciones/services/api_client.dart';
import 'package:flutter_suscripciones/services/auth_service.dart';

/// AuthService falso para los tests: no usa red ni almacenamiento.
/// Si [error] tiene valor, login y registro fallan con ese mensaje.
class FakeAuthService implements AuthService {
  FakeAuthService({this.error, this.dias = 3});

  final String? error;
  int dias;
  Usuario? _usuario;

  /// Datos recibidos en la última llamada (para verificarlos en el test).
  List<String>? ultimaLlamada;

  Future<Usuario> _responder(String nombre, String correo) async {
    await Future.delayed(const Duration(seconds: 1)); // simula la red
    if (error != null) throw ApiException(error!);
    return _usuario = Usuario(id: 1, nombre: nombre, correo: correo);
  }

  @override
  Usuario? get usuario => _usuario;

  @override
  Future<Usuario> login(String correo, String password) {
    ultimaLlamada = [correo, password];
    return _responder('Ana', correo);
  }

  @override
  Future<Usuario> registro(String nombre, String correo, String password) {
    ultimaLlamada = [nombre, correo, password];
    return _responder(nombre, correo);
  }

  @override
  Future<Usuario?> me() async => _usuario;

  @override
  Future<bool> haySesionActiva() async => _usuario != null;

  @override
  Future<void> cerrarSesion() async => _usuario = null;

  @override
  Future<int> obtenerDiasAnticipacion() async => dias;

  @override
  Future<int> guardarDiasAnticipacion(int dias) async => this.dias = dias;

  @override
  Future<void> eliminarCuenta(String password) async => _usuario = null;
}
