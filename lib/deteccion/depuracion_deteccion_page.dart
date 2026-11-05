import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../Common/AppTheme.dart';
import '../services/recordatorios_service.dart';
import '../utils/formato.dart';
import '../widgets/app_botones.dart';
import '../widgets/app_card.dart';
import '../widgets/app_feedback.dart';
import '../widgets/app_header.dart';
import '../widgets/guia_xiaomi.dart';
import 'analizador_pagos.dart';
import 'catalogo_servicios.dart';
import 'lector_notificaciones.dart';
import 'notificacion_capturada.dart';
import 'parser_pagos.dart';

/// Comando de ejemplo para simular un pago desde el PC, en PowerShell (ver
/// docs/deteccion.md). La comilla invertida antes del signo de pesos evita que
/// PowerShell lo interprete, y las comillas simples protegen el texto en el
/// shell del celular.
const comandoSimulacion = r'''adb shell "cmd notification post -S bigtext -t 'Bancolombia' pago1 'Bancolombia: Compraste `$19.900,00 en GOOGLE *Crunchyroll con tu T.Deb *0000, el 23/10/2026 a las 07:20.'"''';

/// Pantalla de depuración del lector (solo en modo debug): estado del
/// permiso, apps permitidas, notificaciones en vivo y cola guardada con lo que
/// extrae el parser (hito 2). Sirve para identificar los paquetes del banco y
/// de la app de SMS del celular y para probar el parser con cobros reales.
class DepuracionDeteccionPage extends StatefulWidget {
  const DepuracionDeteccionPage({
    super.key,
    required this.lector,
    this.recordatorios,
    this.cargarCatalogo,
    this.diagnostico,
  });

  final LectorNotificaciones lector;

  /// Para la guía de Xiaomi (abrir Inicio automático y ajustes de la app).
  final RecordatoriosService? recordatorios;

  /// Catálogo de servicios para normalizar comercios (GET /api/guias). Si
  /// falla, el parser funciona igual, sin reconocer servicios.
  final Future<CatalogoServicios> Function()? cargarCatalogo;

  /// "Último escaneo": cada comercio que agrupó el análisis, con su decisión
  /// (ProcesadorDetecciones.ultimoDiagnostico).
  final ValueListenable<List<DiagnosticoComercio>>? diagnostico;

  @override
  State<DepuracionDeteccionPage> createState() => _DepuracionDeteccionPageState();
}

class _DepuracionDeteccionPageState extends State<DepuracionDeteccionPage> with WidgetsBindingObserver {
  static const _maxEventos = 50;

  EstadoLector _estado = EstadoLector.noDisponible;
  ConfiguracionLector? _config;
  List<NotificacionCapturada> _cola = const [];
  final List<EventoDeteccion> _enVivo = [];
  StreamSubscription<EventoDeteccion>? _suscripcion;
  bool _xiaomi = false;
  ParserPagos _parser = const ParserPagos();

  /// null mientras carga; si no se pudo cargar, el motivo.
  String? _errorCatalogo;
  bool _catalogoCargado = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _cargarCatalogo();
    _suscripcion = widget.lector.eventos().listen(_alLlegar, onError: (Object e) => debugPrint('Lector: $e'));
    _actualizar();
    widget.recordatorios?.esXiaomi().then((v) {
      if (mounted) setState(() => _xiaomi = v);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _suscripcion?.cancel();
    // El modo descubrimiento solo vive mientras esta pantalla está abierta.
    if (_estado.modoDescubrimiento) widget.lector.cambiarModoDescubrimiento(false);
    super.dispose();
  }

  /// Al volver de los ajustes de Android, el permiso pudo cambiar.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _actualizar();
  }

  void _alLlegar(EventoDeteccion evento) {
    if (!mounted) return;
    setState(() {
      _enVivo.insert(0, evento);
      if (_enVivo.length > _maxEventos) _enVivo.removeLast();
    });
    if (evento.tipo == TipoEvento.guardada) _actualizar();
  }

  Future<void> _actualizar() async {
    await widget.lector.reconectarSiHaceFalta();
    final recuperadas = await widget.lector.recuperarActivas();
    if (mounted && recuperadas != null && recuperadas > 0) {
      mostrarToast(context, 'Se recuperaron $recuperadas de la barra de notificaciones');
    }
    final estado = await widget.lector.estado();
    final config = await widget.lector.configuracion();
    final cola = await widget.lector.leerCola();
    if (!mounted) return;
    setState(() {
      _estado = estado;
      _config = config;
      _cola = cola.reversed.toList(); // más recientes primero
    });
  }

