import 'package:flutter/material.dart';

import '../Common/AppTheme.dart';

/// Encabezado con degradado azul y esquinas inferiores redondeadas, como en
/// las pantallas del diseño. Respeta la barra de estado del teléfono.
class AppHeader extends StatelessWidget {
  const AppHeader({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 22),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: AppColors.header,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(26)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// Botón "Volver" translúcido de los encabezados.
class AppBotonVolver extends StatelessWidget {
  const AppBotonVolver({super.key, required this.onPressed, this.texto = 'Volver'});

  final VoidCallback onPressed;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.chevron_left, size: 18),
        label: Text(texto),
        style: TextButton.styleFrom(
          foregroundColor: AppColors.textSoft,
          backgroundColor: Colors.white.withValues(alpha: 0.1),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.22)),
          shape: const StadiumBorder(),
          padding: const EdgeInsets.fromLTRB(8, 4, 14, 4),
          minimumSize: const Size(0, 34),
          textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

/// Título de sección en mayúsculas pequeñas ("FRECUENCIA", "GASTO...").
class AppEtiqueta extends StatelessWidget {
  const AppEtiqueta(this.texto, {super.key, this.color = AppColors.muted});

  final String texto;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      texto.toUpperCase(),
      style: TextStyle(
        color: color,
        fontSize: 11.5,
        fontWeight: FontWeight.w800,
        letterSpacing: 1,
      ),
    );
  }
}
