import 'package:flutter/material.dart';

import '../Common/AppTheme.dart';
import 'app_botones.dart';
import 'app_card.dart';

/// HyperOS/MIUI cierra las apps en segundo plano: puede bloquear los avisos
/// programados y detener el lector de notificaciones. Estos dos ajustes lo
/// evitan. Se usa en Perfil y en la pantalla de depuración de la detección.
class GuiaXiaomi extends StatelessWidget {
  const GuiaXiaomi({
    super.key,
    required this.onInicioAutomatico,
    required this.onAjustes,
    this.titulo = 'En Xiaomi, activa esto para que lleguen los avisos',
  });

  final VoidCallback onInicioAutomatico;
  final VoidCallback onAjustes;
  final String titulo;

  @override
  Widget build(BuildContext context) {
    const estiloPaso = TextStyle(color: AppColors.text2, fontSize: 13, fontWeight: FontWeight.w600, height: 1.45);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            titulo,
            style: const TextStyle(color: AppColors.text, fontSize: 13.5, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          const Text('1. Inicio automático: actívalo para SubTrack.', style: estiloPaso),
          const SizedBox(height: 6),
          const Text(
            '2. Ahorro de batería: en los ajustes de la app, entra a "Ahorro de batería" '
            'y elige "Sin restricciones".',
            style: estiloPaso,
          ),
          const SizedBox(height: 12),
          AppBotonSecundario(texto: 'Abrir Inicio automático', onPressed: onInicioAutomatico),
          const SizedBox(height: 9),
          AppBotonSecundario(texto: 'Abrir ajustes de la app', onPressed: onAjustes),
        ],
      ),
    );
  }
}