  Future<void> _cargarCatalogo() async {
    final cargar = widget.cargarCatalogo;
    if (cargar == null) return;
    try {
      final catalogo = await cargar();
      if (!mounted) return;
      setState(() {
        _parser = ParserPagos(catalogo);
        _catalogoCargado = true;
      });
    } catch (e) {
      if (mounted) setState(() => _errorCatalogo = '$e');
    }
  }

  Future<void> _cambiarDescubrimiento(bool activo) async {
    final resultado = await widget.lector.cambiarModoDescubrimiento(activo);
    if (!mounted) return;
    setState(() => _estado = _estado.conDescubrimiento(resultado));
  }

  Future<void> _vaciar() async {
    await widget.lector.vaciarCola();
    if (!mounted) return;
    mostrarToast(context, 'Cola vaciada');
    _actualizar();
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
                const Text(
                  'Depuración: detección',
                  style: TextStyle(color: AppColors.text, fontSize: 21, fontWeight: FontWeight.w800, letterSpacing: -0.5),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Lector de notificaciones · solo en modo debug',
                  style: TextStyle(color: AppColors.mutedHero, fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          Expanded(child: _cuerpo()),
        ],
      ),
    );
  }

  Widget _cuerpo() {
    if (!kDebugMode || !widget.lector.disponible) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Esta pantalla solo existe en modo debug y en Android.',
          style: TextStyle(color: AppColors.muted),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _actualizar,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _tarjetaEstado(),
          const SizedBox(height: 14),
          _tarjetaApps(),
          const SizedBox(height: 14),
          if (widget.diagnostico case final diagnostico?)
            ValueListenableBuilder(
              valueListenable: diagnostico,
              builder: (context, comercios, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Seccion('Último escaneo (${comercios.length} ${comercios.length == 1 ? 'comercio' : 'comercios'})'),
                  if (comercios.isEmpty)
                    const _Vacio('Haz un escaneo (pantalla 04 o "Buscar suscripciones en mis SMS") para ver qué '
                        'decidió el análisis con cada comercio.')
                  else
                    for (final c in comercios) ...[_TarjetaDiagnostico(c), const SizedBox(height: 8)],
                  const SizedBox(height: 14),
                ],
              ),
            ),
          _Seccion('En vivo (${_enVivo.length})'),
          if (_enVivo.isEmpty)
            const _Vacio('Deja esta pantalla abierta y llegará aquí cada notificación que procese el lector.')
          else
            for (final e in _enVivo) ...[_TarjetaEvento(e), const SizedBox(height: 8)],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _Seccion('Cola guardada (${_cola.length})')),
              if (_cola.isNotEmpty)
                TextButton(onPressed: _vaciar, child: const Text('Vaciar cola')),
            ],
          ),
          if (_cola.isEmpty)
            const _Vacio('Aquí quedan los cobros que llegan con la app cerrada; Flutter los lee al abrirse.')
          else
            for (final n in _cola) ...[
              _TarjetaNotificacion(n, _parser.interpretarNotificacion(n)),
              const SizedBox(height: 8),
            ],
          const SizedBox(height: 14),
          _tarjetaSimulacion(),
          if (_xiaomi && widget.recordatorios != null) ...[
            const SizedBox(height: 14),
            GuiaXiaomi(
              titulo: 'En Xiaomi, activa esto para que el lector no se detenga',
              onInicioAutomatico: widget.recordatorios!.abrirInicioAutomatico,
              onAjustes: widget.recordatorios!.abrirAjustesApp,
            ),
          ],
        ],
      ),
    );
  }

  Widget _tarjetaEstado() {
    final e = _estado;
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilaDato('Acceso a notificaciones', e.permiso ? 'Concedido' : 'No concedido'),
          FilaDato('Servicio ahora', e.conectado ? 'Conectado' : 'Desconectado'),
          FilaDato('Última conexión', _horaONunca(e.ultimaConexion)),
          FilaDato('Última desconexión', _horaONunca(e.ultimaDesconexion)),
          FilaDato(
            'Última notificación recibida',
            e.ultimaNotificacion == null
                ? 'Ninguna'
                : '${_hora(e.ultimaNotificacion!)} (${e.ultimoResultado ?? '?'})',
          ),
          FilaDato(
            'App de SMS predeterminada',
            e.appSmsPaquete == null ? 'Ninguna' : '${e.appSmsNombre ?? e.appSmsPaquete} (${e.appSmsPaquete})',
          ),
          // Tarea de fondo (WorkManager). En dos líneas: la etiqueta es larga
          // y el motivo puede serlo también.
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.divider))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Última ejecución en segundo plano',
                  style: TextStyle(color: AppColors.muted, fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  e.ultimaEjecucionFondo == null
                      ? 'Nunca'
                      : [
                          _hora(e.ultimaEjecucionFondo!),
                          e.resultadoFondo ?? '?',
                          '${e.procesadosFondo} revisadas',
                          ?e.motivoFondo,
                        ].join(' · '),
                  style: const TextStyle(color: AppColors.text, fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          if (e.ultimaReconexion != null)
            FilaDato('Reconexión forzada', '${_hora(e.ultimaReconexion!)} (${e.resultadoReconexion ?? '?'})'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: e.modoDescubrimiento,
            onChanged: e.permiso ? _cambiarDescubrimiento : null,
            activeTrackColor: AppColors.primary,
            title: const Text(
              'Modo descubrimiento',
              style: TextStyle(color: AppColors.text, fontSize: 13.5, fontWeight: FontWeight.w700),
            ),
            subtitle: const Text(
              'De las apps que no están en la lista muestra solo el paquete, sin leer su título '
              'ni su texto. Úsalo para encontrar el paquete del banco y de la app de SMS.',
              style: TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w600, height: 1.4),
            ),
          ),
          if (e.permiso && !e.conectado)
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Text(
                'Android detuvo el lector. Toca "Actualizar" para pedir que se reconecte y '
                'revisa la guía de Xiaomi más abajo.',
                style: TextStyle(color: AppColors.amber, fontSize: 12.5, fontWeight: FontWeight.w700),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Expanded(
                  child: AppBotonSecundario(
                    texto: e.permiso ? 'Ver acceso' : 'Dar acceso',
                    onPressed: widget.lector.abrirAjustesAcceso,
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(child: AppBotonSecundario(texto: 'Actualizar', onPressed: _actualizar)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tarjetaApps() {
    final apps = _config?.apps ?? const [];
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Apps permitidas',
            style: TextStyle(color: AppColors.text, fontSize: 13.5, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          const Text(
            'android/app/src/main/res/raw/deteccion_apps.json, más la app de SMS predeterminada',
            style: TextStyle(color: AppColors.muted, fontSize: 11.5, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          for (final a in apps)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: SelectableText(
                '${a.paquete} · ${a.nombre}',
                style: const TextStyle(color: AppColors.text2, fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
            ),
          if (apps.every((a) => a.paquete == 'com.android.shell'))
            const Text(
              'Todavía no hay apps reales: activa el modo descubrimiento, recibe un SMS o una '
              'notificación del banco y agrega su paquete al archivo.',
              style: TextStyle(color: AppColors.amber, fontSize: 12.5, fontWeight: FontWeight.w700, height: 1.4),
            ),
          const SizedBox(height: 6),
          Text(
            _catalogoCargado
                ? 'Catálogo de servicios: ${_parser.catalogo.servicios.length} (de /api/guias)'
                : _errorCatalogo != null
                    ? 'Sin catálogo de servicios ($_errorCatalogo): el parser limpia el comercio '
                        'pero no lo reconoce como servicio.'
                    : 'Cargando el catálogo de servicios…',
            style: TextStyle(
              color: _errorCatalogo != null ? AppColors.amber : AppColors.muted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _tarjetaSimulacion() {
    return const AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Simular un pago desde el PC (PowerShell)',
            style: TextStyle(color: AppColors.text, fontSize: 13.5, fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 8),
          SelectableText(
            comandoSimulacion,
            style: TextStyle(color: AppColors.text2, fontSize: 12, fontFamily: 'monospace', height: 1.4),
          ),
          SizedBox(height: 8),
          Text(
            'Cambia "pago1" por otro nombre para cada prueba. Más ejemplos en docs/deteccion.md.',
            style: TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

String _horaONunca(DateTime? d) => d == null ? 'Nunca' : _hora(d);

String _hora(DateTime d) {
  String dos(int n) => n.toString().padLeft(2, '0');
  return '${dos(d.day)}/${dos(d.month)} ${dos(d.hour)}:${dos(d.minute)}:${dos(d.second)}';
}

class _Seccion extends StatelessWidget {
  const _Seccion(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 9),
      child: Text(texto, style: const TextStyle(color: AppColors.text, fontSize: 13.5, fontWeight: FontWeight.w800)),
    );
  }
}

class _Vacio extends StatelessWidget {
  const _Vacio(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Text(texto, style: const TextStyle(color: AppColors.muted, fontSize: 12.5, height: 1.45));
  }
}

class _TarjetaNotificacion extends StatelessWidget {
  const _TarjetaNotificacion(this.n, this.interpretacion);

  final NotificacionCapturada n;
  final InterpretacionPago interpretacion;

  static final _numero = NumberFormat('#,##0.##', 'es_CO');

  @override
  Widget build(BuildContext context) {
    final p = interpretacion.pago;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SelectableText.rich(
            TextSpan(
              style: const TextStyle(color: AppColors.text2, fontSize: 12.5, height: 1.45),
              children: [
                TextSpan(
                  text: '${n.app} · ${_hora(n.recibidaEn)}\n',
                  style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w700),
                ),
                TextSpan(text: '${n.paquete}\n', style: const TextStyle(color: AppColors.muted)),
                if (n.titulo.isNotEmpty)
                  TextSpan(text: '${n.titulo}\n', style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w700)),
                TextSpan(text: n.texto),
              ],
            ),
          ),
          const Divider(height: 20, color: AppColors.divider),
          if (p == null)
            Text(
              'No es un cobro (${interpretacion.motivo})',
              style: const TextStyle(color: AppColors.amber, fontSize: 12.5, fontWeight: FontWeight.w700),
            )
          else ...[
            const Text(
              'EXTRAÍDO POR EL PARSER',
              style: TextStyle(color: AppColors.link, fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: 0.5),
            ),
            const SizedBox(height: 4),
            _Extraido('Banco', p.banco),
            _Extraido('Monto', '${_numero.format(p.monto)} ${p.moneda}'),
            _Extraido(
              'Comercio',
              p.esServicioConocido ? '${p.comercio} (servicio conocido)' : '${p.comercio} (no está en el catálogo)',
            ),
            _Extraido('Original', p.comercioOriginal),
            _Extraido('Fecha', '${_fechaHora(p.fecha)} (${p.fechaDelMensaje ? 'del mensaje' : 'de llegada'})'),
            if (p.medio != null) _Extraido('Medio', p.medio!),
            if (p.indicaSuscripcion) const _Extraido('Indica', 'suscripción (SUB)'),
          ],
        ],
      ),
    );
  }
}

class _Extraido extends StatelessWidget {
  const _Extraido(this.clave, this.valor);

  final String clave;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(clave, style: const TextStyle(color: AppColors.muted, fontSize: 12.5, fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Text(valor, style: const TextStyle(color: AppColors.text, fontSize: 12.5, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

String _fechaHora(DateTime d) {
  String dos(int n) => n.toString().padLeft(2, '0');
  return '${dos(d.day)}/${dos(d.month)}/${d.year} ${dos(d.hour)}:${dos(d.minute)}';
}

class _TarjetaEvento extends StatelessWidget {
  const _TarjetaEvento(this.e);

  final EventoDeteccion e;

  @override
  Widget build(BuildContext context) {
    final (etiqueta, color, detalle) = switch (e.tipo) {
      TipoEvento.guardada => ('GUARDADA', AppColors.link, e.notificacion!.texto),
      TipoEvento.descartada => ('DESCARTADA', AppColors.amber, 'No se guardó: ${e.motivo}'),
      TipoEvento.descubierta => ('APP NO PERMITIDA', AppColors.muted, 'Texto no leído (la app no está en la lista).'),
    };
    return AppCard(
      child: SelectableText.rich(
        TextSpan(
          style: const TextStyle(color: AppColors.text2, fontSize: 12.5, height: 1.45),
          children: [
            TextSpan(
              text: '$etiqueta · ${_hora(e.recibidaEn)}\n',
              style: TextStyle(color: color, fontWeight: FontWeight.w800, letterSpacing: 0.5),
            ),
            TextSpan(text: '${e.paquete}\n', style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w700)),
            TextSpan(text: detalle, style: const TextStyle(color: AppColors.muted)),
          ],
        ),
      ),
    );
  }
}

/// Un comercio del último escaneo: banco, cobros, montos, fechas y la decisión
/// con su motivo. Solo campos extraídos.
class _TarjetaDiagnostico extends StatelessWidget {
  const _TarjetaDiagnostico(this.comercio);

  final DiagnosticoComercio comercio;

  @override
  Widget build(BuildContext context) {
    final c = comercio;
    final cobros = c.cobros == 1 ? '1 cobro' : '${c.cobros} cobros';
    final montos = c.montos.map((m) => Formato.moneda(m, c.moneda)).join(', ');
    final fechas = c.fechas.map(Formato.fechaCorta).join(', ');
    final repetidos = c.repetidos == 0 ? '' : ' · ${c.repetidos} repetido${c.repetidos == 1 ? '' : 's'}';
    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(c.nombre, style: const TextStyle(color: AppColors.text, fontSize: 13.5, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(
            '${c.bancos.join(', ')} · $cobros · $montos · $fechas',
            style: const TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            '${c.salen > 0 ? 'SALE' : 'NO SALE'} · ${c.motivo}$repetidos',
            style: TextStyle(
              color: c.salen > 0 ? AppColors.accentSoft : AppColors.amber,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
