import 'dart:io';

import 'package:flutter/services.dart';

/// Guarda archivos en la carpeta publica Descargas/Visuales usando MediaStore
/// (Android 10+), sin permisos especiales. En versiones anteriores se mantiene
/// el almacenamiento privado de la app.
class PublicStorage {
  static const MethodChannel _channel = MethodChannel(
    'cu.uclv.visuales_uclv/storage',
  );

  static bool supported = false;

  static Future<void> detect() async {
    if (!Platform.isAndroid) return;
    try {
      final sdk = await _channel.invokeMethod<int>('sdkInt');
      supported = (sdk ?? 0) >= 29;
    } catch (_) {
      supported = false;
    }
  }

  /// Copia un archivo ya descargado a Descargas/Visuales.
  /// Devuelve el content:// URI publico o null si no se pudo.
  static Future<String?> export({
    required String path,
    required String fileName,
    required String relativeDir,
    required String mime,
  }) async {
    if (!supported) return null;
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>('export', {
        'path': path,
        'name': fileName,
        'relativeDir': relativeDir,
        'mime': mime,
      });
      return result?['uri'] as String?;
    } catch (_) {
      return null;
    }
  }

  static Future<bool> openUri(String uri, {String? mime}) async {
    if (!Platform.isAndroid) return false;
    try {
      final opened = await _channel.invokeMethod<bool>('openUri', {
        'uri': uri,
        'mime': mime,
      });
      return opened ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> deleteUri(String uri) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<bool>('deleteUri', {'uri': uri});
    } catch (_) {
      // Ignorar.
    }
  }
}
