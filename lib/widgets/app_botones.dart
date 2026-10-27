import 'package:flutter/material.dart';

import '../Common/AppTheme.dart';

/// Botón píldora con borde (acciones secundarias). Con [ambar] se usa para
/// acciones de cancelar o eliminar, como en el diseño.
class AppBotonSecundario extends StatelessWidget {
  const AppBotonSecundario({
    super.key,
    required this.texto,
    required this.onPressed,
    this.ambar = false,
    this.icon,
  });

  final String texto;
  final VoidCallback? onPressed;
  final bool ambar;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final style = OutlinedButton.styleFrom(
      foregroundColor: ambar ? AppColors.amber : AppColors.textSoft,
      side: BorderSide(
        color: ambar ? AppColors.amberBorder : AppColors.lineStrong,
        width: ambar ? 1.5 : 1,
      ),
      shape: const StadiumBorder(),
      minimumSize: const Size.fromHeight(46),
      textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
    );
    if (icon == null) {
      return OutlinedButton(onPressed: onPressed, style: style, child: Text(texto));
    }
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: style,
      icon: Icon(icon, size: 18),
      label: Text(texto),
    );
  }
}

/// Grupo de opciones en píldoras (frecuencia, moneda, días de aviso).
class AppPills<T> extends StatelessWidget {
  const AppPills({
    super.key,
    required this.opciones,
    required this.seleccion,
    required this.onChanged,
  });

  /// Pares (valor, texto).
  final List<(T, String)> opciones;
  final T? seleccion;
  final ValueChanged<T>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final (i, (valor, texto)) in opciones.indexed) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: _pill(valor, texto)),
        ],
      ],
    );
  }

  Widget _pill(T valor, String texto) {
    final activa = valor == seleccion;
    return Semantics(
      selected: activa,
      button: true,
      child: TextButton(
        onPressed: onChanged == null ? null : () => onChanged!(valor),
        style: TextButton.styleFrom(
          backgroundColor: activa ? AppColors.primary : Colors.transparent,
          foregroundColor: activa ? Colors.white : AppColors.textSoft,
          disabledForegroundColor: AppColors.muted,
          side: activa ? BorderSide.none : const BorderSide(color: AppColors.lineStrong),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
        ),
        child: Text(texto, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}

/// Botón con borde discontinuo ("+ Agregar suscripción manualmente").
class AppBotonPunteado extends StatelessWidget {
  const AppBotonPunteado({super.key, required this.texto, required this.onPressed});

  final String texto;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _BordePunteado(),
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: AppColors.textSoft,
          shape: const StadiumBorder(),
          minimumSize: const Size.fromHeight(46),
          textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
        ),
        child: Text(texto),
      ),
    );
  }
}

/// Dibuja el contorno de una píldora con trazos de 5 px y espacios de 4 px.
class _BordePunteado extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final contorno = Path()
      ..addRRect(RRect.fromRectAndRadius(rect.deflate(0.5), Radius.circular(size.height / 2)));
    final pincel = Paint()
      ..color = AppColors.lineStrong
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final metrica in contorno.computeMetrics()) {
      for (double d = 0; d < metrica.length; d += 9) {
        canvas.drawPath(metrica.extractPath(d, d + 5), pincel);
      }
    }
  }

  @override
  bool shouldRepaint(_BordePunteado oldDelegate) => false;
}
