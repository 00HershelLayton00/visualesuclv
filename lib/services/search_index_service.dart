import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html_parser;

import '../core/api_client.dart';
import '../core/formatters.dart';
import '../core/json_store.dart';
import '../core/url_utils.dart';
import '../models/search_entry.dart';

enum SearchIndexStatus { idle, loading, downloading, parsing, ready, error }

/// Indice global del sitio a partir de listado.html (arbol de 30 000+ carpetas).
class SearchIndexService extends ChangeNotifier {
  SearchIndexService(this._api);

  static const String indexUrl = 'https://visuales.uclv.cu/listado.html';
  static const String _indexFile = 'search_index.json';
  static const String _metaFile = 'search_index_meta.json';
  static const Duration _maxAge = Duration(days: 30);

  final ApiClient _api;
  final List<SearchEntry> _entries = [];
  SearchIndexStatus _status = SearchIndexStatus.idle;
  DateTime? _updatedAt;
  String? _error;
  bool _started = false;

  SearchIndexStatus get status => _status;
  DateTime? get updatedAt => _updatedAt;
  String? get error => _error;
  int get entryCount => _entries.length;
  bool get isBusy =>
      _status == SearchIndexStatus.downloading ||
      _status == SearchIndexStatus.parsing ||
      _status == SearchIndexStatus.loading;

  /// Carga el indice desde disco. No descarga nada automaticamente:
  /// asi la red no se satura al abrir la app.
  Future<void> ensureLoaded() async {
    if (_started) return;
    _started = true;
    _status = SearchIndexStatus.loading;
    notifyListeners();

    final raw = await JsonStore.read(_indexFile);
    final meta = await JsonStore.read(_metaFile);
    if (raw is List && raw.isNotEmpty) {
      for (final item in raw) {
        final entry = SearchEntry.fromJson(item);
        if (entry != null) _entries.add(entry);
      }
      if (meta is Map) {
        _updatedAt = DateTime.tryParse(meta['updated_at']?.toString() ?? '');
      }
      _status = SearchIndexStatus.ready;
      notifyListeners();
      final age = _updatedAt == null
          ? const Duration(days: 365)
          : DateTime.now().difference(_updatedAt!);
      if (age > _maxAge) {
        unawaited(refresh(silent: true));
      }
      return;
    }
    _status = SearchIndexStatus.idle;
    notifyListeners();
  }

  /// Descarga y parsea de nuevo el indice global.
  Future<bool> refresh({bool silent = false}) async {
    if (_status == SearchIndexStatus.downloading ||
        _status == SearchIndexStatus.parsing) {
      return false;
    }
    _status = SearchIndexStatus.downloading;
    _error = null;
    if (!silent) notifyListeners();

    try {
      final text = await _api.getText(
        indexUrl,
        timeout: const Duration(seconds: 90),
      );
      _status = SearchIndexStatus.parsing;
      if (!silent) notifyListeners();
      final parsed = await compute(parseListadoTree, text);
      final fresh = <SearchEntry>[
        for (final row in parsed)
          SearchEntry(name: row[0], url: row[1], path: row[2]),
      ];
      if (fresh.isNotEmpty) {
        _entries
          ..clear()
          ..addAll(fresh);
        _updatedAt = DateTime.now();
        await JsonStore.write(_indexFile, [
          for (final entry in _entries) entry.toJson(),
        ]);
        await JsonStore.write(_metaFile, {
          'updated_at': _updatedAt!.toIso8601String(),
        });
      }
      _status = SearchIndexStatus.ready;
      if (!silent) notifyListeners();
      return true;
    } catch (error) {
      _error = error is ApiException
          ? error.message
          : 'No se pudo actualizar el indice del sitio.';
      _status = _entries.isEmpty
          ? SearchIndexStatus.error
          : SearchIndexStatus.ready;
      notifyListeners();
      return false;
    }
  }

