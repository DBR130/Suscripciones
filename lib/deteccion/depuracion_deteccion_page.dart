import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../Common/AppTheme.dart';
import '../services/recordatorios_service.dart';
import '../widgets/app_botones.dart';
import '../widgets/app_card.dart';
import '../widgets/app_feedback.dart';
import '../widgets/app_header.dart';
import '../widgets/guia_xiaomi.dart';
import 'lector_notificaciones.dart';
import 'notificacion_capturada.dart';

/// Comando de ejemplo para simular un pago desde el PC, en PowerShell (ver
/// docs/deteccion.md). La comilla invertida antes del signo de pesos evita que
/// PowerShell lo interprete, y las comillas simples protegen el texto en el
/// shell del celular.
const comandoSimulacion = r'''adb shell "cmd notification post -S bigtext -t 'Bancolombia' pago1 'Bancolombia: Compraste `$19.900,00 en GOOGLE *Crunchyroll con tu T.Deb *0000, el 23/10/2026 a las 07:20.'"''';

/// Pantalla de depuración del lector (hito 1, solo en modo debug): estado del
/// permiso, apps permitidas, notificaciones en vivo y cola guardada. Sirve
/// para identificar los paquetes del banco y de la app de SMS del celular.
class DepuracionDeteccionPage extends StatefulWidget {
  const DepuracionDeteccionPage({super.key, required this.lector, this.recordatorios});

  final LectorNotificaciones lector;

  /// Para la guía de Xiaomi (abrir Inicio automático y ajustes de la app).
  final RecordatoriosService? recordatorios;

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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

  Future<void> _cambiarDescubrimiento(bool activo) async {
    final resultado = await widget.lector.cambiarModoDescubrimiento(activo);
    if (!mounted) return;
    setState(() => _estado = EstadoLector(
          permiso: _estado.permiso,
          conectado: _estado.conectado,
          esDebug: _estado.esDebug,
          modoDescubrimiento: resultado,
        ));
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
            for (final n in _cola) ...[_TarjetaNotificacion(n), const SizedBox(height: 8)],
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
          FilaDato('Servicio', e.conectado ? 'Conectado' : 'Desconectado'),
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
              'Muestra el paquete y el título de cualquier notificación que llegue, sin leer '
              'ni guardar su texto. Úsalo para encontrar el paquete del banco y de la app de SMS.',
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
            'android/app/src/main/res/raw/deteccion_apps.json',
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
  const _TarjetaNotificacion(this.n);

  final NotificacionCapturada n;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: SelectableText.rich(
        TextSpan(
          style: const TextStyle(color: AppColors.text2, fontSize: 12.5, height: 1.45),
          children: [
            TextSpan(
              text: '${n.app} · ${_hora(n.recibidaEn)}\n',
              style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.w700),
            ),
            TextSpan(text: '${n.paquete}\n', style: const TextStyle(color: AppColors.muted)),
            TextSpan(text: '${n.titulo}\n', style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w700)),
            TextSpan(text: n.texto),
          ],
        ),
      ),
    );
  }
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
            if (e.titulo.isNotEmpty) TextSpan(text: '${e.titulo}\n'),
            TextSpan(text: detalle, style: const TextStyle(color: AppColors.muted)),
          ],
        ),
      ),
    );
  }
}
