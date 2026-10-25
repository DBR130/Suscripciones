import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../Common/AppTheme.dart';
import '../Common/Routers.dart';
import '../models/suscripcion.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/suscripcion_service.dart';
import '../utils/formato.dart';
import '../widgets/app_botones.dart';
import '../widgets/app_card.dart';
import '../widgets/app_feedback.dart';
import '../widgets/app_header.dart';
import '../widgets/logo_servicio.dart';

/// Detalle de una suscripción (pantalla 09 del diseño): datos, historial de
/// pagos, recordatorio propio, "quiero cancelar" y cancelar. Editar y
/// eliminar están en el formulario (botón "Editar" del encabezado).
class SuscripcionDetallePage extends StatefulWidget {
  const SuscripcionDetallePage({
    super.key,
    required this.id,
    required this.authService,
    required this.suscripcionService,
  });

  final int id;
  final AuthService authService;
  final SuscripcionService suscripcionService;

  @override
  State<SuscripcionDetallePage> createState() => _SuscripcionDetallePageState();
}

class _SuscripcionDetallePageState extends State<SuscripcionDetallePage> {
  DetalleSuscripcion? _detalle;
  int _diasGlobales = 3;
  String? _error;
  bool _ocupado = false;

  Suscripcion? get _s => _detalle?.suscripcion;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      final resultados = await Future.wait([
        widget.suscripcionService.obtener(widget.id),
        widget.authService.obtenerDiasAnticipacion(),
      ]);
      if (!mounted) return;
      setState(() {
        _detalle = resultados[0] as DetalleSuscripcion;
        _diasGlobales = resultados[1] as int;
        _error = null;
      });
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
      if (mounted) mostrarToast(context, e.mensaje);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  void _reemplazar(Suscripcion s) {
    setState(() => _detalle = DetalleSuscripcion(
          suscripcion: s,
          pagos: _detalle!.pagos,
          pagadoTotal: _detalle!.pagadoTotal,
        ));
  }

  Future<void> _cambiarEstado(EstadoSuscripcion estado, String mensaje) {
    return _accion(() async {
      final s = await widget.suscripcionService.cambiarEstado(widget.id, estado);
      if (!mounted) return;
      _reemplazar(s);
      mostrarToast(context, mensaje);
    });
  }

  Future<void> _cambiarDias(int dias) {
    return _accion(() async {
      final s = await widget.suscripcionService.actualizar(_s!.conDiasAviso(dias));
      if (!mounted) return;
      _reemplazar(s);
      mostrarToast(context, 'Te avisaremos ${dias == 1 ? '1 día' : '$dias días'} antes de este cobro');
    });
  }

  Future<void> _editar() async {
    await context.push(Routers.editarSuscripcion(widget.id), extra: _s);
    // Si se eliminó, el formulario ya llevó al dashboard y esta pantalla no existe.
    if (mounted) _cargar();
  }

