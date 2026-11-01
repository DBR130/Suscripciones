import 'package:flutter/material.dart';

import '../Common/AppTheme.dart';
import '../widgets/app_botones.dart';

/// Aviso cuando el permiso está concedido pero Android desconectó el lector
/// (dashboard y pantalla de permisos). El botón abre directamente el ajuste
/// de SubTrack en "Acceso a notificaciones".
class AvisoDeteccionPausada extends StatelessWidget {
  const AvisoDeteccionPausada({super.key, required this.onAbrirAjuste});

  final VoidCallback onAbrirAjuste;

  static const titulo = 'La detección está pausada';
  static const texto = 'Android desconectó el lector de notificaciones. '
      'Desactiva y vuelve a activar el acceso de SubTrack.';

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.amberBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.amberLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(Icons.pause_circle_outline, color: AppColors.amber, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  titulo,
                  style: TextStyle(color: AppColors.amber, fontSize: 14, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            texto,
            style: TextStyle(color: AppColors.text2, fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.5),
          ),
          const SizedBox(height: 10),
          AppBotonSecundario(texto: 'Abrir el ajuste', ambar: true, onPressed: onAbrirAjuste),
        ],
      ),
    );
  }
}
