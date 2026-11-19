import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Almacen JSON en el directorio de soporte de la app.
class JsonStore {
  static Future<File> _file(String name) async {
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}/$name');
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }
    return file;
  }

  static Future<dynamic> read(String name) async {
    try {
      final file = await _file(name);
      if (!await file.exists()) return null;
      final text = await file.readAsString();
      if (text.trim().isEmpty) return null;
      return jsonDecode(text);
    } catch (_) {
      return null;
    }
  }

  static Future<void> write(String name, dynamic data) async {
    try {
      final file = await _file(name);
      await file.writeAsString(jsonEncode(data), flush: true);
    } catch (_) {
      // Ignorar fallos de escritura.
    }
  }

  static Future<void> delete(String name) async {
    try {
      final file = await _file(name);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Ignorar.
    }
  }

  static Future<void> deleteFolder(String name) async {
    try {
      final dir = await getApplicationSupportDirectory();
      final folder = Directory('${dir.path}/$name');
      if (await folder.exists()) await folder.delete(recursive: true);
    } catch (_) {
      // Ignorar.
    }
  }
}
