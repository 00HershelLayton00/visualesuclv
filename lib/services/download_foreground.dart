import 'dart:io';

import 'package:flutter/services.dart';

/// Mantiene el proceso vivo con un servicio en primer plano mientras
/// hay descargas activas, para que Android no las suspenda al salir de la app.
class DownloadForeground {
  static const MethodChannel _channel = MethodChannel(
    'cu.uclv.visuales_uclv/foreground',
  );

  static Future<void> sync({required bool active, required String text}) async {
    if (!Platform.isAndroid) return;
    try {
      if (active) {
        await _channel.invokeMethod<bool>('start', {'text': text});
      } else {
        await _channel.invokeMethod<bool>('stop');
      }
    } catch (_) {
      // Sin servicio en primer plano la descarga sigue funcionando mientras
      // la app este en uso.
    }
  }
}
