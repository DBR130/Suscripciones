import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../Common/AppTheme.dart';
import '../Common/Routers.dart';
import '../models/suscripcion.dart';
import '../services/api_client.dart';
import '../services/recordatorios_service.dart';
import '../services/suscripcion_service.dart';
import '../utils/formato.dart';
import '../widgets/app_botones.dart';
import '../widgets/app_card.dart';
import '../widgets/app_feedback.dart';
import '../widgets/app_header.dart';
import '../widgets/estado_vacio.dart';
import '../widgets/logo_servicio.dart';
import 'candidato_suscripcion.dart';
import 'deteccion_service.dart';
import 'parser_pagos.dart';

/// Pantalla 05: "Encontramos {n} suscripciones" con los candidatos reales del
/// backend. Cada uno se marca "Es mía" o "No es mía", con la opción de
/// corregir monto y frecuencia antes de confirmar.
///
/// También la abre la notificación del flujo B ("¿Tienes una suscripción a…?").
class ResultadosDeteccionPage extends StatefulWidget {
  const ResultadosDeteccionPage({
    super.key,
    required this.servicio,
    this.inicio = false,
    this.recordatorios,
    this.suscripcionService,
  });

  final DeteccionService servicio;

  /// Viene del registro: al terminar sigue la pantalla 06 (si no, el dashboard).
  final bool inicio;

  /// Para programar los recordatorios de las suscripciones confirmadas.
  final RecordatoriosService? recordatorios;
  final SuscripcionService? suscripcionService;

  @override
  State<ResultadosDeteccionPage> createState() => _ResultadosDeteccionPageState();
}

class _ResultadosDeteccionPageState extends State<ResultadosDeteccionPage> {
  List<CandidatoSuscripcion>? _candidatos;
  String? _error;
  bool _guardando = false;

  /// Por candidato: true = "Es mía" (por defecto), false = "No es mía".
  final Map<int, bool> _esMia = {};

