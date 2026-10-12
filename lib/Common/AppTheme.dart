import 'package:flutter/material.dart';

/// Paleta del mockup 07-flat-azul-oscuro.html.
class AppColors {
  AppColors._();

  static const Color bg = Color(0xFF0B1220); // --bg
  static const Color surface = Color(0xFF141D2F); // --surface
  static const Color line = Color(0xFF243149); // --line
  static const Color text = Color(0xFFE9EFFA); // --text
  static const Color muted = Color(0xFF9AAAC4); // --muted
  static const Color accent = Color(0xFF60A5FA); // --accent
  static const Color primary = Color(0xFF2563EB); // --btn-bg / --mark-bg
  static const Color error = Color(0xFFF87171);
}

/// Tema de la app: aquí se define una sola vez cómo se ven
/// los campos, los botones y los SnackBar en todas las vistas.
class AppTheme {
  AppTheme._();

  static OutlineInputBorder _border(Color color, [double width = 1]) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(14), // --radius
      borderSide: BorderSide(color: color, width: width),
    );
  }

  static final ThemeData dark = ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.bg,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.primary,
      onPrimary: Colors.white,
      secondary: AppColors.accent,
      surface: AppColors.surface,
      onSurface: AppColors.text,
      error: AppColors.error,
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: AppColors.accent,
      selectionColor: Color(0x5560A5FA),
      selectionHandleColor: AppColors.accent,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      labelStyle: const TextStyle(
        color: AppColors.muted,
        fontWeight: FontWeight.w500,
      ),
      // El label flotante cambia de color: rojo con error, azul con foco.
      floatingLabelStyle: WidgetStateTextStyle.resolveWith((states) {
        if (states.contains(WidgetState.error)) {
          return const TextStyle(color: AppColors.error);
        }
        if (states.contains(WidgetState.focused)) {
          return const TextStyle(color: AppColors.accent);
        }
        return const TextStyle(color: AppColors.muted);
      }),
      hintStyle: TextStyle(color: AppColors.muted.withValues(alpha: 0.6)),
      prefixIconColor: AppColors.muted,
      suffixIconColor: AppColors.muted,
      errorStyle: const TextStyle(
        color: AppColors.error,
        fontWeight: FontWeight.w600,
      ),
      enabledBorder: _border(AppColors.line),
      focusedBorder: _border(AppColors.accent, 1.5),
      errorBorder: _border(AppColors.error),
      focusedErrorBorder: _border(AppColors.error, 1.5),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.6),
        disabledForegroundColor: Colors.white,
        minimumSize: const Size.fromHeight(52),
        shape: const StadiumBorder(), // botón píldora del mockup
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: AppColors.surface,
      contentTextStyle: TextStyle(color: AppColors.text),
      behavior: SnackBarBehavior.floating,
    ),
  );
}
