import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_suscripciones/deteccion/almacen_pagos_locales.dart';
import 'package:flutter_suscripciones/deteccion/catalogo_servicios.dart';
import 'package:flutter_suscripciones/deteccion/deteccion_service.dart';
import 'package:flutter_suscripciones/deteccion/lector_notificaciones.dart';
import 'package:flutter_suscripciones/deteccion/procesador_detecciones.dart';
import 'package:flutter_suscripciones/services/api_client.dart';
import 'package:flutter_suscripciones/services/recordatorios_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'deteccion_flujo_test.dart' show FakeDeteccionService, candidato;

/// Aviso "Registramos un pago de X en Y" (ticket T8) y el título del flujo B
/// para un procesador.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('qué cuenta como pago registrado', () {
    setUp(() => FlutterSecureStorage.setMockInitialValues({'auth_token': 'tok'}));

    test('solo los registrados en una suscripción: nada si es repetido, compra normal o descartado', () async {
      Map<String, Object?> resultado(String r, {String? nombre, num? monto, num? antes}) => {
            'huella': 'h',
            'resultado': r,
            'nombre_servicio': nombre,
            'monto': monto,
            'moneda': monto == null ? null : 'COP',
            'monto_anterior': antes,
          };
      final api = ApiClient(
        client: MockClient((_) async => http.Response.bytes(
              utf8.encode(jsonEncode({
                'resultados': [
                  resultado('repetido'),
                  resultado('compra_normal'),
                  resultado('comercio_descartado'),
                  resultado('suscripcion_existente', nombre: 'Netflix', monto: 44900),
                  resultado('suscripcion_existente', nombre: 'Netflix', monto: 49900, antes: 44900),
                ],
                'candidatos_nuevos': [],
              })),
              200,
              headers: {'content-type': 'application/json'},
            )),
      );
      final r = await DeteccionService(api).enviarPagos([{'huella': 'h'}]);
      expect(r.nuevos, isEmpty);
      expect(
        [for (final p in r.registrados) (p.servicio, p.monto, p.montoAnterior)],
        [('Netflix', 44900.0, null), ('Netflix', 49900.0, 44900.0)],
      );
    });
  });

  group('textos del aviso', () {
    const netflix = PagoRegistrado(servicio: 'Netflix', monto: 44900, moneda: 'COP');

    test('un pago, una subida y una bajada', () {
      expect(avisosDePagosRegistrados([netflix]), [(titulo: 'Pago registrado', cuerpo: r'Registramos un pago de $44.900 en Netflix')]);
      expect(
        avisosDePagosRegistrados([const PagoRegistrado(servicio: 'Netflix', monto: 49900, moneda: 'COP', montoAnterior: 44900)]),
        [(titulo: 'Cambio de precio', cuerpo: r'Netflix subió de $44.900 a $49.900')],
      );
      expect(
        avisosDePagosRegistrados([const PagoRegistrado(servicio: 'Netflix', monto: 39900, moneda: 'COP', montoAnterior: 44900)]),
        [(titulo: 'Cambio de precio', cuerpo: r'Netflix bajó de $44.900 a $39.900')],
      );
    });

    test('3 o más en una misma revisión: un solo aviso de resumen', () {
      expect(avisosDePagosRegistrados([netflix, netflix, netflix]), [
        (titulo: 'Pagos registrados', cuerpo: 'Registramos 3 pagos en tus suscripciones'),
      ]);
      expect(avisosDePagosRegistrados(const []), isEmpty);
    });

    test('el flujo B de un procesador no dice "¿Tienes una suscripción a EBANX?"', () {
      expect(tituloAvisoCandidato(candidato(7, 'EBANX', 19900, procesador: 'EBANX')), 'Pago procesado por EBANX');
      expect(tituloAvisoCandidato(candidato(1, 'Crunchyroll', 19900)), '¿Tienes una suscripción a Crunchyroll?');
    });
  });

  test('procesar() devuelve los pagos registrados para avisar', () async {
    FlutterSecureStorage.setMockInitialValues({});
    const canal = MethodChannel('subtrack/deteccion');
    final mensajero = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    mensajero.setMockMethodCallHandler(canal, (call) async => switch (call.method) {
          'estado' => {'permiso': true, 'conectado': true, 'es_debug': true, 'modo_descubrimiento': false},
          'recuperarActivas' => 0,
          'leerCola' => [
              {
                'id': 'n1',
                'paquete': 'com.google.android.apps.messaging',
                'app': 'Mensajes',
                'titulo': '',
                'texto': r'Bancolombia: Compraste $44.900,00 en NETFLIX con tu T.Deb *0000, el 05/11/2026 a las 08:00.',
                'recibida_en': DateTime(2026, 11, 5, 8, 1).millisecondsSinceEpoch,
              },
            ],
          _ => null,
        });
    addTearDown(() => mensajero.setMockMethodCallHandler(canal, null));
    final catalogo = CatalogoServicios.fromJson(jsonDecode(File('backend/db/guias.json').readAsStringSync()) as Object);
    final servicio = FakeDeteccionService()
      ..registradosRespuesta = [const PagoRegistrado(servicio: 'Netflix', monto: 44900, moneda: 'COP')];
    final r = await ProcesadorDetecciones(
      lector: LectorNotificaciones(disponible: true),
      servicio: servicio,
      cargarCatalogo: () async => catalogo,
      almacen: AlmacenPagosLocales(),
      esperaConexion: Duration.zero,
    ).procesar();
    expect(r.registrados.single.servicio, 'Netflix');
  });
}