  /// Correcciones del usuario (monto y frecuencia) antes de confirmar.
  final Map<int, ({double monto, Frecuencia frecuencia})> _correccion = {};

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _error = null);
    try {
      final candidatos = await widget.servicio.candidatos();
      if (mounted) setState(() => _candidatos = candidatos);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    }
  }

  bool _mia(CandidatoSuscripcion c) => _esMia[c.id] ?? true;
  double _monto(CandidatoSuscripcion c) => _correccion[c.id]?.monto ?? c.monto;
  Frecuencia _frecuencia(CandidatoSuscripcion c) => _correccion[c.id]?.frecuencia ?? c.frecuencia;

  int get _confirmadas => (_candidatos ?? const []).where(_mia).length;

  String get _textoBoton => switch (_confirmadas) {
        0 => 'Continuar',
        1 => 'Confirmar 1 suscripción',
        final n => 'Confirmar $n suscripciones',
      };

  Future<void> _corregir(CandidatoSuscripcion c) async {
    final r = await showModalBottomSheet<({double monto, Frecuencia frecuencia})>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (_) => _HojaCorreccion(candidato: c, monto: _monto(c), frecuencia: _frecuencia(c)),
    );
    if (r != null && mounted) {
      setState(() {
        _correccion[c.id] = r;
        _esMia[c.id] = true;
      });
    }
  }

  Future<void> _terminar() async {
    HapticFeedback.lightImpact();
    final candidatos = _candidatos ?? const <CandidatoSuscripcion>[];
    setState(() {
      _guardando = true;
      _error = null;
    });
    var confirmadas = 0;
    try {
      for (final c in candidatos) {
        if (_mia(c)) {
          final corregido = _correccion[c.id];
          await widget.servicio.confirmar(c.id, monto: corregido?.monto, frecuencia: corregido?.frecuencia);
          confirmadas++;
        } else {
          await widget.servicio.descartar(c.id);
        }
      }
    } on ApiException catch (e) {
      // Las que ya se procesaron quedan hechas; se recarga la lista.
      if (!mounted) return;
      setState(() {
        _guardando = false;
        _error = e.mensaje;
      });
      _cargar();
      return;
    }
    if (!mounted) return;
    final servicio = widget.suscripcionService;
    if (confirmadas > 0 && servicio != null) widget.recordatorios?.sincronizar(servicio);
    if (confirmadas > 0) {
      mostrarToast(context, confirmadas == 1 ? 'Agregamos 1 suscripción' : 'Agregamos $confirmadas suscripciones');
    }
    context.go(widget.inicio ? Routers.preferencias : Routers.dashboard);
  }

  @override
  Widget build(BuildContext context) {
    final candidatos = _candidatos;
    final n = candidatos?.length ?? 0;
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppHeader(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!widget.inicio && context.canPop()) ...[
                  AppBotonVolver(onPressed: () => context.pop()),
                  const SizedBox(height: 14),
                ],
                AppEtiqueta(widget.inicio ? 'Primera detección' : 'Detección automática', color: AppColors.mutedHero),
                const SizedBox(height: 6),
                Text(
                  candidatos == null
                      ? 'Buscando suscripciones…'
                      : n == 1
                          ? 'Encontramos 1 suscripción'
                          : 'Encontramos $n suscripciones',
                  style: const TextStyle(color: AppColors.text, fontSize: 23, fontWeight: FontWeight.w800, letterSpacing: -0.6),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Confirma las que sí son tuyas. Puedes descartar el resto.',
                  style: TextStyle(color: AppColors.mutedHero, fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          Expanded(child: _cuerpo(candidatos)),
          if (candidatos != null)
            Container(
              color: AppColors.bar,
              padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.paddingOf(context).bottom),
              child: FilledButton(
                onPressed: _guardando ? null : _terminar,
                child: Text(_guardando ? 'Guardando…' : _textoBoton),
              ),
            ),
        ],
      ),
    );
  }

  Widget _cuerpo(List<CandidatoSuscripcion>? candidatos) {
    if (candidatos == null) {
      if (_error != null) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              BannerError(_error!),
              const SizedBox(height: 12),
              AppBotonSecundario(texto: 'Reintentar', onPressed: _cargar),
            ],
          ),
        );
      }
      return const Center(child: CircularProgressIndicator());
    }
    if (candidatos.isEmpty) {
      return ListView(
        children: [
          EstadoVacio(
            titulo: 'No encontramos suscripciones nuevas',
            texto: 'Cuando llegue un cobro de tu banco o de tu app de SMS, te avisaremos para que lo confirmes.',
            boton: 'Agregar suscripción manualmente',
            onPressed: () => context.push(Routers.nuevaSuscripcion),
          ),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_error != null) ...[BannerError(_error!), const SizedBox(height: 12)],
        for (final c in candidatos) ...[
          _FilaCandidato(
            candidato: c,
            monto: _monto(c),
            frecuencia: _frecuencia(c),
            esMia: _mia(c),
            corregido: _correccion.containsKey(c.id),
            onEsMia: _guardando ? null : (v) => setState(() => _esMia[c.id] = v),
            onCorregir: _guardando ? null : () => _corregir(c),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _FilaCandidato extends StatelessWidget {
  const _FilaCandidato({
    required this.candidato,
    required this.monto,
    required this.frecuencia,
    required this.esMia,
    required this.corregido,
    required this.onEsMia,
    required this.onCorregir,
  });

  final CandidatoSuscripcion candidato;
  final double monto;
  final Frecuencia frecuencia;
  final bool esMia;
  final bool corregido;
  final ValueChanged<bool>? onEsMia;
  final VoidCallback? onCorregir;

  @override
  Widget build(BuildContext context) {
    final c = candidato;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              LogoServicio(c.nombre, size: 38),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.nombre,
                      style: TextStyle(
                        color: esMia ? AppColors.text : AppColors.muted,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        decoration: esMia ? null : TextDecoration.lineThrough,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${Formato.moneda(monto, c.moneda)} · ${frecuencia.etiqueta} · ${c.textoCobros}',
                      style: const TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    if (corregido)
                      const Text(
                        'Corregida por ti',
                        style: TextStyle(color: AppColors.accentSoft, fontSize: 11.5, fontWeight: FontWeight.w700),
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Corregir monto y frecuencia',
                onPressed: onCorregir,
                icon: const Icon(Icons.edit_outlined, size: 19, color: AppColors.muted),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _Opcion(texto: 'Es mía', activa: esMia, onTap: onEsMia == null ? null : () => onEsMia!(true))),
              const SizedBox(width: 8),
              Expanded(
                child: _Opcion(texto: 'No es mía', activa: !esMia, onTap: onEsMia == null ? null : () => onEsMia!(false)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Botón conmutable: activo con fondo surface-2 y texto accent-soft.
class _Opcion extends StatelessWidget {
  const _Opcion({required this.texto, required this.activa, required this.onTap});

  final String texto;
  final bool activa;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: activa,
      button: true,
      child: Material(
        color: activa ? AppColors.surface2 : Colors.transparent,
        shape: StadiumBorder(side: BorderSide(color: activa ? AppColors.line2 : AppColors.line)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Text(
              texto,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: activa ? AppColors.accentSoft : AppColors.muted,
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Hoja inferior para corregir monto y frecuencia antes de confirmar.
class _HojaCorreccion extends StatefulWidget {
  const _HojaCorreccion({required this.candidato, required this.monto, required this.frecuencia});

  final CandidatoSuscripcion candidato;
  final double monto;
  final Frecuencia frecuencia;

  @override
  State<_HojaCorreccion> createState() => _HojaCorreccionState();
}

class _HojaCorreccionState extends State<_HojaCorreccion> {
  late final TextEditingController _monto =
      TextEditingController(text: widget.monto == widget.monto.roundToDouble() ? widget.monto.toStringAsFixed(0) : widget.monto.toStringAsFixed(2));
  late Frecuencia _frecuencia = widget.frecuencia;
  String? _error;

  @override
  void dispose() {
    _monto.dispose();
    super.dispose();
  }

  void _guardar() {
    // Acepta "19900", "19.900" o "19.900,50" (mismas reglas que el parser).
    final monto = leerNumero(_monto.text.replaceAll(RegExp(r'[\s$]'), ''));
    if (monto == null || monto <= 0) {
      setState(() => _error = 'Escribe un monto mayor que 0');
      return;
    }
    Navigator.of(context).pop((monto: monto, frecuencia: _frecuencia));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Corregir ${widget.candidato.nombre}',
            style: const TextStyle(color: AppColors.text, fontSize: 17, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 16),
          AppEtiqueta('Monto (${widget.candidato.moneda})'),
          const SizedBox(height: 6),
          TextField(
            controller: _monto,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(errorText: _error),
          ),
          const SizedBox(height: 14),
          const AppEtiqueta('Frecuencia'),
          const SizedBox(height: 6),
          AppPills<Frecuencia>(
            opciones: [for (final f in Frecuencia.values) (f, f.etiqueta)],
            seleccion: _frecuencia,
            onChanged: (f) => setState(() => _frecuencia = f),
          ),
          const SizedBox(height: 20),
          FilledButton(onPressed: _guardar, child: const Text('Guardar corrección')),
        ],
      ),
    );
  }
}