  /// Borra el indice guardado y vuelve a descargarlo.
  Future<void> clearAndRefresh() async {
    _entries.clear();
    _updatedAt = null;
    _status = SearchIndexStatus.idle;
    _error = null;
    await JsonStore.delete(_indexFile);
    await JsonStore.delete(_metaFile);
    notifyListeners();
    await refresh();
  }

  /// Busca carpetas por nombre y ruta, sin distinguir acentos ni mayusculas.
  List<SearchEntry> search(String query, {int limit = 400}) {
    final normalized = foldQuery(query);
    if (normalized.isEmpty) return const [];
    final terms = normalized
        .split(' ')
        .where((term) => term.isNotEmpty)
        .toList();
    final scored = <_ScoredEntry>[];
    for (final entry in _entries) {
      final foldedName = foldText(entry.name);
      String? foldedPath;
      var score = 0;
      var matchesAll = true;
      for (final term in terms) {
        if (foldedName == term) {
          score += 120;
        } else if (foldedName.startsWith(term)) {
          score += 70;
        } else if (_wordStartsWith(foldedName, term)) {
          score += 55;
        } else if (foldedName.contains(term)) {
          score += 40;
        } else {
          foldedPath ??= foldText(entry.path);
          if (foldedPath.contains(term)) {
            score += 12;
          } else {
            matchesAll = false;
            break;
          }
        }
      }
      if (matchesAll) scored.add(_ScoredEntry(entry, score));
    }
    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return a.entry.path.length.compareTo(b.entry.path.length);
    });
    return [for (final item in scored.take(limit)) item.entry];
  }

  static bool _wordStartsWith(String text, String term) {
    final index = text.indexOf(term);
    if (index == 0) return true;
    if (index < 0) return false;
    final previous = text.codeUnitAt(index - 1);
    return previous == 0x20 ||
        previous == 0x2e ||
        previous == 0x2d ||
        previous == 0x5f ||
        previous == 0x28;
  }

  static String foldQuery(String query) {
    return foldText(query).replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}

class _ScoredEntry {
  _ScoredEntry(this.entry, this.score);

  final SearchEntry entry;
  final int score;
}

/// Parseo del arbol HTML generado por `tree`.
List<List<String>> parseListadoTree(String htmlText) {
  final document = html_parser.parse(htmlText);
  final result = <List<String>>[];
  final seen = <String>{};
  for (final anchor in document.querySelectorAll('a')) {
    final href = anchor.attributes['href'];
    if (href == null || !href.contains(ApiClient.host)) continue;
    final segments = _segmentsFromUrl(href);
    if (segments == null || segments.isEmpty) continue;
    final canonical = _canonicalUrl(
      segments,
      trailingSlash: href.endsWith('/'),
    );
    if (!seen.add(canonical)) continue;
    final text = anchor.text.trim();
    final name = text.isEmpty ? segments.last : text;
    result.add([name, canonical, segments.join(' / ')]);
  }
  return result;
}

/// Decodifica los segmentos de una URL aunque tenga codificacion invalida.
List<String>? _segmentsFromUrl(String url) {
  var value = collapseSlashes(url);
  if (value.startsWith('http://')) {
    value = 'https://${value.substring('http://'.length)}';
  }
  if (!value.startsWith('https://${ApiClient.host}/')) return null;
  try {
    final uri = Uri.parse(value);
    final segments = uri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList();
    if (segments.isNotEmpty) return segments;
  } on FormatException {
    // Continua con el respaldo manual.
  }
  final withoutHost = value.replaceFirst(RegExp(r'^https?://[^/]+'), '');
  final decoded = <String>[];
  for (final part in withoutHost.split('/')) {
    if (part.isEmpty) continue;
    try {
      decoded.add(Uri.decodeComponent(part));
    } catch (_) {
      decoded.add(part);
    }
  }
  return decoded.isEmpty ? null : decoded;
}

String _canonicalUrl(List<String> segments, {required bool trailingSlash}) {
  return Uri(
    scheme: 'https',
    host: ApiClient.host,
    pathSegments: trailingSlash ? [...segments, ''] : segments,
  ).toString();
}
