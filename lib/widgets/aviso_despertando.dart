import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../Common/AppTheme.dart';
import '../services/api_client.dart';

/// Aviso fijo arriba de la pantalla mientras el servidor despierta (Render
/// gratuito tarda cerca de 1 minuto tras 15 minutos sin uso). Se muestra
/// sobre cualquier pantalla: arranque, login, registro, dashboard…
class AvisoDespertando extends StatelessWidget {
  const AvisoDespertando({super.key, required this.despertando, required this.child});

  final ValueListenable<bool> despertando;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        ValueListenableBuilder<bool>(
          valueListenable: despertando,
          builder: (context, activo, _) => activo
              ? const Positioned(top: 0, left: 0, right: 0, child: _Banner())
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Material(
          color: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: AppColors.line2),
          ),
          elevation: 6,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    ApiClient.mensajeDespertando,
                    style: TextStyle(color: AppColors.text, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
