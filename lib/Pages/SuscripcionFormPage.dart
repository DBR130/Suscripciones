import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../Common/AppTheme.dart';
import '../models/suscripcion.dart';
import '../services/api_client.dart';
import '../services/suscripcion_service.dart';
import '../utils/formato.dart';
import '../widgets/app_botones.dart';
import '../widgets/app_card.dart';
import '../widgets/app_header.dart';
import '../widgets/app_text_field.dart';

/// Agregar o editar una suscripción manual (pantalla 13 del diseño).
/// Con [inicial] edita esa suscripción; sin ella, crea una nueva.
/// Al guardar vuelve con la suscripción guardada como resultado.
class SuscripcionFormPage extends StatefulWidget {
  const SuscripcionFormPage({
    super.key,
    required this.suscripcionService,
    this.inicial,
  });

  final SuscripcionService suscripcionService;
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

  String _moneda = 'COP';
  Frecuencia _frecuencia = Frecuencia.mensual;
  DateTime? _fecha;
  bool _esPrueba = false;
  DateTime? _finPrueba;
  int? _diasAviso; // null = preferencia global
  bool _guardando = false;

  bool get _editando => widget.inicial != null;

  @override
  void initState() {
    super.initState();
    final s = widget.inicial;
    if (s != null) {
      _nombreCtrl.text = s.nombreServicio;
      _montoCtrl.text = Formato.montoParaEditar(s.monto, s.moneda);
      _moneda = s.moneda;
      _frecuencia = s.frecuencia;
      _esPrueba = s.esPruebaGratis;
      _diasAviso = s.diasAviso;
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
    _finPrueba = fecha;
    _finPruebaCtrl.text = Formato.fecha(fecha);
  }

  Future<DateTime?> _elegirFecha(DateTime? actual) {
    final hoy = DateUtils.dateOnly(DateTime.now());
    return showDatePicker(
      context: context,
      initialDate: actual ?? hoy,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100, 12, 31),
      helpText: 'Selecciona la fecha',
    );
  }

  String? _validarMonto(String? value) {
    if (value == null || value.trim().isEmpty) return 'Ingresa el monto';
    if (Formato.leerMonto(value, _moneda) == null) {
      return 'Monto no válido (máximo 2 decimales)';
    }
    return null;
  }

  Future<void> _guardar() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    final suscripcion = Suscripcion(
      id: widget.inicial?.id,
      nombreServicio: _nombreCtrl.text.trim(),
      monto: Formato.leerMonto(_montoCtrl.text, _moneda)!,
      moneda: _moneda,
      frecuencia: _frecuencia,
      fechaProximoCobro: _fecha!,
      esPruebaGratis: _esPrueba,
      fechaFinPrueba: _esPrueba ? _finPrueba : null,
      diasAviso: _diasAviso,
    );

    setState(() => _guardando = true);
    try {
      final guardada = _editando
          ? await widget.suscripcionService.actualizar(suscripcion)
          : await widget.suscripcionService.crear(suscripcion);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_editando ? 'Cambios guardados' : 'Suscripción agregada'),
        ),
      );
      context.pop(guardada);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _guardando = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.mensaje)));
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
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                children: [
                  AppTextField(
                    controller: _nombreCtrl,
                    label: 'Servicio',
                    hint: 'ej. HBO Max',
                    icon: Icons.subscriptions_outlined,
                    textInputAction: TextInputAction.next,
                    validator: (v) => v == null || v.trim().isEmpty
                        ? 'Ingresa el nombre del servicio'
                        : v.trim().length > 100
                            ? 'Máximo 100 caracteres'
                            : null,
                  ),
                  const SizedBox(height: 14),
                  AppTextField(
                    controller: _montoCtrl,
                    label: 'Monto ($_moneda)',
                    hint: _moneda == 'COP' ? '24900' : '9.99',
                    icon: Icons.payments_outlined,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    validator: _validarMonto,
                  ),
                  const SizedBox(height: 18),
                  const AppEtiqueta('Moneda'),
                  const SizedBox(height: 7),
                  AppPills<String>(
                    opciones: const [('COP', 'COP'), ('USD', 'USD')],
                    seleccion: _moneda,
                    onChanged: (m) => setState(() => _moneda = m),
                  ),
                  const SizedBox(height: 18),
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
                  const SizedBox(height: 18),
                  AppTextField(
                    controller: _fechaCtrl,
                    label: 'Próximo cobro',
                    hint: 'dd/mm/aaaa',
                    icon: Icons.calendar_today_outlined,
                    readOnly: true,
                    validator: (_) => _fecha == null ? 'Elige la fecha del próximo cobro' : null,
                    onTap: () async {
                      final fecha = await _elegirFecha(_fecha);
                      if (fecha != null) setState(() => _ponerFecha(fecha));
                    },
                  ),
                  const SizedBox(height: 14),
                  AppCard(
                    padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _esPrueba,
                      onChanged: (v) => setState(() => _esPrueba = v),
                      activeTrackColor: AppColors.primary,
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
                      hint: 'dd/mm/aaaa',
                      icon: Icons.event_outlined,
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
                  const SizedBox(height: 18),
                  const AppEtiqueta('Recordatorio de esta suscripción'),
                  const SizedBox(height: 4),
                  const Text(
                    'Global usa tu preferencia de Configuración',
                    style: TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  AppPills<int?>(
                    opciones: const [(null, 'Global'), (1, '1 día'), (3, '3 días'), (7, '7 días')],
                    seleccion: _diasAviso,
                    onChanged: (d) => setState(() => _diasAviso = d),
                  ),
                ],
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
              child: FilledButton(
                onPressed: _guardando ? null : _guardar,
                child: _guardando
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Guardar suscripción'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
