import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../Common/AppTheme.dart';
import '../Common/Routers.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../utils/formato.dart';
import '../widgets/app_botones.dart';
import '../widgets/app_card.dart';
import '../widgets/app_feedback.dart';
import 'almacen_pagos_locales.dart';
import 'catalogo_servicios.dart';
import 'deteccion_service.dart';
import 'huella_pago.dart';
import 'parser_pagos.dart';

/// Un SMS compartido con SubTrack desde la app de mensajes (sin permisos;
/// funciona en las dos versiones). Se interpreta en el celular con el mismo
/// parser: si es un cobro, el usuario lo usa para crear o completar una
/// suscripción; si no, se explica por qué.
///
/// El texto no sale del celular: solo los campos extraídos, y solo si el
/// usuario toca "Usar este cobro".
class CompartirPage extends StatefulWidget {
  const CompartirPage({
    super.key,
    required this.texto,
    required this.servicio,
    required this.cargarCatalogo,
    required this.almacen,
    required this.authService,
    DateTime Function()? ahora,
  }) : _ahora = ahora ?? DateTime.now;

  final String texto;
  final DeteccionService servicio;
  final Future<CatalogoServicios> Function() cargarCatalogo;
  final AlmacenPagosLocales almacen;
  final AuthService authService;
  final DateTime Function() _ahora;

  static const tituloNoReconocido = 'No reconocimos un cobro';

  @override
  State<CompartirPage> createState() => _CompartirPageState();
}

class _CompartirPageState extends State<CompartirPage> {
  InterpretacionPago? _interpretacion;

  /// El texto no traía la fecha: la elige el usuario (por defecto, hoy).
  DateTime? _fechaElegida;
  bool _enviando = false;
  String? _error;

  /// Respuesta del backend que no lleva a otra pantalla.
  String? _mensaje;

  @override
  void initState() {
    super.initState();
    _interpretar();
  }

  Future<void> _interpretar() async {
    CatalogoServicios catalogo;
    try {
      catalogo = await widget.cargarCatalogo();
    } on ApiException {
      // Sin backend igual se interpreta; solo no se reconoce el servicio.
      catalogo = CatalogoServicios.vacio;
    }
    final r = ParserPagos(catalogo).interpretar(widget.texto, recibidaEn: widget._ahora());
    if (mounted) setState(() => _interpretacion = r);
  }

  /// El pago con la fecha elegida, si el mensaje no traía la suya.
  PagoExtraido get _pago {
    final p = _interpretacion!.pago!;
    final elegida = _fechaElegida;
    if (p.fechaDelMensaje || elegida == null) return p;
    final ahora = widget._ahora();
    return PagoExtraido(
      banco: p.banco,
      monto: p.monto,
      moneda: p.moneda,
      comercioOriginal: p.comercioOriginal,
      comercio: p.comercio,
      servicio: p.servicio,
      indicaSuscripcion: p.indicaSuscripcion,
      medio: p.medio,
      fecha: DateTime(elegida.year, elegida.month, elegida.day, ahora.hour, ahora.minute),
      fechaDelMensaje: false,
    );
  }

  Future<void> _elegirFecha() async {
    final hoy = widget._ahora();
    final fecha = await showDatePicker(
      context: context,
      initialDate: _fechaElegida ?? hoy,
      firstDate: DateTime(hoy.year - 1, hoy.month, hoy.day),
      lastDate: hoy,
    );
    if (fecha != null && mounted) setState(() => _fechaElegida = fecha);
  }

