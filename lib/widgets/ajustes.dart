import 'package:flutter/material.dart';

import '../Common/AppTheme.dart';

/// Sección de ajustes del Perfil: título pequeño en mayúsculas y gris fuera
/// de la tarjeta, y las filas dentro, separadas por líneas finas.
class SeccionAjustes extends StatelessWidget {
  const SeccionAjustes({super.key, this.titulo, required this.filas});

  /// null: tarjeta sin título.
  final String? titulo;
  final List<Widget> filas;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (titulo != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Text(
              titulo!.toUpperCase(),
              style: const TextStyle(color: AppColors.muted, fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 1),
            ),
          ),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.line),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              children: [
                for (final (i, fila) in filas.indexed) ...[
                  if (i > 0) const Divider(height: 1, thickness: 1, indent: 62, color: AppColors.divider),
                  fila,
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Fila de ajustes: ícono en un cuadrito de color suave, título, subtítulo
/// gris con el valor actual y, a la derecha, "›" o un interruptor.
/// [debajo] agrega contenido bajo el texto (por ejemplo, el selector de días).
class FilaAjuste extends StatelessWidget {
  const FilaAjuste({
    super.key,
    required this.icono,
    required this.color,
    required this.titulo,
    this.subtitulo,
    this.colorSubtitulo = AppColors.muted,
    this.onTap,
    this.debajo,
  })  : interruptor = null,
        onCambiar = null;

  /// Fila con interruptor. Tocar cualquier parte de la fila lo cambia.
  const FilaAjuste.interruptor({
    super.key,
    required this.icono,
    required this.color,
    required this.titulo,
    this.subtitulo,
    required bool valor,
    required this.onCambiar,
  })  : interruptor = valor,
        colorSubtitulo = AppColors.muted,
        onTap = null,
        debajo = null;

  final IconData icono;
  final Color color;
  final String titulo;
  final String? subtitulo;
  final Color colorSubtitulo;
  final VoidCallback? onTap;
  final Widget? debajo;
  final bool? interruptor;
  final ValueChanged<bool>? onCambiar;

  @override
  Widget build(BuildContext context) {
    final valor = interruptor;
    final alTocar = valor == null ? onTap : (onCambiar == null ? null : () => onCambiar!(!valor));
    return InkWell(
      onTap: alTocar,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icono, size: 19, color: color),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titulo,
                        style: const TextStyle(color: AppColors.text, fontSize: 14, fontWeight: FontWeight.w700),
                      ),
                      if (subtitulo != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitulo!,
                          style: TextStyle(color: colorSubtitulo, fontSize: 12.5, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (valor != null)
                  Switch(value: valor, onChanged: onCambiar, activeTrackColor: AppColors.primary)
                else if (onTap != null)
                  const Text('›', style: TextStyle(color: AppColors.muted, fontSize: 22, fontWeight: FontWeight.w600)),
              ],
            ),
            if (debajo != null) ...[
              const SizedBox(height: 12),
              Padding(padding: const EdgeInsets.only(left: 48), child: debajo),
            ],
          ],
        ),
      ),
    );
  }
}

/// Colores de los íconos de las filas, todos de la paleta de la app.
abstract final class ColoresAjustes {
  static const azul = AppColors.accent;
  static const celeste = AppColors.link;
  static const lavanda = AppColors.accentSoft;
  static const ambar = AppColors.amber;
  static const dorado = AppColors.amberStrong;
  static const rosa = AppColors.errorSoft;
  static const gris = AppColors.mutedHero;
  static const primario = AppColors.primary;
}
