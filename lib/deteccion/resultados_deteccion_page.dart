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
import 'catalogo_servicios.dart';
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
    this.cargarCatalogo,
  });

  final DeteccionService servicio;

  /// Nombres del catálogo para sugerir mientras se escribe el nombre del
  /// servicio (GET /api/guias). Sin él, la hoja no sugiere nada.
  final Future<CatalogoServicios> Function()? cargarCatalogo;

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

  /// Correcciones del usuario (monto, frecuencia y nombre) antes de confirmar.
  final Map<int, Correccion> _correccion = {};

  /// Catálogo para las sugerencias de la hoja (nombres y precios).
  CatalogoServicios _catalogo = CatalogoServicios.vacio;

  @override
  void initState() {
    super.initState();
    _cargar();
    _cargarCatalogo();
  }

  Future<void> _cargarCatalogo() async {
    try {
      final catalogo = await widget.cargarCatalogo?.call();
      if (catalogo != null && mounted) setState(() => _catalogo = catalogo);
    } on ApiException {
      // Sin sugerencias: el usuario igual puede escribir el nombre.
    }
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

  double _monto(CandidatoSuscripcion c) => _correccion[c.id]?.monto ?? c.monto;
  Frecuencia _frecuencia(CandidatoSuscripcion c) => _correccion[c.id]?.frecuencia ?? c.frecuencia;
  String? _nombre(CandidatoSuscripcion c) => _correccion[c.id]?.nombre;

  /// Un candidato de procesador todavía sin nombre ("¿Qué servicio es?").
  bool _faltaNombre(CandidatoSuscripcion c) => c.esDeProcesador && _nombre(c) == null;

  /// "Es mía": los que siguen en la lista se confirman al final. En uno de
  /// procesador sin nombre, abre la hoja para escribirlo.
  void _esMia(CandidatoSuscripcion c) {
    if (_faltaNombre(c)) _corregir(c);
  }

  /// "No es mía" descarta al instante (T6). La barra de 5 s permite deshacerlo.
  Future<void> _descartar(CandidatoSuscripcion c) async {
    final lista = _candidatos;
    if (lista == null) return;
    final posicion = lista.indexOf(c);
    try {
      await widget.servicio.descartar(c.id);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
      return;
    }
    if (!mounted) return;
    setState(() => _candidatos = [...lista]..remove(c));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('Descartamos ${c.titulo}'),
        duration: const Duration(seconds: 5),
        // Encima de la barra inferior con el botón de confirmar.
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(label: 'Deshacer', onPressed: () => _deshacer(c, posicion)),
      ));
  }

  Future<void> _deshacer(CandidatoSuscripcion c, int posicion) async {
    try {
      await widget.servicio.restaurar(c.id);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
      return;
    }
    if (!mounted) return;
    final lista = [...?_candidatos];
    setState(() => _candidatos = lista..insert(posicion.clamp(0, lista.length), c));
  }

  int get _confirmadas => _candidatos?.length ?? 0;

  String get _textoBoton => switch (_confirmadas) {
        0 => 'Continuar',
        1 => 'Confirmar 1 suscripción',
        final n => 'Confirmar $n suscripciones',
      };

  /// Abre la hoja de corrección. Devuelve true si el usuario guardó.
  Future<bool> _corregir(CandidatoSuscripcion c) async {
    final r = await showModalBottomSheet<Correccion>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (_) => _HojaCorreccion(
        candidato: c,
        monto: _monto(c),
        frecuencia: _frecuencia(c),
        nombre: _nombre(c),
        sugerencias: [for (final s in _catalogo.servicios) s.nombre],
        sugerenciaPorMonto: _catalogo.sugerirPorMonto(_monto(c), c.moneda),
      ),
    );
    if (r == null || !mounted) return false;
    setState(() => _correccion[c.id] = r);
    return true;
  }

  Future<void> _terminar() async {
    HapticFeedback.lightImpact();
    final candidatos = _candidatos ?? const <CandidatoSuscripcion>[];
    // Antes de confirmar, el usuario dice qué servicio es cada cobro de un
    // procesador ("Pago procesado por EBANX").
    for (final c in candidatos.where(_faltaNombre)) {
      if (!await _corregir(c)) return;
    }
    if (!mounted) return;
    setState(() {
      _guardando = true;
      _error = null;
    });
    var confirmadas = 0;
    try {
      // Los descartados ya salieron de la lista ("No es mía" es inmediato).
      for (final c in candidatos) {
        final corregido = _correccion[c.id];
        await widget.servicio.confirmar(
          c.id,
          monto: corregido?.monto,
          frecuencia: corregido?.frecuencia,
          nombre: corregido?.nombre,
        );
        confirmadas++;
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
        ],
      ),
      // Como barra inferior del Scaffold: la barra de "Deshacer" flota encima
      // de ella en vez de taparla.
      bottomNavigationBar: candidatos == null
          ? null
          : Container(
              color: AppColors.bar,
              padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.paddingOf(context).bottom),
              child: FilledButton(
                onPressed: _guardando ? null : _terminar,
                child: Text(_guardando ? 'Guardando…' : _textoBoton),
              ),
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
            nombre: _nombre(c),
            corregido: _correccion.containsKey(c.id),
            onEsMia: _guardando ? null : () => _esMia(c),
            onNoEsMia: _guardando ? null : () => _descartar(c),
            onCorregir: _guardando ? null : () => _corregir(c),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

/// Corrección del usuario en la hoja. [nombre] null = el del candidato.
typedef Correccion = ({double monto, Frecuencia frecuencia, String? nombre});

class _FilaCandidato extends StatelessWidget {
  const _FilaCandidato({
    required this.candidato,
    required this.monto,
    required this.frecuencia,
    required this.nombre,
    required this.corregido,
    required this.onEsMia,
    required this.onNoEsMia,
    required this.onCorregir,
  });

  final CandidatoSuscripcion candidato;
  final double monto;
  final Frecuencia frecuencia;

  /// Nombre que escribió el usuario, o null.
  final String? nombre;
  final bool corregido;
  final VoidCallback? onEsMia;

  /// Descarta al instante (con "Deshacer").
  final VoidCallback? onNoEsMia;
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
              LogoServicio(nombre ?? c.nombre, size: 38),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nombre ?? c.titulo,
                      style: const TextStyle(
                        color: AppColors.text,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${Formato.moneda(monto, c.moneda)} · ${frecuencia.etiqueta} · ${c.textoCobros}',
                      style: const TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    if (c.motivo != null)
                      Text(
                        c.motivo!,
                        style: const TextStyle(color: AppColors.amber, fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                    if (c.esDeProcesador && nombre == null)
                      const Text(
                        '¿Qué servicio es?',
                        style: TextStyle(color: AppColors.amber, fontSize: 12, fontWeight: FontWeight.w800),
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
                tooltip: 'Corregir nombre, monto y frecuencia',
                onPressed: onCorregir,
                icon: const Icon(Icons.edit_outlined, size: 19, color: AppColors.muted),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _Opcion(texto: 'Es mía', activa: true, onTap: onEsMia)),
              const SizedBox(width: 8),
              Expanded(child: _Opcion(texto: 'No es mía', activa: false, onTap: onNoEsMia)),
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

/// Hoja inferior para corregir nombre, monto y frecuencia antes de confirmar.
/// En un candidato de procesador el nombre es obligatorio ("¿Qué servicio es?").
class _HojaCorreccion extends StatefulWidget {
  const _HojaCorreccion({
    required this.candidato,
    required this.monto,
    required this.frecuencia,
    required this.nombre,
    required this.sugerencias,
    this.sugerenciaPorMonto,
  });

  final CandidatoSuscripcion candidato;
  final double monto;
  final Frecuencia frecuencia;
  final String? nombre;

  /// Nombres del catálogo que se sugieren al escribir.
  final List<String> sugerencias;

  /// Servicio con un precio de referencia parecido al monto (T5): se ofrece
  /// como chip "¿Es Crunchyroll?", nunca se elige solo.
  final String? sugerenciaPorMonto;

  @override
  State<_HojaCorreccion> createState() => _HojaCorreccionState();
}

class _HojaCorreccionState extends State<_HojaCorreccion> {
  late final TextEditingController _monto =
      TextEditingController(text: widget.monto == widget.monto.roundToDouble() ? widget.monto.toStringAsFixed(0) : widget.monto.toStringAsFixed(2));
  late Frecuencia _frecuencia = widget.frecuencia;
  late String _nombre =
      widget.nombre ?? (widget.candidato.esDeProcesador ? '' : widget.candidato.nombre);
  String? _error;
  String? _errorNombre;

  /// El del campo del nombre (lo crea Autocomplete).
  TextEditingController? _controlNombre;

  void _usarSugerencia(String servicio) {
    setState(() => _nombre = servicio);
    _controlNombre?.text = servicio;
  }

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
    final nombre = _nombre.trim();
    if (nombre.isEmpty) {
      setState(() => _errorNombre = 'Escribe qué servicio es');
      return;
    }
    // Solo se envía si cambió (o si el candidato es de un procesador).
    final cambiado = widget.candidato.esDeProcesador || nombre != widget.candidato.nombre;
    Navigator.of(context).pop((monto: monto, frecuencia: _frecuencia, nombre: cambiado ? nombre : null));
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
            widget.candidato.esDeProcesador ? '¿Qué servicio es?' : 'Corregir ${widget.candidato.nombre}',
            style: const TextStyle(color: AppColors.text, fontSize: 17, fontWeight: FontWeight.w800),
          ),
          if (widget.candidato.esDeProcesador) ...[
            const SizedBox(height: 4),
            Text(
              'Lo cobró ${widget.candidato.procesador}, que procesa pagos de otros servicios. '
              'Escribe el nombre del servicio que pagaste.',
              style: const TextStyle(color: AppColors.muted, fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.4),
            ),
          ],
          const SizedBox(height: 16),
          const AppEtiqueta('Servicio'),
          const SizedBox(height: 6),
          Autocomplete<String>(
            initialValue: TextEditingValue(text: _nombre),
            optionsBuilder: (valor) {
              final t = normalizarNombre(valor.text);
              if (t.isEmpty) return const Iterable<String>.empty();
              return widget.sugerencias.where((s) => normalizarNombre(s).contains(t));
            },
            onSelected: (s) => setState(() => _nombre = s),
            fieldViewBuilder: (context, controlador, foco, alEnviar) => TextField(
              key: const Key('campo-nombre'),
              // Se guarda para que el chip de la sugerencia pueda llenarlo.
              controller: _controlNombre = controlador,
              focusNode: foco,
              textCapitalization: TextCapitalization.words,
              onChanged: (v) => _nombre = v,
              decoration: InputDecoration(errorText: _errorNombre, hintText: 'Por ejemplo, Crunchyroll'),
            ),
          ),
          if (widget.sugerenciaPorMonto case final sugerencia? when sugerencia != _nombre) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: ActionChip(
                avatar: const Icon(Icons.lightbulb_outline, size: 16, color: AppColors.amber),
                label: Text('¿Es $sugerencia?'),
                onPressed: () => _usarSugerencia(sugerencia),
              ),
            ),
          ],
          const SizedBox(height: 14),
          AppEtiqueta('Monto (${widget.candidato.moneda})'),
          const SizedBox(height: 6),
          TextField(
            key: const Key('campo-monto'),
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
