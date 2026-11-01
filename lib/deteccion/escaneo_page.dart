import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../Common/AppTheme.dart';
import '../Common/Routers.dart';
import '../widgets/app_botones.dart';
import '../widgets/app_feedback.dart';
import 'procesador_detecciones.dart';

/// Pantalla 04: revisa la cola de notificaciones de pago y las activas de la
/// barra, las interpreta y envía al backend lo que forma una suscripción. Con
/// [historial] además busca en los SMS de los últimos 6 meses (versión
/// "completa", con el permiso ya concedido). Al terminar pasa a los
/// resultados (05).
class EscaneoPage extends StatefulWidget {
  const EscaneoPage({
    super.key,
    required this.procesador,
    this.inicio = false,
    this.historial = false,
    this.duracionMinima = const Duration(milliseconds: 1900),
  });

  final ProcesadorDetecciones procesador;
  final bool inicio;
  final bool historial;

  /// El diseño muestra la animación al menos 1,9 s, aunque termine antes.
  final Duration duracionMinima;

  /// Pista cuando se leyeron SMS pero ninguno de un banco o empresa.
  static const tituloSmsOcultos = 'No vimos SMS de bancos';

  @override
  State<EscaneoPage> createState() => _EscaneoPageState();
}

class _EscaneoPageState extends State<EscaneoPage> with SingleTickerProviderStateMixin {
  late final AnimationController _pulso =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
  String? _error;
  EtapaHistorial? _etapa;

  /// Búsqueda en el historial sin ningún SMS de empresa (ver ResultadoHistorial).
  bool _smsOcultos = false;

  @override
  void initState() {
    super.initState();
    _escanear();
  }

  @override
  void dispose() {
    _pulso.dispose();
    super.dispose();
  }

  Future<void> _escanear() async {
    setState(() {
      _error = null;
      _smsOcultos = false;
    });
    _pulso.repeat(reverse: true);
    try {
      await Future.wait([_revisar(), Future<void>.delayed(widget.duracionMinima)]);
      if (!mounted) return;
      if (_smsOcultos) {
        _pulso.stop();
        setState(() {});
        return;
      }
      _verResultados();
    } catch (e) {
      // La cola y el almacén local quedan intactos: se puede reintentar.
      if (!mounted) return;
      _pulso.stop();
      setState(() => _error = '$e');
    }
  }

  Future<void> _revisar() async {
    await widget.procesador.procesar();
    if (!widget.historial) return;
    final r = await widget.procesador.buscarEnHistorial(
      alAvanzar: (etapa) {
        if (mounted) setState(() => _etapa = etapa);
      },
    );
    _smsOcultos = r.sospechaSmsOcultos && r.cobros == 0;
  }

  void _verResultados() => context.pushReplacement(Routers.rutaDeteccion(inicio: widget.inicio));

  void _seguirSinDetectar() => context.go(widget.inicio ? Routers.preferencias : Routers.dashboard);

  String get _titulo => widget.historial ? 'Revisando tus mensajes del banco…' : 'Revisando tus notificaciones de pago…';

  String get _detalle => switch (_etapa) {
        EtapaHistorial.leyendo => 'Leyendo los SMS de los últimos 6 meses. Los que no son cobros se descartan aquí mismo.',
        EtapaHistorial.analizando => 'Buscando cobros que se repitan con el mismo monto y comercio.',
        EtapaHistorial.enviando => 'Guardando las suscripciones que encontramos.',
        null => 'Buscamos cobros que se repitan con el mismo monto y comercio.',
      };

  /// Progreso por etapas en la búsqueda del historial; indeterminado si no.
  double? get _progreso => switch (_etapa) {
        EtapaHistorial.leyendo => 0.2,
        EtapaHistorial.analizando => 0.6,
        EtapaHistorial.enviando => 0.9,
        null => null,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: ScaleTransition(
                  scale: Tween(begin: 0.92, end: 1.05).animate(CurvedAnimation(parent: _pulso, curve: Curves.easeInOut)),
                  child: Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.surface2,
                      border: Border.all(color: AppColors.primary, width: 2),
                    ),
                    child: Icon(
                      widget.historial ? Icons.sms_outlined : Icons.search_rounded,
                      color: AppColors.link,
                      size: 40,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 26),
              Text(
                _titulo,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.text,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _detalle,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.muted, fontSize: 13.5, fontWeight: FontWeight.w500, height: 1.5),
              ),
              const SizedBox(height: 22),
              if (_smsOcultos)
                _SmsOcultos(
                  onAbrirPermisos: widget.procesador.historial.abrirPermisosApp,
                  onReintentar: _escanear,
                  onVerResultados: _verResultados,
                )
              else if (_error == null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: _progreso,
                    minHeight: 6,
                    color: AppColors.primary,
                    backgroundColor: AppColors.surface,
                  ),
                )
              else ...[
                const BannerError('No pudimos revisar tus cobros. Revisa tu conexión e inténtalo de nuevo.'),
                const SizedBox(height: 14),
                FilledButton(onPressed: _escanear, child: const Text('Reintentar')),
                const SizedBox(height: 10),
                AppBotonSecundario(texto: 'Seguir sin detectar', onPressed: _seguirSinDetectar),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Se leyeron SMS, pero ninguno de un número corto o de una empresa. En
/// Xiaomi (MIUI/HyperOS) los "SMS de servicio" pueden estar ocultos para las
/// apps aunque el permiso SMS esté concedido.
class _SmsOcultos extends StatelessWidget {
  const _SmsOcultos({required this.onAbrirPermisos, required this.onReintentar, required this.onVerResultados});

  final Future<void> Function() onAbrirPermisos;
  final VoidCallback onReintentar;
  final VoidCallback onVerResultados;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.amberBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.amberLine),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                EscaneoPage.tituloSmsOcultos,
                style: TextStyle(color: AppColors.amber, fontSize: 13.5, fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 6),
              Text(
                'Leímos tus SMS, pero ninguno de un banco o de un número corto. En Xiaomi, Redmi y '
                'POCO esos «SMS de servicio» pueden estar ocultos para las apps: abre los permisos de '
                'SubTrack y permite los SMS (y, si aparece, «SMS de servicio» o «SMS de notificación» '
                'en Otros permisos). Luego toca «Buscar de nuevo».',
                style: TextStyle(color: AppColors.text2, fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.5),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AppBotonSecundario(texto: 'Abrir los permisos de SubTrack', ambar: true, onPressed: onAbrirPermisos),
        const SizedBox(height: 9),
        FilledButton(onPressed: onReintentar, child: const Text('Buscar de nuevo')),
        const SizedBox(height: 9),
        AppBotonSecundario(texto: 'Ver resultados', onPressed: onVerResultados),
      ],
    );
  }
}
