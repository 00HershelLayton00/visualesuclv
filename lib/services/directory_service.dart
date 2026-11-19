import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../core/api_client.dart';
import '../core/apache_parser.dart';
import '../core/json_store.dart';
import '../core/url_utils.dart';
import '../models/remote_entry.dart';

class _CachedListing {
  _CachedListing(this.entries, this.at);

  final List<RemoteEntry> entries;
  final DateTime at;
}

/// Obtiene listados de directorios con cache en memoria y en disco.
/// Permite mostrar una carpeta al instante y refrescarla en segundo plano.
class DirectoryService {
  DirectoryService(this._api);

  final ApiClient _api;
  final Map<String, _CachedListing> _memory = {};
  final Map<String, Future<List<RemoteEntry>>> _inflight = {};
  static const Duration _freshness = Duration(minutes: 5);
  static const Duration _diskMaxAge = Duration(days: 60);
  static const int _memoryLimit = 10;

  /// Lista una carpeta. Si [force] es false usa la copia en memoria reciente.
  Future<List<RemoteEntry>> list(String url, {bool force = false}) {
    final key = canonicalFolderUrl(url);
    final cached = _memory[key];
    if (!force &&
        cached != null &&
        DateTime.now().difference(cached.at) < _freshness) {
      return Future.value(cached.entries);
    }
    final pending = _inflight[key];
    if (pending != null) return pending;
    final future = _fetch(key);
    _inflight[key] = future;
    return future.whenComplete(() {
      _inflight.remove(key);
    });
  }

  Future<List<RemoteEntry>> _fetch(String key) async {
    final text = await _api.getText(key);
    final entries = parseApacheIndex(text, key);
    _storeMemory(key, entries);
    await _writeDisk(key, entries);
    return entries;
  }

  /// Devuelve la copia guardada (memoria o disco) sin tocar la red.
  Future<List<RemoteEntry>?> cachedAsync(String url) async {
    final key = canonicalFolderUrl(url);
    final memory = _memory[key];
    if (memory != null) return memory.entries;
    final entries = await _readDisk(key);
    if (entries == null) return null;
    _storeMemory(key, entries);
    return entries;
  }

  /// Ultimo listado conocido en memoria, si existe.
  List<RemoteEntry>? cached(String url) =>
      _memory[canonicalFolderUrl(url)]?.entries;

  Future<void> clearCache() async {
    _memory.clear();
    await JsonStore.deleteFolder('listings');
  }

  void _storeMemory(String key, List<RemoteEntry> entries) {
    _memory[key] = _CachedListing(entries, DateTime.now());
    if (_memory.length > _memoryLimit) {
      _memory.remove(_memory.keys.first);
    }
  }

  String _cacheName(String key) =>
      'listings/${sha1.convert(utf8.encode(key))}.json';

  Future<void> _writeDisk(String key, List<RemoteEntry> entries) async {
    await JsonStore.write(_cacheName(key), {
      'url': key,
      'saved_at': DateTime.now().toIso8601String(),
      'entries': [for (final entry in entries) entry.toJson()],
    });
  }

  Future<List<RemoteEntry>?> _readDisk(String key) async {
    final data = await JsonStore.read(_cacheName(key));
    if (data is! Map) return null;
    final savedAt = DateTime.tryParse(data['saved_at']?.toString() ?? '');
    if (savedAt != null && DateTime.now().difference(savedAt) > _diskMaxAge) {
      return null;
    }
    final raw = data['entries'];
    if (raw is! List) return null;
    final entries = <RemoteEntry>[];
    for (final item in raw) {
      final entry = RemoteEntry.fromJson(item);
      if (entry != null) entries.add(entry);
    }
    return entries;
  }
}
