/// Validadores reutilizables para los formularios.
/// Devuelven el mensaje de error, o null si el valor es válido.
class Validators {
  Validators._();

  static String? nombre(String? value) {
    if (value == null || value.trim().isEmpty) return 'Ingresa tu nombre';
    return null;
  }

  static String? email(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return 'Ingresa tu correo electrónico';
    final regex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (!regex.hasMatch(email)) return 'Correo no válido';
    return null;
  }

  static String? password(String? value) {
    if (value == null || value.isEmpty) return 'Ingresa tu contraseña';
    if (value.length < 6) return 'Mínimo 6 caracteres';
    return null;
  }
}
