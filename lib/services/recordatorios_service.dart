import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:timezone/data/latest_all.dart' as tz_datos;
import 'package:timezone/timezone.dart' as tz;

import '../models/suscripcion.dart';
import '../utils/formato.dart';
import 'suscripcion_service.dart';

/// Un recordatorio que hay que programar (sin depender del plugin, para
/// poder probar el cálculo en test/recordatorios_test.dart).
class RecordatorioPlan {
  const RecordatorioPlan({
    required this.id,
    required this.cuando,
    required this.titulo,
    required this.cuerpo,
    required this.payload,
  });

  final int id;

  /// Fecha y hora en Colombia (sin zona horaria).
  final DateTime cuando;
  final String titulo;
  final String cuerpo;

  /// Id de la suscripción a abrir al tocarla, o '' para el dashboard.
  final String payload;
}

const int _horaAviso = 9; // 9:00 a. m.
const int idResumenMensual = 1;
const int idPrueba = 2;

/// Calcula los recordatorios (RF06, RF07, RF12):
/// - Próximo cobro: 9:00 del día (cobro - días de aviso).
/// - Fin de prueba gratis: 9:00 del día (fin - días de aviso).
/// - Resumen mensual: día 1 del próximo mes a las 9:00.
/// Nunca en el pasado: si la hora del aviso ya pasó pero el cobro no, se
/// programa en 1 minuto. Los días de aviso son los de la suscripción o, si
/// no tiene, [diasGlobales].
List<RecordatorioPlan> planificarRecordatorios(
  List<Suscripcion> suscripciones,
  int diasGlobales,
  DateTime ahora, {
  bool resumenMensual = true,
}) {
  final hoy = DateTime(ahora.year, ahora.month, ahora.day);
  final planes = <RecordatorioPlan>[];

  int diasEntre(DateTime desde, DateTime hasta) =>
      DateTime.utc(hasta.year, hasta.month, hasta.day)
          .difference(DateTime.utc(desde.year, desde.month, desde.day))
          .inDays;

  final enCurso = suscripciones.where((s) => s.estado != EstadoSuscripcion.cancelada && s.id != null);
  for (final s in enCurso) {
    final esPrueba = s.esPruebaGratis && s.fechaFinPrueba != null;
    final evento = esPrueba ? s.fechaFinPrueba! : s.fechaProximoCobro;
    if (evento.isBefore(hoy)) continue; // ya pasó: no se avisa

    final dias = s.diasAvisoEfectivos(diasGlobales);
    var cuando = DateTime(evento.year, evento.month, evento.day - dias, _horaAviso);
    if (cuando.isBefore(ahora)) cuando = ahora.add(const Duration(minutes: 1));
    final faltan = Formato.enDias(diasEntre(cuando, evento));
    final monto = s.montoTexto;

    planes.add(esPrueba
        ? RecordatorioPlan(
            id: s.id! * 10 + 2,
            cuando: cuando,
            titulo: 'Fin de prueba gratis',
            cuerpo: 'Tu prueba de ${s.nombreServicio} termina $faltan: '
                'luego se cobran $monto${s.frecuencia.sufijo}',
            payload: '${s.id}',
          )
        : RecordatorioPlan(
            id: s.id! * 10 + 1,
            cuando: cuando,
            titulo: 'Próximo cobro',
            cuerpo: '${s.nombreServicio} te cobra $monto $faltan',
            payload: '${s.id}',
          ));
  }

  if (resumenMensual) {
    // Gasto mensual equivalente por moneda (las pruebas gratis suman 0).
    final porMoneda = <String, double>{};
    for (final s in enCurso.where((s) => !s.esPruebaGratis)) {
      porMoneda[s.moneda] = (porMoneda[s.moneda] ?? 0) + s.monto * s.frecuencia.cobrosPorAnio / 12;
    }
    if (porMoneda.isNotEmpty) {
      final cuando = ahora.day == 1 && ahora.hour < _horaAviso
          ? DateTime(ahora.year, ahora.month, 1, _horaAviso)
          : DateTime(ahora.year, ahora.month + 1, 1, _horaAviso);
      final total = porMoneda.entries.map((e) => Formato.moneda(e.value, e.key)).join(' + ');
      planes.add(RecordatorioPlan(
        id: idResumenMensual,
        cuando: cuando,
        titulo: 'Resumen mensual',
        cuerpo: 'Este mes tus suscripciones suman $total. Revisa tu lista en SubTrack.',
        payload: '',
      ));
    }
  }
  return planes;
}

