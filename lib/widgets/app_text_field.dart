import 'package:flutter/material.dart';

/// Campo de texto de la app. El estilo (relleno, bordes, colores)
/// viene de AppTheme.inputDecorationTheme, así que aquí no se repite.
class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.label,
    this.controller,
    this.validator,
    this.hint,
    this.icon,
    this.suffixIcon,
    this.keyboardType,
    this.textInputAction,
    this.onFieldSubmitted,
    this.onTap,
    this.obscureText = false,
    this.readOnly = false,
  });

  final String label;
  final TextEditingController? controller;
  final String? Function(String?)? validator;
  final String? hint;
  final IconData? icon;
  final Widget? suffixIcon;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onFieldSubmitted;

  /// Con [readOnly], sirve para abrir un selector (por ejemplo, de fecha).
  final VoidCallback? onTap;
  final bool obscureText;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      validator: validator,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      onFieldSubmitted: onFieldSubmitted,
      onTap: onTap,
      obscureText: obscureText,
      readOnly: readOnly,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: icon != null ? Icon(icon) : null,
        suffixIcon: suffixIcon,
      ),
    );
  }
}