  /// La guía de cancelación (pantalla 10) llega en otra fase; por ahora se
  /// confirma directamente que ya se canceló con el proveedor.
  Future<void> _cancelar() async {
    final s = _s!;
    final ok = await confirmarAccion(
      context,
      titulo: '¿Ya cancelaste ${s.nombreServicio}?',
      texto: 'Márcala como cancelada solo si ya la cancelaste con el proveedor. '
          'Deja de sumar en tu gasto y apagamos sus recordatorios.',
      boton: 'Sí, ya la cancelé',
    );
    if (!ok || !mounted) return;
    await _accion(() async {
      await widget.suscripcionService.cambiarEstado(widget.id, EstadoSuscripcion.cancelada);
      if (!mounted) return;
      mostrarToast(context, '${s.nombreServicio} quedó en canceladas');
      context.pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    if (s == null) {
      return Scaffold(
        body: Column(
          children: [
            AppHeader(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
              child: AppBotonVolver(onPressed: () => context.pop()),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _error == null
                    ? const Center(child: CircularProgressIndicator())
                    : Column(children: [BannerError(_error!)]),
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    AppBotonVolver(onPressed: () => context.pop()),
                    AppBotonVolver(
                      texto: 'Editar',
                      icono: Icons.edit_outlined,
                      onPressed: _ocupado ? () {} : _editar,
                    ),
                  ],
                ),
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
                            s.categoria ?? 'Registro manual',
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
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _cargar,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                children: [
                  if (marcada || cancelada) ...[
                    _AvisoAmbar(
                      cancelada
                          ? 'Esta suscripción está cancelada.'
                          : 'Tú marcaste esta suscripción para cancelar.',
                    ),
                    const SizedBox(height: 14),
                  ],
                  _Datos(_detalle!),
                  const SizedBox(height: 14),
                  _Historial(_detalle!),
                  if (!cancelada) ...[
                    const SizedBox(height: 14),
                    AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Recordatorio de esta suscripción',
                            style: TextStyle(color: AppColors.text, fontSize: 13.5, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Sobrescribe tu preferencia global',
                            style: TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 12),
                          AppPills<int>(
                            opciones: const [(1, '1 día'), (3, '3 días'), (7, '7 días')],
                            seleccion: s.diasAvisoEfectivos(_diasGlobales),
                            onChanged: _ocupado ? null : _cambiarDias,
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  if (cancelada)
                    AppBotonSecundario(
                      texto: 'Reactivar suscripción',
                      onPressed: _ocupado
                          ? null
                          : () => _cambiarEstado(EstadoSuscripcion.activa, 'Suscripción reactivada'),
                    )
                  else ...[
                    AppBotonSecundario(
                      texto: 'Cancelar esta suscripción',
                      ambar: true,
                      onPressed: _ocupado ? null : _cancelar,
                    ),
                    const SizedBox(height: 9),
                    AppBotonSecundario(
                      texto: marcada
                          ? 'Quitar marca de "quiero cancelar"'
                          : 'Marcar como "quiero cancelar"',
                      onPressed: _ocupado
                          ? null
                          : () => marcada
                              ? _cambiarEstado(EstadoSuscripcion.activa, 'Quitamos la marca')
                              : _cambiarEstado(
                                  EstadoSuscripcion.marcadaParaCancelar,
                                  'Marcada para cancelar',
                                ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Datos extends StatelessWidget {
  const _Datos(this.detalle);

  final DetalleSuscripcion detalle;

  @override
  Widget build(BuildContext context) {
    final s = detalle.suscripcion;
    final filas = <(String, String)>[
      ('Frecuencia', s.frecuencia.etiqueta),
      if (s.esPruebaGratis && s.fechaFinPrueba != null)
        ('Fin de la prueba', Formato.fecha(s.fechaFinPrueba!)),
      (s.esPruebaGratis ? 'Primer cobro' : 'Próximo cobro', Formato.fecha(s.fechaProximoCobro)),
      ('Pagado en total', Formato.moneda(detalle.pagadoTotal, s.moneda)),
      if (s.desde != null) ('Desde', Formato.mesAnio(s.desde!)),
      ('Origen', s.origen == 'notificacion' ? 'Detección por notificación' : 'Registro manual'),
    ];
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Column(
        children: [
          for (final (i, (clave, valor)) in filas.indexed)
            FilaDato(clave, valor, ultima: i == filas.length - 1),
        ],
      ),
    );
  }
}

class _Historial extends StatelessWidget {
  const _Historial(this.detalle);

  final DetalleSuscripcion detalle;

  @override
  Widget build(BuildContext context) {
    final s = detalle.suscripcion;
    final pagos = detalle.pagos;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(2, 0, 2, 9),
          child: Text(
            'Historial de pagos',
            style: TextStyle(color: AppColors.text, fontSize: 13.5, fontWeight: FontWeight.w800),
          ),
        ),
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: Column(
            children: pagos.isEmpty
                ? [
                    FilaDato(
                      s.esPruebaGratis
                          ? 'Sin pagos aún: está en prueba gratis'
                          : 'Sin pagos registrados aún',
                      Formato.moneda(0, s.moneda),
                      ultima: true,
                    ),
                  ]
                : [
                    for (final (i, p) in pagos.indexed)
                      FilaDato(
                        s.frecuencia == Frecuencia.anual
                            ? Formato.fecha(p.fecha)
                            : Formato.fechaCorta(p.fecha),
                        Formato.moneda(p.monto, s.moneda),
                        ultima: i == pagos.length - 1,
                      ),
                  ],
          ),
        ),
      ],
    );
  }
}

class _AvisoAmbar extends StatelessWidget {
  const _AvisoAmbar(this.texto);

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
