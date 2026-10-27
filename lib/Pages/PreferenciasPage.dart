import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../Common/AppTheme.dart';
import '../Common/Routers.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/recordatorios_service.dart';
import '../widgets/app_card.dart';
import '../widgets/app_feedback.dart';

/// Preferencia de recordatorio (pantalla 06 del diseño). Se muestra después
/// del registro: elige los días de anticipación y pide el permiso de
/// notificaciones. Si el usuario no lo da, la app funciona igual.
class PreferenciasPage extends StatefulWidget {
  const PreferenciasPage({super.key, required this.authService, this.recordatorios});

  final AuthService authService;

  /// null en los tests (y en web no hace nada).
  final RecordatoriosService? recordatorios;

  @override
  State<PreferenciasPage> createState() => _PreferenciasPageState();
}

class _PreferenciasPageState extends State<PreferenciasPage> {
  static const _opciones = [
    (dias: 1, titulo: '1 día antes', pista: 'Aviso justo antes del cobro'),
    (dias: 3, titulo: '3 días antes', pista: 'Recomendado: alcanzas a cancelar'),
    (dias: 7, titulo: '7 días antes', pista: 'Para planear el mes completo'),
  ];

  int _dias = 3;
  bool _resumen = true;
  bool _guardando = false;

  bool get _hayRecordatorios => widget.recordatorios?.disponible ?? false;

  Future<void> _continuar() async {
    setState(() => _guardando = true);
    try {
      await widget.authService.guardarDiasAnticipacion(_dias);
    } on ApiException catch (e) {
      // No bloquea: se puede cambiar después en Perfil.
      if (mounted) mostrarToast(context, e.mensaje);
    }
    final recordatorios = widget.recordatorios;
    if (recordatorios != null) {
      await recordatorios.cambiarResumenMensual(_resumen);
      // Android 13+ muestra el diálogo del sistema. Si lo rechaza, seguimos.
      await recordatorios.pedirPermiso();
    }
    if (mounted) context.go(Routers.dashboard);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 26, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      '¿Cuántos días antes te avisamos?',
                      style: TextStyle(
                        color: AppColors.text,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.6,
                        height: 1.18,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Se aplica a todos los cobros. Después puedes cambiarlo por suscripción.',
                      style: TextStyle(color: AppColors.muted, fontSize: 13.5, fontWeight: FontWeight.w500, height: 1.5),
                    ),
                    const SizedBox(height: 22),
                    for (final o in _opciones) ...[
                      _Opcion(
                        titulo: o.titulo,
                        pista: o.pista,
                        activa: _dias == o.dias,
                        onTap: () => setState(() => _dias = o.dias),
                      ),
                      const SizedBox(height: 10),
                    ],
                    const SizedBox(height: 14),
                    AppCard(
                      padding: const EdgeInsets.fromLTRB(14, 4, 8, 4),
                      child: SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _resumen,
                        onChanged: (v) => setState(() => _resumen = v),
                        activeTrackColor: AppColors.primary,
                        title: const Text(
                          'Resumen mensual',
                          style: TextStyle(color: AppColors.text, fontSize: 13.5, fontWeight: FontWeight.w700),
                        ),
                        subtitle: const Text(
                          'Cada inicio de mes, con tu gasto total',
                          style: TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    if (_hayRecordatorios) ...[
                      const SizedBox(height: 12),
                      const Text(
                        'Al continuar te pediremos permiso para enviarte notificaciones. '
                        'Si no lo das, la app funciona igual.',
                        style: TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w600, height: 1.5),
                      ),
                    ],
                    const Spacer(),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _guardando ? null : _continuar,
                      child: const Text('Ir a mi dashboard'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Opción grande con título y pista ("3 días antes" / "Recomendado…").
class _Opcion extends StatelessWidget {
  const _Opcion({required this.titulo, required this.pista, required this.activa, required this.onTap});

  final String titulo;
  final String pista;
  final bool activa;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: activa,
      button: true,
      child: Material(
        color: activa ? AppColors.primary : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: activa ? BorderSide.none : const BorderSide(color: AppColors.line2),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: TextStyle(
                    color: activa ? Colors.white : AppColors.text2,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  pista,
                  style: TextStyle(
                    color: activa ? const Color(0xFFDCE6F8) : AppColors.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
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