/// Recordatorios locales en el celular con flutter_local_notifications.
///
/// - En web (Chrome) no hace nada: [disponible] es false.
/// - Usa alarmas inexactas (inexactAllowWhileIdle), que no necesitan el
///   permiso SCHEDULE_EXACT_ALARM; pueden llegar unos minutos tarde.
/// - Cada vez que cambia la lista o se abre la app, [reprogramar] borra los
///   pendientes y los vuelve a programar.
class RecordatoriosService {
  RecordatoriosService({
    FlutterLocalNotificationsPlugin? plugin,
    FlutterSecureStorage? storage,
  })  : _plugin = plugin ?? FlutterLocalNotificationsPlugin(),
        _storage = storage ?? const FlutterSecureStorage();

  static const String zonaHoraria = 'America/Bogota';
  static const _sistema = MethodChannel('subtrack/sistema');
  static const _claveActivos = 'recordatorios_activos';
  static const _claveResumen = 'resumen_mensual';

  static const _detalles = NotificationDetails(
    android: AndroidNotificationDetails(
      'recordatorios',
      'Recordatorios de cobro',
      channelDescription: 'Avisos antes de cada cobro, del fin de las pruebas gratis y resumen mensual',
      importance: Importance.high,
      priority: Priority.high,
      icon: 'ic_notificacion',
    ),
  );

  final FlutterLocalNotificationsPlugin _plugin;
  final FlutterSecureStorage _storage;
  bool _iniciado = false;
  late final tz.Location _colombia;

  /// Se llama al tocar una notificación: id de la suscripción, o null para
  /// abrir el dashboard. main.dart lo conecta con el router.
  void Function(int? suscripcionId)? onAbrir;

