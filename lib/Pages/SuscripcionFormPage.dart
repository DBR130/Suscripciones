import 'package:flutter/material.dart';
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
import '../widgets/app_text_field.dart';

/// Agregar o editar una suscripción (pantalla 13 del diseño).
/// Con [inicial] edita esa suscripción (y permite eliminarla); sin ella,
/// crea una nueva. Al guardar vuelve con la suscripción guardada.
class SuscripcionFormPage extends StatefulWidget {
  const SuscripcionFormPage({
    super.key,
    required this.suscripcionService,
    this.recordatorios,
    this.inicial,
  });

  final SuscripcionService suscripcionService;
  final RecordatoriosService? recordatorios;
  final Suscripcion? inicial;

  @override
  State<SuscripcionFormPage> createState() => _SuscripcionFormPageState();
}

class _SuscripcionFormPageState extends State<SuscripcionFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _nombreCtrl = TextEditingController();
  final _montoCtrl = TextEditingController();
  final _fechaCtrl = TextEditingController();
  final _finPruebaCtrl = TextEditingController();

  String? _categoria;
  String _moneda = 'COP';
  Frecuencia _frecuencia = Frecuencia.mensual;
  DateTime? _fecha;
  bool _esPrueba = false;
  DateTime? _finPrueba;
  bool _guardando = false;
  String? _errorServidor;

  bool get _editando => widget.inicial != null;

  @override
  void initState() {
    super.initState();
    final s = widget.inicial;
    if (s != null) {
      _nombreCtrl.text = s.nombreServicio;
      _categoria = s.categoria;
      _montoCtrl.text = Formato.montoParaEditar(s.monto, s.moneda);
      _moneda = s.moneda;
      _frecuencia = s.frecuencia;
      _esPrueba = s.esPruebaGratis;
      _ponerFecha(s.fechaProximoCobro);
      if (s.fechaFinPrueba != null) _ponerFinPrueba(s.fechaFinPrueba!);
    }
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _montoCtrl.dispose();
    _fechaCtrl.dispose();
    _finPruebaCtrl.dispose();
    super.dispose();
  }

  void _ponerFecha(DateTime fecha) {
    _fecha = fecha;
    _fechaCtrl.text = Formato.fecha(fecha);
  }

  void _ponerFinPrueba(DateTime fecha) {
    // El primer cobro suele ser el día en que termina la prueba: se llena
    // solo si está vacío o si seguía igual al fin anterior (no lo tocaron).
    if (_fecha == null || _fecha == _finPrueba) _ponerFecha(fecha);
    _finPrueba = fecha;
    _finPruebaCtrl.text = Formato.fecha(fecha);
  }

  Future<DateTime?> _elegirFecha(DateTime? actual) {
    return showDatePicker(
      context: context,
      initialDate: actual ?? DateUtils.dateOnly(DateTime.now()),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100, 12, 31),
      helpText: 'Selecciona la fecha',
    );
  }

  String? _validarMonto(String? value) {
    if (value == null || value.trim().isEmpty) return 'Ingresa un monto mayor a 0';
    final monto = Formato.leerMonto(value, _moneda);
    if (monto == null) return 'Monto no válido (máximo 2 decimales)';
    if (monto <= 0) return 'Ingresa un monto mayor a 0';
    return null;
  }

  Future<void> _guardar() async {
    FocusScope.of(context).unfocus();
    setState(() => _errorServidor = null);
    if (!_formKey.currentState!.validate()) return;

    final suscripcion = Suscripcion(
      id: widget.inicial?.id,
      nombreServicio: _nombreCtrl.text.trim(),
      categoria: _categoria,
      monto: Formato.leerMonto(_montoCtrl.text, _moneda)!,
      moneda: _moneda,
      frecuencia: _frecuencia,
      fechaProximoCobro: _fecha!,
      esPruebaGratis: _esPrueba,
      fechaFinPrueba: _esPrueba ? _finPrueba : null,
      // Los días de aviso se cambian en el detalle; aquí se conservan.
      diasAviso: widget.inicial?.diasAviso,
    );

    setState(() => _guardando = true);
    try {
      final guardada = _editando
          ? await widget.suscripcionService.actualizar(suscripcion)
          : await widget.suscripcionService.crear(suscripcion);
      widget.recordatorios?.sincronizar(widget.suscripcionService);
      if (!mounted) return;
      mostrarToast(
        context,
        _editando ? 'Cambios guardados' : '${guardada.nombreServicio} se agregó a tu lista',
      );
      context.pop(guardada);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _guardando = false;
        _errorServidor = e.mensaje;
      });
    }
  }

  Future<void> _eliminar() async {
    final s = widget.inicial!;
    final ok = await confirmarAccion(
      context,
      titulo: '¿Eliminar ${s.nombreServicio}?',
      texto: 'Se borra de tu lista junto con su historial de pagos y sus recordatorios. '
          'Esto no cancela el servicio con el proveedor y no se puede deshacer.',
      boton: 'Eliminar suscripción',
    );
    if (!ok || !mounted) return;
    setState(() => _guardando = true);
    try {
      await widget.suscripcionService.eliminar(s.id!);
      widget.recordatorios?.sincronizar(widget.suscripcionService);
      if (!mounted) return;
      mostrarToast(context, '${s.nombreServicio} se eliminó de tu lista');
      context.go(Routers.dashboard);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _guardando = false;
        _errorServidor = e.mensaje;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          AppHeader(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppBotonVolver(onPressed: () => context.pop()),
                const SizedBox(height: 14),
                Text(
                  _editando ? 'Editar suscripción' : 'Agregar suscripción',
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            // SafeArea lateral: en horizontal o con muesca, el sistema puede
            // tapar los bordes y cortar el inicio de las etiquetas.
            child: SafeArea(
              top: false,
              bottom: false,
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                  children: [
                    if (_errorServidor != null) ...[
                      BannerError(_errorServidor!),
                      const SizedBox(height: 14),
                    ],
                    AppTextField(
                      controller: _nombreCtrl,
                      label: 'Servicio',
                      hint: 'ej. HBO Max',
                      textInputAction: TextInputAction.next,
                      validator: (v) => v == null || v.trim().isEmpty
                          ? 'Ingresa el nombre del servicio'
                          : v.trim().length > 100
                              ? 'Máximo 100 caracteres'
                              : null,
                    ),
                    const SizedBox(height: 14),
                    const AppEtiqueta('Categoría (opcional)'),
                    const SizedBox(height: 7),
                    _SelectorCategoria(
                      seleccion: _categoria,
                      onChanged: (c) => setState(() => _categoria = c),
                    ),
                    const SizedBox(height: 14),
                    AppTextField(
                      controller: _montoCtrl,
                      label: 'Monto ($_moneda)',
                      hint: _moneda == 'COP' ? '24900' : '9.99',
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      validator: _validarMonto,
                    ),
                    const SizedBox(height: 14),
                    const AppEtiqueta('Moneda'),
                    const SizedBox(height: 7),
                    AppPills<String>(
                      opciones: const [('COP', 'COP'), ('USD', 'USD')],
                      seleccion: _moneda,
                      onChanged: (m) => setState(() => _moneda = m),
                    ),
                    const SizedBox(height: 14),
                    const AppEtiqueta('Frecuencia'),
                    const SizedBox(height: 7),
                    AppPills<Frecuencia>(
                      // Mismo orden que el diseño.
                      opciones: [
                        for (final f in const [Frecuencia.mensual, Frecuencia.anual, Frecuencia.semanal])
                          (f, f.etiqueta),
                      ],
                      seleccion: _frecuencia,
                      onChanged: (f) => setState(() => _frecuencia = f),
                    ),
                    const SizedBox(height: 14),
                    AppTextField(
                      controller: _fechaCtrl,
                      label: _esPrueba ? 'Primer cobro (al terminar la prueba)' : 'Próximo cobro',
                      hint: 'Elige una fecha',
                      suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
                      readOnly: true,
                      validator: (_) => _fecha == null ? 'Elige la fecha del próximo cobro' : null,
                      onTap: () async {
                        final fecha = await _elegirFecha(_fecha);
                        if (fecha != null) setState(() => _ponerFecha(fecha));
                      },
                    ),
                    const SizedBox(height: 14),
                    AppCard(
                      padding: const EdgeInsets.fromLTRB(14, 4, 8, 4),
                      child: SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _esPrueba,
                        onChanged: (v) => setState(() => _esPrueba = v),
                        activeTrackColor: AppColors.primary,
                        inactiveTrackColor: AppColors.surface,
                        inactiveThumbColor: const Color(0xFF5B6A85),
                        trackOutlineColor: WidgetStateProperty.resolveWith(
                          (states) => states.contains(WidgetState.selected)
                              ? Colors.transparent
                              : AppColors.lineStrong,
                        ),
                        title: const Text(
                          'Es una prueba gratis',
                          style: TextStyle(color: AppColors.text, fontSize: 13.5, fontWeight: FontWeight.w700),
                        ),
                        subtitle: const Text(
                          'Activa el aviso de fin de prueba',
                          style: TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    if (_esPrueba) ...[
                      const SizedBox(height: 14),
                      AppTextField(
                        controller: _finPruebaCtrl,
                        label: 'Fin de la prueba',
                        hint: 'Elige una fecha',
                        suffixIcon: const Icon(Icons.event_outlined, size: 18),
                        readOnly: true,
                        validator: (_) => _esPrueba && _finPrueba == null
                            ? 'Elige cuándo termina la prueba'
                            : null,
                        onTap: () async {
                          final fecha = await _elegirFecha(_finPrueba ?? _fecha);
                          if (fecha != null) setState(() => _ponerFinPrueba(fecha));
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: const BoxDecoration(
              color: AppColors.panel,
              border: Border(top: BorderSide(color: AppColors.divider)),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton(
                    onPressed: _guardando ? null : _guardar,
                    child: _guardando
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : Text(_editando ? 'Guardar cambios' : 'Guardar suscripción'),
                  ),
                  if (_editando) ...[
                    const SizedBox(height: 4),
                    TextButton(
                      onPressed: _guardando ? null : _eliminar,
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.error,
                        minimumSize: const Size.fromHeight(42),
                        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                      ),
                      child: const Text('Eliminar suscripción'),
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

/// Píldoras con las categorías del diseño, más "Sin categoría".
class _SelectorCategoria extends StatelessWidget {
  const _SelectorCategoria({required this.seleccion, required this.onChanged});

  final String? seleccion;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final opciones = <(String?, String)>[
      (null, 'Sin categoría'),
      for (final c in Suscripcion.categorias) (c, c),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (valor, texto) in opciones)
          Semantics(
            selected: valor == seleccion,
            button: true,
            child: TextButton(
              onPressed: () => onChanged(valor),
              style: TextButton.styleFrom(
                backgroundColor: valor == seleccion ? AppColors.primary : Colors.transparent,
                foregroundColor: valor == seleccion ? Colors.white : AppColors.textSoft,
                side: valor == seleccion
                    ? BorderSide.none
                    : const BorderSide(color: AppColors.lineStrong),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
              ),
              child: Text(texto),
            ),
          ),
      ],
    );
  }
}
