import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../core/json_store.dart';
import '../core/url_utils.dart';
import '../models/change_event.dart';
import '../models/favorite_folder.dart';
import 'directory_service.dart';
import 'notification_service.dart';

class CheckSummary {
  const CheckSummary({
    this.checked = 0,
    this.changed = 0,
    this.missing = 0,
    this.failed = 0,
  });

  final int checked;
  final int changed;
  final int missing;
  final int failed;

  String get message {
    if (checked == 0) return 'No hay carpetas favoritas que revisar.';
    final parts = <String>['$checked revisada${checked == 1 ? '' : 's'}'];
    if (changed > 0) {
      parts.add('$changed con cambios');
    }
    if (missing > 0) {
      parts.add('$missing desaparecida${missing == 1 ? '' : 's'}');
    }
    if (failed > 0) {
      parts.add('$failed sin conexion');
    }
    return parts.join(' · ');
  }
}

/// Gestiona carpetas favoritas, su historial de cambios y avisos.
class FavoritesService extends ChangeNotifier {
  FavoritesService(this._directories, this._notifications);

  static const String _fileName = 'favorites.json';
  static const int _maxEvents = 100;

  final DirectoryService _directories;
  final NotificationService _notifications;
  final List<FavoriteFolder> _favorites = [];
  final List<ChangeEvent> _events = [];
  bool _loaded = false;
  bool _checking = false;
  DateTime? _lastCheckAt;

  List<FavoriteFolder> get favorites => List.unmodifiable(_favorites);
  List<ChangeEvent> get events => List.unmodifiable(_events);
  bool get isChecking => _checking;
  DateTime? get lastCheckAt => _lastCheckAt;
  int get count => _favorites.length;
  int get unreadCount => _events.where((event) => !event.read).length;

  bool isFavorite(String url) =>
      _favorites.any((favorite) => isSameFolder(favorite.url, url));

  FavoriteFolder? favoriteFor(String url) {
    for (final favorite in _favorites) {
      if (isSameFolder(favorite.url, url)) return favorite;
    }
    return null;
  }

  bool hasUnreadEventFor(String url) {
    for (final event in _events) {
      if (!event.read && isSameFolder(event.folderUrl, url)) return true;
    }
    return false;
  }

