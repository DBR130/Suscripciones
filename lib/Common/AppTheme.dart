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

  // Colores adicionales de design/SubTrack_Simulacion.html.
  static const Color link = Color(0xFF7DB3FF);
  static const Color textSoft = Color(0xFFD6E3FB); // texto de botones secundarios
  static const Color mutedOnGradient = Color(0xFFA6B6D0);
  static const Color lineStrong = Color(0xFF2C3B58); // borde de botones/pills
  static const Color divider = Color(0xFF1E2A40);
  static const Color panel = Color(0xFF0E1626); // barra inferior fija
  static const Color chip = Color(0xFF1A263D);
  static const Color avatar = Color(0xFF1C2942);
  static const Color cardFlag = Color(0xFF17203A); // tarjeta resaltada
  static const Color flagBlueBg = Color(0xFF16273F);
  static const Color flagBlueText = Color(0xFFA9CCFF);
  static const Color amber = Color(0xFFFBD167); // avisos y acciones de cancelar
  static const Color amberStrong = Color(0xFFFCD34D);
  static const Color amberBorder = Color(0x73FBBF24); // rgba(251,191,36,.45)
  static const Color amberBg = Color(0x21FBBF24); // rgba(251,191,36,.13)
  static const Color errorSoft = Color(0xFFFCA5A5); // texto del banner de error
  static const Color errorBg = Color(0x1FF87171); // rgba(248,113,113,.12)
  static const Color errorLine = Color(0x73F87171); // rgba(248,113,113,.45)
  static const Color danger = Color(0xFFDC2626); // botón destructivo del diálogo

  /// Degradado de los encabezados (dashboard, detalle, perfil...).
  static const LinearGradient header = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0D1526), Color(0xFF152443), Color(0xFF1E3A6E)],
    stops: [0, 0.55, 1],
  );
}

/// Tema de la app: aquí se define una sola vez cómo se ven
/// los campos, los botones y los SnackBar en todas las vistas.
class AppTheme {
  AppTheme._();

  static OutlineInputBorder _border(Color color, [double width = 1]) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(12), // inputs del diseño
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
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
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
        fontSize: 12,
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
    // "Toast" del diseño: tarjeta flotante con borde (ver mostrarToast).
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.surface,
      contentTextStyle: const TextStyle(
        color: AppColors.text,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.lineStrong),
      ),
    ),
  );
}