  /// Solo Android (la entrega). En web y escritorio no se programa nada.
  bool get disponible => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  Future<void> inicializar() async {
    if (!disponible || _iniciado) return;
    tz_datos.initializeTimeZones();
    _colombia = tz.getLocation(zonaHoraria);
    tz.setLocalLocation(_colombia);
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_notificacion'),
      ),
      onDidReceiveNotificationResponse: (respuesta) =>
          onAbrir?.call(int.tryParse(respuesta.payload ?? '')),
    );
    _iniciado = true;
  }

  /// Si la app se abrió tocando una notificación, el id de la suscripción.
  Future<int?> suscripcionQueAbrioLaApp() async {
    if (!disponible) return null;
    await inicializar();
    final detalles = await _plugin.getNotificationAppLaunchDetails();
    if (detalles == null || !detalles.didNotificationLaunchApp) return null;
    return int.tryParse(detalles.notificationResponse?.payload ?? '');
  }

  // ─── Preferencias guardadas en el celular ───────────────────────────────

  Future<bool> activos() async => await _storage.read(key: _claveActivos) != 'no';

  Future<void> cambiarActivos(bool activos) async {
    await _storage.write(key: _claveActivos, value: activos ? 'si' : 'no');
    if (!activos && disponible) {
      await inicializar();
      await _plugin.cancelAllPendingNotifications();
    }
  }

  Future<bool> resumenMensual() async => await _storage.read(key: _claveResumen) != 'no';

  Future<void> cambiarResumenMensual(bool activo) =>
      _storage.write(key: _claveResumen, value: activo ? 'si' : 'no');

  // ─── Permiso (Android 13+) ──────────────────────────────────────────────

  Future<bool> tienePermiso() async {
    if (!disponible) return false;
    await inicializar();
    return await _android?.areNotificationsEnabled() ?? false;
  }

  /// Muestra el diálogo del sistema. Devuelve true si quedó concedido.
  Future<bool> pedirPermiso() async {
    if (!disponible) return false;
    await inicializar();
    return await _android?.requestNotificationsPermission() ?? false;
  }

  // ─── Programación ───────────────────────────────────────────────────────

  Future<void> reprogramar(List<Suscripcion> suscripciones, int diasGlobales) async {
    if (!disponible) return;
    await inicializar();
    // Solo los pendientes: las notificaciones ya mostradas se quedan.
    await _plugin.cancelAllPendingNotifications();
    if (!await activos()) return;

    final ahora = tz.TZDateTime.now(_colombia);
    final planes = planificarRecordatorios(
      suscripciones,
      diasGlobales,
      DateTime(ahora.year, ahora.month, ahora.day, ahora.hour, ahora.minute, ahora.second),
      resumenMensual: await resumenMensual(),
    );
    for (final p in planes) {
      await _plugin.zonedSchedule(
        id: p.id,
        title: p.titulo,
        body: p.cuerpo,
        payload: p.payload,
        scheduledDate: tz.TZDateTime(
          _colombia, p.cuando.year, p.cuando.month, p.cuando.day, p.cuando.hour, p.cuando.minute, p.cuando.second,
        ),
        notificationDetails: _detalles,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }

  /// Pide al servidor la lista y los días de aviso y reprograma. Lo usan las
  /// pantallas que cambian una suscripción (detalle, formulario, perfil).
  /// Los errores se ignoran: se reintenta la próxima vez que abra la app.
  Future<void> sincronizar(SuscripcionService suscripcionService) async {
    if (!disponible) return;
    try {
      final suscripciones = await suscripcionService.listar(estados: const [
        EstadoSuscripcion.activa,
        EstadoSuscripcion.marcadaParaCancelar,
      ]);
      final resumen = await suscripcionService.resumen();
      await reprogramar(suscripciones, resumen.diasAnticipacion);
    } catch (e) {
      debugPrint('No se pudieron reprogramar los recordatorios: $e');
    }
  }

  /// Notificación de ejemplo en 10 segundos (para la demostración).
  Future<void> probarAviso() async {
    if (!disponible) return;
    await inicializar();
    await _plugin.zonedSchedule(
      id: idPrueba,
      title: 'Próximo cobro',
      body: 'Así te avisaremos: Netflix te cobra \$38.900 en 3 días',
      payload: '',
      scheduledDate: tz.TZDateTime.now(_colombia).add(const Duration(seconds: 10)),
      notificationDetails: _detalles,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  /// Al cerrar sesión o eliminar la cuenta: borra pendientes y mostradas.
  Future<void> cancelarTodo() async {
    if (!disponible) return;
    await inicializar();
    await _plugin.cancelAll();
  }

  // ─── Ajustes del sistema (MainActivity.kt) ──────────────────────────────

  /// true en Xiaomi, Redmi y POCO (HyperOS/MIUI cierra apps en segundo plano).
  Future<bool> esXiaomi() async {
    if (!disponible) return false;
    try {
      final fabricante = await _sistema.invokeMethod<String>('fabricante') ?? '';
      return RegExp('xiaomi|redmi|poco', caseSensitive: false).hasMatch(fabricante);
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Abre la pantalla de información de la app (permisos, batería...).
  Future<void> abrirAjustesApp() => _invocar('abrirAjustesApp');

  /// Abre "Inicio automático" de Xiaomi; si no existe, los ajustes de la app.
  Future<void> abrirInicioAutomatico() => _invocar('abrirInicioAutomatico');

  Future<void> _invocar(String metodo) async {
    if (!disponible) return;
    try {
      await _sistema.invokeMethod<bool>(metodo);
    } on PlatformException {
      // Sin esa pantalla en este celular: no hay nada más que hacer.
    } on MissingPluginException {
      // Sin la parte nativa (por ejemplo, en tests).
    }
  }
}
