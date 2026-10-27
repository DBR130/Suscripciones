import 'package:flutter/material.dart';

import '../Common/AppTheme.dart';

/// Tarjeta del diseño. Con [destacada] usa el borde ámbar de las pruebas
/// gratis y de las suscripciones marcadas para cancelar.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.destacada = false,
    this.padding = const EdgeInsets.all(14),
  });

  final Widget child;
  final bool destacada;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    // Material (y no Container) para que los ListTile e InkWell de adentro
    // puedan pintar su efecto al tocarlos.
    return Material(
      color: destacada ? AppColors.cardFlag : AppColors.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: destacada
            ? BorderSide(color: AppColors.amber.withValues(alpha: 0.55), width: 2)
            : const BorderSide(color: AppColors.line),
      ),
      child: Padding(
        padding: padding,
        child: SizedBox(width: double.infinity, child: child),
      ),
    );
  }
}

/// Aviso corto dentro de una tarjeta: ámbar (prueba gratis, marcada) o azul
/// (cobro cercano).
class AvisoFlag extends StatelessWidget {
  const AvisoFlag(this.texto, {super.key, this.ambar = false});

  final String texto;
  final bool ambar;

  @override
  Widget build(BuildContext context) {
    final color = ambar ? AppColors.amber : AppColors.flagBlueText;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: ambar ? AppColors.amberBg : AppColors.flagBlueBg,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: ambar ? AppColors.amber.withValues(alpha: 0.55) : AppColors.lineStrong,
          width: ambar ? 1.5 : 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.info_outline, size: 14, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              texto,
              style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fila "clave ........ valor" de las tarjetas de datos.
class FilaDato extends StatelessWidget {
  const FilaDato(this.clave, this.valor, {super.key, this.ultima = false});

  final String clave;
  final String valor;
  final bool ultima;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: ultima ? null : const Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            clave,
            style: const TextStyle(color: AppColors.muted, fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              valor,
              textAlign: TextAlign.right,
              style: const TextStyle(color: AppColors.text, fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
