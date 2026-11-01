import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../Common/AppTheme.dart';
import '../Common/Routers.dart';
import '../services/avisos_nuevos.dart';
import 'presionable.dart';

/// Campana del encabezado (arriba a la derecha) con el número de avisos
/// nuevos. Abre la pantalla de Avisos y al volver recuenta.
class CampanaAvisos extends StatelessWidget {
  const CampanaAvisos({super.key});

  @override
  Widget build(BuildContext context) {
    final avisos = AvisosNuevos.maybeOf(context);
    final nuevos = avisos?.value ?? 0;
    return Semantics(
      container: true,
      button: true,
      label: nuevos == 0 ? 'Avisos' : 'Avisos, $nuevos ${nuevos == 1 ? 'nuevo' : 'nuevos'}',
      excludeSemantics: true,
      child: Presionable(
        onTap: () async {
          await context.push(Routers.avisos);
          avisos?.actualizar();
        },
        child: SizedBox(
          width: 38,
          height: 38,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
                ),
                child: Icon(
                  nuevos > 0 ? Icons.notifications_active_outlined : Icons.notifications_none,
                  size: 19,
                  color: AppColors.textSoft,
                ),
              ),
              Positioned(
                top: -3,
                right: -3,
                child: AnimatedScale(
                  scale: nuevos > 0 ? 1 : 0,
                  duration: MediaQuery.of(context).disableAnimations
                      ? Duration.zero
                      : const Duration(milliseconds: 220),
                  curve: Curves.easeOutBack,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 18),
                    height: 18,
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.amber,
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(color: AppColors.bg, width: 1.5),
                    ),
                    child: Text(
                      nuevos > 9 ? '9+' : '$nuevos',
                      style: const TextStyle(color: AppColors.bg, fontSize: 10.5, fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
