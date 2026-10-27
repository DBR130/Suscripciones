import 'package:flutter/material.dart';

import '../Common/AppTheme.dart';

/// Estado vacío del diseño: ícono "+" en un cuadro, título, texto y botón.
class EstadoVacio extends StatelessWidget {
  const EstadoVacio({
    super.key,
    required this.titulo,
    required this.texto,
    this.boton,
    this.onPressed,
  });

  final String titulo;
  final String texto;
  final String? boton;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 34),
      child: Column(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: AppColors.flagBlueBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.lineStrong),
            ),
            child: const Icon(Icons.add, color: AppColors.link),
          ),
          const SizedBox(height: 10),
          Text(
            titulo,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.text, fontSize: 17, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: Text(
              texto,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted, fontSize: 13, fontWeight: FontWeight.w500, height: 1.5),
            ),
          ),
          if (boton != null) ...[
            const SizedBox(height: 18),
            FilledButton(onPressed: onPressed, child: Text(boton!)),
          ],
        ],
      ),
    );
  }
}
