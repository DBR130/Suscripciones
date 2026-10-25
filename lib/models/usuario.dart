/// Usuario autenticado, tal como lo devuelve el backend.
class Usuario {
  const Usuario({required this.id, required this.nombre, required this.correo});

  final int id;
  final String nombre;
  final String correo;

  factory Usuario.fromJson(Map<String, dynamic> json) {
    return Usuario(
      id: json['id'] as int,
      nombre: json['nombre'] as String,
      correo: json['correo'] as String,
    );
  }

  /// "Daniela Bustos" → "DB"; "Ana" → "A".
  String get iniciales {
    final palabras =
        nombre.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    return palabras.take(2).map((p) => p[0].toUpperCase()).join();
  }
}
