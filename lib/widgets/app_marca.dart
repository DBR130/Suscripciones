import 'package:flutter/material.dart';

import '../Common/AppTheme.dart';

/// Logo de SubTrack: el cuadro azul con la "S".
/// - `AppMarca()`: grande y centrado (login y registro).
/// - `AppMarca.fila()`: la "Marca" del diseño, cuadro de 28 y "SubTrack" al lado.
class AppMarca extends StatelessWidget {
  const AppMarca({super.key}) : _fila = false;

  const AppMarca.fila({super.key}) : _fila = true;

  final bool _fila;

  @override
  Widget build(BuildContext context) {
    if (_fila) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Text(
              'S',
              style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(width: 9),
          const Text(
            'SubTrack',
            style: TextStyle(
              color: AppColors.text,
              fontSize: 17,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.34,
            ),
          ),
        ],
      );
    }
    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Text(
            'S',
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'SubTrack',
          style: TextStyle(
            color: AppColors.text,
            fontSize: 18,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
        ),
      ],
    );
  }
}