  Future<void> load() async {
    if (_loaded) return;
    final data = await JsonStore.read(_fileName);
    if (data is Map) {
      for (final item in (data['favorites'] as List? ?? const [])) {
        final favorite = FavoriteFolder.fromJson(item);
        if (favorite != null) _favorites.add(favorite);
      }
      for (final item in (data['events'] as List? ?? const [])) {
        final event = ChangeEvent.fromJson(item);
        if (event != null) _events.add(event);
      }
      _lastCheckAt = DateTime.tryParse(data['last_check_at']?.toString() ?? '');
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> reload() async {
    _loaded = false;
    _favorites.clear();
    _events.clear();
    await load();
  }

  Future<void> save() async {
    await JsonStore.write(_fileName, {
      'favorites': [for (final favorite in _favorites) favorite.toJson()],
      'events': [for (final event in _events) event.toJson()],
      'last_check_at': _lastCheckAt?.toIso8601String(),
    });
  }

  /// Agrega o quita una carpeta. Devuelve true si quedo como favorita.
  Future<bool> toggle(String url, String name) async {
    final existing = favoriteFor(url);
    if (existing != null) {
      _favorites.remove(existing);
      await save();
      notifyListeners();
      return false;
    }
    final favorite = FavoriteFolder(
      url: canonicalFolderUrl(url),
      name: name,
      path: displayPathOf(url),
    );
    _favorites.add(favorite);
    await save();
    notifyListeners();
    unawaited(_snapshotInitial(favorite));
    return true;
  }

  Future<void> remove(String url) async {
    _favorites.removeWhere((favorite) => isSameFolder(favorite.url, url));
    await save();
    notifyListeners();
  }

  Future<void> _snapshotInitial(FavoriteFolder favorite) async {
    try {
      final entries = await _directories.list(favorite.url, force: true);
      favorite.snapshot = [for (final entry in entries) entry.fingerprint];
      favorite.initialized = true;
      favorite.lastChecked = DateTime.now();
      favorite.missing = false;
      favorite.lastError = null;
      await save();
      notifyListeners();
    } catch (_) {
      // Se completara en la proxima revision.
    }
  }

  /// Revisa todas las carpetas favoritas buscando cambios o desapariciones.
  Future<CheckSummary> checkAll({
    bool notify = true,
    void Function(int done, int total)? onProgress,
  }) async {
    if (_checking || _favorites.isEmpty) {
      return const CheckSummary();
    }
    _checking = true;
    notifyListeners();
    var changed = 0;
    var missing = 0;
    var failed = 0;
    final snapshot = List<FavoriteFolder>.of(_favorites);
    for (var index = 0; index < snapshot.length; index++) {
      final result = await _checkOne(snapshot[index], notify: notify);
      switch (result) {
        case _CheckResult.changed:
          changed++;
        case _CheckResult.missing:
          missing++;
        case _CheckResult.failed:
          failed++;
        case _CheckResult.same:
        case _CheckResult.initialized:
          break;
      }
      onProgress?.call(index + 1, snapshot.length);
    }
    _lastCheckAt = DateTime.now();
    await save();
    _checking = false;
    notifyListeners();
    return CheckSummary(
      checked: snapshot.length,
      changed: changed,
      missing: missing,
      failed: failed,
    );
  }

  /// Revisa una sola carpeta favorita.
  Future<CheckSummary> checkOne(String url, {bool notify = true}) async {
    final favorite = favoriteFor(url);
    if (favorite == null || _checking) return const CheckSummary();
    _checking = true;
    notifyListeners();
    final result = await _checkOne(favorite, notify: notify);
    _lastCheckAt = DateTime.now();
    await save();
    _checking = false;
    notifyListeners();
    return CheckSummary(
      checked: 1,
      changed: result == _CheckResult.changed ? 1 : 0,
      missing: result == _CheckResult.missing ? 1 : 0,
      failed: result == _CheckResult.failed ? 1 : 0,
    );
  }

  Future<_CheckResult> _checkOne(
    FavoriteFolder favorite, {
    required bool notify,
  }) async {
    try {
      final entries = await _directories.list(favorite.url, force: true);
      final current = <String>{for (final entry in entries) entry.fingerprint};
      final wasMissing = favorite.missing;
      favorite.lastChecked = DateTime.now();
      favorite.missing = false;
      favorite.lastError = null;

      if (!favorite.initialized) {
        favorite.snapshot = current.toList();
        favorite.initialized = true;
        await save();
        return _CheckResult.initialized;
      }

      if (wasMissing) {
        favorite.snapshot = current.toList();
        final event = ChangeEvent(
          folderUrl: favorite.url,
          folderName: favorite.name,
          type: ChangeEventType.restored,
          at: DateTime.now(),
        );
        await _pushEvent(event, notify: notify);
        return _CheckResult.changed;
      }

      final previous = favorite.snapshot.toSet();
      final added = current.difference(previous);
      final removed = previous.difference(current);
      if (added.isEmpty && removed.isEmpty) {
        await save();
        return _CheckResult.same;
      }

      favorite.snapshot = current.toList();
      final event = ChangeEvent(
        folderUrl: favorite.url,
        folderName: favorite.name,
        type: ChangeEventType.updated,
        added: _namesOf(added),
        removed: _namesOf(removed),
        totalAdded: added.length,
        totalRemoved: removed.length,
        at: DateTime.now(),
      );
      await _pushEvent(event, notify: notify);
      return _CheckResult.changed;
    } on ApiException catch (error) {
      favorite.lastChecked = DateTime.now();
      if (error.isNotFound) {
        final wasMissing = favorite.missing;
        favorite.missing = true;
        favorite.lastError = null;
        if (!wasMissing) {
          final event = ChangeEvent(
            folderUrl: favorite.url,
            folderName: favorite.name,
            type: ChangeEventType.disappeared,
            at: DateTime.now(),
          );
          await _pushEvent(event, notify: notify);
        } else {
          await save();
        }
        return _CheckResult.missing;
      }
      favorite.lastError = error.message;
      await save();
      return _CheckResult.failed;
    }
  }

  List<String> _namesOf(Set<String> fingerprints) {
    final names = [
      for (final fingerprint in fingerprints) fingerprint.split('|').first,
    ]..sort();
    return names.take(20).toList();
  }

  Future<void> _pushEvent(ChangeEvent event, {required bool notify}) async {
    _events.insert(0, event);
    if (_events.length > _maxEvents) {
      _events.removeRange(_maxEvents, _events.length);
    }
    await save();
    if (notify) {
      await _notifications.showChange(
        folderName: event.folderName,
        folderUrl: event.folderUrl,
        body: describeEvent(event),
      );
    }
    notifyListeners();
  }

  void markEventsRead() {
    for (final event in _events) {
      event.read = true;
    }
    save();
    notifyListeners();
  }

  void markEventRead(ChangeEvent event) {
    if (event.read) return;
    event.read = true;
    save();
    notifyListeners();
  }

  Future<void> clearEvents() async {
    _events.clear();
    await save();
    notifyListeners();
  }

  static String describeEvent(ChangeEvent event) {
    switch (event.type) {
      case ChangeEventType.updated:
        final parts = <String>[];
        if (event.totalAdded > 0) {
          parts.add(
            '${event.totalAdded} nuevo${event.totalAdded == 1 ? '' : 's'}',
          );
        }
        if (event.totalRemoved > 0) {
          parts.add(
            '${event.totalRemoved} eliminado${event.totalRemoved == 1 ? '' : 's'}',
          );
        }
        return parts.join(' · ');
      case ChangeEventType.disappeared:
        return 'La carpeta ya no esta disponible en el servidor';
      case ChangeEventType.restored:
        return 'La carpeta vuelve a estar disponible';
    }
  }
}

enum _CheckResult { initialized, same, changed, missing, failed }
