import 'package:flutter/material.dart';

import '../Common/AppTheme.dart';

/// Campo de texto de la app con la etiqueta ARRIBA en mayúsculas, como en
/// design/subtrack-pantallas.md. El estilo de la caja (relleno, bordes,
/// colores) viene de AppTheme.inputDecorationTheme.
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: AppColors.muted,
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 7),
        TextFormField(
          controller: controller,
          validator: validator,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          onFieldSubmitted: onFieldSubmitted,
          onTap: onTap,
          obscureText: obscureText,
          readOnly: readOnly,
          style: const TextStyle(
            color: AppColors.text,
            fontSize: 14.5,
            fontWeight: FontWeight.w600,
          ),
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: icon != null ? Icon(icon) : null,
            suffixIcon: suffixIcon,
          ),
        ),
      ],
    );
  }
}
