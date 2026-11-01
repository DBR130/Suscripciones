import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'parser_pagos.dart';

/// Huella de un cobro para que el backend no lo registre dos veces
/// (pagos_detectados.huella). Se calcula solo con los campos extraídos, nunca
/// con el texto de la notificación.
///
/// La fecha es la del mensaje o, si no la trae (Nequi), la hora en que
/// Android publicó la notificación (postTime). Así la misma notificación
/// leída en vivo y recuperada después desde la barra da la misma huella.
///
/// Si el mismo SMS sin fecha llega por otro camino (el historial de SMS trae
/// la hora de recepción, unos segundos distinta), la huella cambia: para eso
/// están [AnalizadorPagos.mismoCobro] en el celular y la tolerancia de 5
/// minutos del backend (fecha_del_mensaje = false).
String huellaDePago(PagoExtraido p) {
  final datos = [p.banco, p.comercio, p.monto.toStringAsFixed(2), p.moneda, fechaParaApi(p.fecha)].join('|');
  return sha256.convert(utf8.encode(datos)).toString();
}

/// Hora local sin zona, como la espera el backend: "2026-10-23T07:20:00.000".
String fechaParaApi(DateTime fecha) => (fecha.isUtc ? fecha.toLocal() : fecha).toIso8601String();

/// Lo que se envía a POST /api/detecciones/pagos: solo los campos extraídos.
Map<String, Object> pagoParaEnviar(PagoExtraido p) => {
      'huella': huellaDePago(p),
      'comercio': _recortar(p.comercioOriginal),
      'comercio_normalizado': _recortar(p.comercio),
      'monto': p.monto.toStringAsFixed(2),
      'moneda': p.moneda,
      'fecha': fechaParaApi(p.fecha),
      // false = el texto no traía fecha (Nequi) y es la hora de llegada: el
      // backend tolera unos minutos de diferencia al buscar repetidos.
      'fecha_del_mensaje': p.fechaDelMensaje,
      'banco': _recortar(p.banco, 50),
    };

/// Máximo que acepta el backend (VARCHAR(100) / VARCHAR(50)).
String _recortar(String texto, [int maximo = 100]) =>
    texto.length <= maximo ? texto : texto.substring(0, maximo);
