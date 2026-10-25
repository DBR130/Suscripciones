import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../Common/AppTheme.dart';
import '../Common/Routers.dart';
import '../models/suscripcion.dart';
import '../services/api_client.dart';
import '../services/suscripcion_service.dart';
import '../utils/formato.dart';
import '../widgets/app_botones.dart';
import '../widgets/app_card.dart';
import '../widgets/app_header.dart';
import '../widgets/logo_servicio.dart';
import '../widgets/suscripcion_card.dart';

/// Detalle de una suscripción (pantalla 09 del diseño): datos, editar,
/// marcar "quiero cancelar" / cancelada y eliminar.
class SuscripcionDetallePage extends StatefulWidget {
  const SuscripcionDetallePage({
    super.key,
    required this.id,
    required this.suscripcionService,
  });

  final int id;
  final SuscripcionService suscripcionService;

  @override
  State<SuscripcionDetallePage> createState() => _SuscripcionDetallePageState();
}

class _SuscripcionDetallePageState extends State<SuscripcionDetallePage> {
  Suscripcion? _suscripcion;
  String? _error;
  bool _ocupado = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final s = await widget.suscripcionService.obtener(widget.id);
      if (mounted) setState(() => _suscripcion = s);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    }
  }

  /// Ejecuta una acción mostrando el estado ocupado y los errores.
  Future<void> _accion(Future<void> Function() accion) async {
    setState(() => _ocupado = true);
    try {
      await accion();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.mensaje)));
      }
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _cambiarEstado(EstadoSuscripcion estado, String mensaje) {
    return _accion(() async {
      final s = await widget.suscripcionService.cambiarEstado(widget.id, estado);
      if (!mounted) return;
      setState(() => _suscripcion = s);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensaje)));
    });
  }

  Future<void> _editar() async {
    final editada = await context.push<Suscripcion>(
      Routers.editarSuscripcion(widget.id),
      extra: _suscripcion,
    );
    if (editada != null && mounted) setState(() => _suscripcion = editada);
  }

  Future<void> _marcarCancelada() async {
    final ok = await _confirmar(
      titulo: '¿Ya cancelaste ${_suscripcion!.nombreServicio}?',
      texto: 'Márcala como cancelada solo si ya la cancelaste con el proveedor. '
          'Dejará de contar en tu gasto y no recibirás más avisos de ella.',
      boton: 'Sí, ya la cancelé',
    );
    if (ok) await _cambiarEstado(EstadoSuscripcion.cancelada, 'Suscripción marcada como cancelada');
  }

  Future<void> _eliminar() async {
    final ok = await _confirmar(
      titulo: '¿Eliminar ${_suscripcion!.nombreServicio}?',
      texto: 'Se borrará de tu lista junto con su historial. '
          'Esta acción no se puede deshacer.',
      boton: 'Eliminar',
      peligro: true,
    );
    if (!ok) return;
    await _accion(() async {
      await widget.suscripcionService.eliminar(widget.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Suscripción eliminada')),
      );
      context.pop();
    });
  }

  Future<bool> _confirmar({
    required String titulo,
    required String texto,
    required String boton,
    bool peligro = false,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(titulo),
        content: Text(texto, style: const TextStyle(color: AppColors.muted, height: 1.4)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: peligro ? AppColors.error : AppColors.amber,
            ),
            child: Text(boton),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final s = _suscripcion;
    if (s == null) {
      return Scaffold(
        body: Column(
          children: [
            AppHeader(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
              child: AppBotonVolver(onPressed: () => context.pop()),
            ),
            Expanded(
              child: Center(
                child: _error == null
                    ? const CircularProgressIndicator()
                    : Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppColors.muted),
                        ),
                      ),
              ),
            ),
          ],
        ),
      );
    }

    final marcada = s.estado == EstadoSuscripcion.marcadaParaCancelar;
    final cancelada = s.estado == EstadoSuscripcion.cancelada;

    return Scaffold(
      body: Column(
        children: [
          AppHeader(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppBotonVolver(onPressed: () => context.pop()),
                const SizedBox(height: 16),
                Row(
                  children: [
                    LogoServicio(s.nombreServicio, size: 52),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.nombreServicio,
                            style: const TextStyle(
                              color: AppColors.text,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            descripcionSuscripcion(s),
                            style: const TextStyle(
                              color: AppColors.mutedOnGradient,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text.rich(
                  TextSpan(
                    text: s.montoTexto,
                    children: [
                      TextSpan(
                        text: ' ${s.frecuencia.sufijo}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.mutedOnGradient,
                          letterSpacing: 0,
                        ),
                      ),
                    ],
                  ),
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.8,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                if (marcada || cancelada) ...[
                  _Banner(
                    cancelada
                        ? 'Esta suscripción está cancelada.'
                        : 'Tú marcaste esta suscripción para cancelar.',
                  ),
                  const SizedBox(height: 14),
                ],
                AppCard(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  child: Column(children: _datos(s)),
                ),
                const SizedBox(height: 18),
                AppBotonSecundario(
                  texto: 'Editar suscripción',
                  icon: Icons.edit_outlined,
                  onPressed: _ocupado ? null : _editar,
                ),
                const SizedBox(height: 9),
                if (cancelada)
                  AppBotonSecundario(
                    texto: 'Reactivar suscripción',
                    onPressed: _ocupado
                        ? null
                        : () => _cambiarEstado(EstadoSuscripcion.activa, 'Suscripción reactivada'),
                  )
                else ...[
                  AppBotonSecundario(
                    texto: 'Marcar como cancelada',
                    ambar: true,
                    onPressed: _ocupado ? null : _marcarCancelada,
                  ),
                  const SizedBox(height: 9),
                  AppBotonSecundario(
                    texto: marcada
                        ? 'Quitar marca de "quiero cancelar"'
                        : 'Marcar como "quiero cancelar"',
                    onPressed: _ocupado
                        ? null
                        : () => marcada
                            ? _cambiarEstado(EstadoSuscripcion.activa, 'Marca quitada')
                            : _cambiarEstado(
                                EstadoSuscripcion.marcadaParaCancelar,
                                'Marcada para cancelar',
                              ),
                  ),
                ],
                const SizedBox(height: 9),
                TextButton.icon(
                  onPressed: _ocupado ? null : _eliminar,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Eliminar suscripción'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.error,
                    minimumSize: const Size.fromHeight(46),
                    textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _datos(Suscripcion s) {
    final filas = <(String, String)>[
      ('Frecuencia', s.frecuencia.etiqueta),
      ('Próximo cobro', Formato.fecha(s.fechaProximoCobro)),
      if (s.esPruebaGratis && s.fechaFinPrueba != null)
        ('Fin de la prueba', Formato.fecha(s.fechaFinPrueba!)),
      ('Moneda', s.moneda),
      (
        'Recordatorio',
        s.diasAviso == null
            ? 'Preferencia global'
            : s.diasAviso == 1
                ? '1 día antes'
                : '${s.diasAviso} días antes',
      ),
      ('Estado', s.estado.etiqueta),
      ('Origen', s.origen == 'notificacion' ? 'Detección por notificación' : 'Registro manual'),
      if (s.creadoEn != null) ('Registrada el', Formato.fecha(s.creadoEn!)),
    ];
    return [
      for (final (i, (clave, valor)) in filas.indexed)
        FilaDato(clave, valor, ultima: i == filas.length - 1),
    ];
  }
}

class _Banner extends StatelessWidget {
  const _Banner(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: AppColors.amberBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.amber.withValues(alpha: 0.55), width: 1.5),
      ),
      child: Text(
        texto,
        style: const TextStyle(
          color: AppColors.amberStrong,
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