  Future<void> _usar() async {
    final pago = _pago;
    setState(() {
      _enviando = true;
      _error = null;
      _mensaje = null;
    });
    try {
      final r = await widget.servicio.enviarCompartido(pagoParaEnviar(pago));
      // Ya salió: no se vuelve a enviar desde el almacén local.
      await widget.almacen.agregar([pago], enviados: true);
      if (!mounted) return;
      switch (r.resultado) {
        case 'suscripcion_existente':
          mostrarToast(context, 'Registramos el cobro en tu suscripción');
          context.go(r.suscripcionId == null ? Routers.dashboard : Routers.detalle(r.suscripcionId!));
        case 'candidato_nuevo' || 'candidato_actualizado':
          context.go(Routers.deteccion);
        case 'ya_confirmado':
          setState(() => _mensaje = 'Ya tienes ${pago.comercio} como suscripción.');
        case 'comercio_descartado':
          setState(() => _mensaje = 'Antes marcaste ${pago.comercio} como «No es mía», así que no la '
              'proponemos de nuevo. Si sí es tuya, agrégala a mano.');
        default: // repetido
          setState(() => _mensaje = 'Este cobro ya estaba registrado en SubTrack.');
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  void _salir() => context.go(widget.authService.usuario == null ? Routers.home : Routers.dashboard);

  @override
  Widget build(BuildContext context) {
    final r = _interpretacion;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _salir,
                icon: const Icon(Icons.close),
                label: const Text('Cerrar'),
              ),
            ),
            const SizedBox(height: 8),
            if (r == null)
              const Padding(
                padding: EdgeInsets.only(top: 60),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (!r.esCobro)
              _noReconocido(r.motivo!)
            else
              _cobro(r.pago!),
          ],
        ),
      ),
    );
  }

  Widget _noReconocido(String motivo) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          CompartirPage.tituloNoReconocido,
          style: TextStyle(color: AppColors.text, fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.6),
        ),
        const SizedBox(height: 8),
        Text(
          'Este mensaje no parece el cobro de un banco ($motivo). SubTrack reconoce SMS como '
          '«Bancolombia: Compraste \$19.900,00 en NETFLIX…» o «NEQUI: Pagaste 26.900 en SPOTIFY».',
          style: const TextStyle(color: AppColors.muted, fontSize: 13.5, fontWeight: FontWeight.w500, height: 1.5),
        ),
        const SizedBox(height: 22),
        FilledButton(
          onPressed: () => context.go(Routers.nuevaSuscripcion),
          child: const Text('Agregar una suscripción a mano'),
        ),
        const SizedBox(height: 10),
        AppBotonSecundario(texto: 'Volver al inicio', onPressed: _salir),
      ],
    );
  }

  Widget _cobro(PagoExtraido detectado) {
    final pago = _pago;
    final sinSesion = widget.authService.usuario == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Encontramos un cobro',
          style: TextStyle(color: AppColors.text, fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.6),
        ),
        const SizedBox(height: 8),
        const Text(
          'Úsalo para agregar la suscripción o registrar el pago en la que ya tienes. Solo enviamos '
          'el banco, el comercio, el monto y la fecha; el texto del mensaje se queda en tu celular.',
          style: TextStyle(color: AppColors.muted, fontSize: 13.5, fontWeight: FontWeight.w500, height: 1.5),
        ),
        const SizedBox(height: 18),
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: Column(
            children: [
              FilaDato('Comercio', pago.servicio ?? pago.comercio),
              FilaDato('Monto', Formato.moneda(pago.monto, pago.moneda)),
              FilaDato('Banco', pago.banco),
              FilaDato('Fecha', Formato.fechaLarga(pago.fecha), ultima: detectado.fechaDelMensaje),
              if (!detectado.fechaDelMensaje)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'El mensaje no trae la fecha. ¿Cuándo llegó?',
                          style: TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                      TextButton(onPressed: _elegirFecha, child: const Text('Cambiar')),
                    ],
                  ),
                ),
            ],
          ),
        ),
        if (_mensaje != null) ...[
          const SizedBox(height: 14),
          AppCard(
            child: Text(
              _mensaje!,
              style: const TextStyle(color: AppColors.text2, fontSize: 13, fontWeight: FontWeight.w600, height: 1.45),
            ),
          ),
        ],
        if (_error != null) ...[const SizedBox(height: 14), BannerError(_error!)],
        if (sinSesion) ...[
          const SizedBox(height: 14),
          const BannerError('Inicia sesión en SubTrack y vuelve a compartir el mensaje.'),
        ],
        const SizedBox(height: 22),
        FilledButton(
          onPressed: _enviando || sinSesion || _mensaje != null ? null : _usar,
          child: Text(_enviando ? 'Guardando…' : 'Usar este cobro'),
        ),
        const SizedBox(height: 10),
        AppBotonSecundario(texto: _mensaje == null ? 'Ahora no' : 'Volver al inicio', onPressed: _salir),
      ],
    );
  }
}
