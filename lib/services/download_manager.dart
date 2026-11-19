import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../core/api_client.dart';
import '../core/formatters.dart';
import '../core/json_store.dart';
import '../core/media_types.dart';
import '../core/url_utils.dart';
import '../models/download_task.dart';
import '../models/remote_entry.dart';
import 'download_foreground.dart';
import 'notification_service.dart';
import 'public_storage.dart';

/// Excepcion interna para reintentar una descarga desde cero.
class _RetryDownloadException implements Exception {
  const _RetryDownloadException(this.reason);

  final String reason;
}

/// Cola de descargas con pausa, reanudacion (Range), reintentos automaticos
/// y persistencia. Descarga de una en una para no saturar conexiones lentas.
class DownloadManager extends ChangeNotifier {
  DownloadManager(this._api, this._notifications);

  static const String _fileName = 'downloads.json';
  static const int _maxConcurrent = 1;
  static const int _maxAttempts = 4;

  final ApiClient _api;
  final NotificationService _notifications;
  final List<DownloadTask> _tasks = [];
  final Set<String> _runningIds = {};
  Directory? _root;
  DateTime _lastNotify = DateTime.fromMillisecondsSinceEpoch(0);
  bool _foregroundActive = false;
  int _foregroundCount = 0;

  List<DownloadTask> get tasks => List.unmodifiable(_tasks);

  List<DownloadTask> get active => [
    for (final task in _tasks)
      if (task.isActive) task,
  ];

  List<DownloadTask> get finished => [
    for (final task in _tasks)
      if (!task.isActive) task,
  ];

  int get activeCount => active.length;

  DownloadTask? taskForUrl(String url) {
    for (final task in _tasks) {
      if (task.url == url) return task;
    }
    return null;
  }

  Future<void> load() async {
    _tasks.clear();
    final data = await JsonStore.read(_fileName);
    if (data is List) {
      for (final item in data) {
        final task = DownloadTask.fromJson(item);
        if (task == null) continue;
        if (task.status == DownloadStatus.downloading ||
            task.status == DownloadStatus.queued) {
          final part = File('${task.localPath}.part');
          task.received = await part.exists() ? await part.length() : 0;
          task.status = DownloadStatus.paused;
        }
        if (task.status == DownloadStatus.completed && task.publicUri == null) {
          final file = File(task.localPath);
          if (!await file.exists()) continue;
        }
        _tasks.add(task);
      }
    }
    notifyListeners();
  }

  String get storageLabel => PublicStorage.supported
      ? 'Descargas/Visuales'
      : 'almacenamiento de la app';

  Future<Directory> _ensureRoot() async {
    if (_root != null) return _root!;
    Directory base;
    if (Platform.isAndroid) {
      base =
          await getExternalStorageDirectory() ??
          await getApplicationDocumentsDirectory();
    } else {
      base = await getApplicationDocumentsDirectory();
    }
    final dir = Directory('${base.path}/VisualesUCLV');
    if (!await dir.exists()) await dir.create(recursive: true);
    _root = dir;
    return dir;
  }

  Future<DownloadTask> start(RemoteEntry entry) async {
    final existing = taskForUrl(entry.url);
    if (existing != null) {
      if (existing.status == DownloadStatus.completed || existing.isActive) {
        return existing;
      }
      existing.status = DownloadStatus.queued;
      existing.error = null;
      existing.cancelToken = null;
      _scheduleSave();
      _notify(force: true);
      _pump();
      return existing;
    }
    final root = await _ensureRoot();
    final relativePath = localRelativePathOf(entry.url);
    final task = DownloadTask(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      url: entry.url,
      fileName: entry.name,
      relativePath: relativePath,
      localPath: '${root.path}/$relativePath',
      total: entry.size ?? 0,
    );
    _tasks.insert(0, task);
    _scheduleSave();
    _notify(force: true);
    _pump();
    return task;
  }

  void pause(DownloadTask task) {
    if (task.status != DownloadStatus.downloading &&
        task.status != DownloadStatus.queued) {
      return;
    }
    task.status = DownloadStatus.paused;
    task.speed = 0;
    task.cancelToken?.cancel('pause');
    _scheduleSave();
    _notify(force: true);
    _pump();
  }

  void resume(DownloadTask task) {
    if (task.status == DownloadStatus.downloading ||
        task.status == DownloadStatus.completed) {
      return;
    }
    task.status = DownloadStatus.queued;
    task.error = null;
    _scheduleSave();
    _notify(force: true);
    _pump();
  }

  Future<void> remove(DownloadTask task, {bool deleteFile = true}) async {
    if (task.status == DownloadStatus.downloading ||
        task.status == DownloadStatus.queued) {
      task.status = DownloadStatus.canceled;
      task.cancelToken?.cancel('cancel');
    }
    _tasks.remove(task);
    if (deleteFile) {
      try {
        final file = File(task.localPath);
        if (await file.exists()) await file.delete();
        final part = File('${task.localPath}.part');
        if (await part.exists()) await part.delete();
      } catch (_) {
        // Ignorar.
      }
      if (task.publicUri != null) {
        await PublicStorage.deleteUri(task.publicUri!);
      }
    }
    _scheduleSave();
    _notify(force: true);
    _pump();
  }

  Future<void> clearFinished() async {
    final removed = [
      for (final task in _tasks)
        if (!task.isActive) task,
    ];
    for (final task in removed) {
      _tasks.remove(task);
      try {
        final file = File(task.localPath);
        if (await file.exists()) await file.delete();
        final part = File('${task.localPath}.part');
        if (await part.exists()) await part.delete();
      } catch (_) {
        // Ignorar.
      }
      if (task.publicUri != null) {
        await PublicStorage.deleteUri(task.publicUri!);
      }
    }
    _scheduleSave();
    _notify(force: true);
  }

  Future<bool> open(DownloadTask task) async {
    if (task.publicUri != null) {
      if (await PublicStorage.openUri(
        task.publicUri!,
        mime: mimeForName(task.fileName),
      )) {
        return true;
      }
    }
    try {
      final result = await OpenFilex.open(task.localPath);
      return result.type == ResultType.done;
    } catch (_) {
      return false;
    }
  }

  /// Inicia las descargas en cola hasta el limite de concurrencia.
  void _pump() {
    var running = _tasks
        .where((task) => task.status == DownloadStatus.downloading)
        .length;
    if (running >= _maxConcurrent) {
      _syncForeground();
      return;
    }
    for (final task in _tasks.reversed) {
      if (running >= _maxConcurrent) break;
      if (task.status == DownloadStatus.queued &&
          !_runningIds.contains(task.id)) {
        running++;
        unawaited(_run(task));
      }
    }
    _syncForeground();
  }

  Future<void> _run(DownloadTask task) async {
    if (_runningIds.contains(task.id)) return;
    _runningIds.add(task.id);
    task.status = DownloadStatus.downloading;
    task.error = null;
    task.cancelToken = CancelToken();
    _notify(force: true);

    try {
      for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
        if (task.status != DownloadStatus.downloading) break;
        try {
          final done = await _downloadOnce(task);
          if (done) break;
        } catch (error) {
          if (task.status != DownloadStatus.downloading) break;
          if (!_isRetryable(error) || attempt >= _maxAttempts) {
            task.status = DownloadStatus.failed;
            task.speed = 0;
            task.error = _friendlyError(error);
            break;
          }
          task.speed = 0;
          task.error =
              'Conexion interrumpida. Reintentando ($attempt/$_maxAttempts)...';
          _notify(force: true);
          await Future<void>.delayed(Duration(seconds: 2 * attempt));
          if (task.status != DownloadStatus.downloading) break;
        }
      }
    } finally {
      task.cancelToken = null;
      if (task.status == DownloadStatus.canceled) {
        _tasks.remove(task);
        try {
          final part = File('${task.localPath}.part');
          if (await part.exists()) await part.delete();
        } catch (_) {
          // Ignorar.
        }
      }
      _scheduleSave();
      _notify(force: true);
      _runningIds.remove(task.id);
      _syncForeground();
      _pump();
    }
  }

  /// Un intento de descarga. Devuelve true si el archivo quedo completo.
  Future<bool> _downloadOnce(DownloadTask task) async {
    final part = File('${task.localPath}.part');
    final target = File(task.localPath);
    await Directory(target.parent.path).create(recursive: true);

    var start = await part.exists() ? await part.length() : 0;
    if (task.total > 0 && start >= task.total) {
      await _finalize(task, part);
      return true;
    }

    final headers = <String, String>{};
    if (start > 0) headers['Range'] = 'bytes=$start-';

    final response = await _api.createDio().get<ResponseBody>(
      task.url,
      options: Options(
        responseType: ResponseType.stream,
        headers: headers,
        receiveTimeout: const Duration(minutes: 5),
        validateStatus: (status) =>
            status != null && (status == 200 || status == 206 || status == 416),
      ),
      cancelToken: task.cancelToken,
    );

    final statusCode = response.statusCode ?? 200;
    if (statusCode == 416) {
      if (task.total > 0 && start >= task.total) {
        await _finalize(task, part);
        return true;
      }
      try {
        if (await part.exists()) await part.delete();
      } catch (_) {
        // Ignorar.
      }
      throw const _RetryDownloadException('rango no valido');
    }

    if (statusCode != 206) start = 0;
    final raf = await part.open(
      mode: start > 0 ? FileMode.append : FileMode.write,
    );
    task.received = start;

    try {
      final contentLength =
          int.tryParse(response.headers.value('content-length') ?? '') ?? 0;
      final contentRange = response.headers.value('content-range');
      if (contentRange != null) {
        final match = RegExp(r'/(\d+)$').firstMatch(contentRange);
        final parsedTotal = int.tryParse(match?.group(1) ?? '');
        task.total = parsedTotal ?? (start + contentLength);
      } else if (contentLength > 0) {
        task.total = start + contentLength;
      }

      task.lastTickAt = DateTime.now();
      task.lastTickBytes = task.received;

      await for (final chunk in response.data!.stream) {
        if (task.status != DownloadStatus.downloading) break;
        await raf.writeFrom(chunk);
        task.received += chunk.length;
        _updateSpeed(task);
        _notify();
      }
    } finally {
      await raf.close();
    }

    if (task.status != DownloadStatus.downloading) return false;
    await _finalize(task, part);
    return true;
  }

  Future<void> _finalize(DownloadTask task, File part) async {
    final target = File(task.localPath);
    if (await target.exists()) await target.delete();
    if (await part.exists()) await part.rename(task.localPath);
    task.status = DownloadStatus.completed;
    task.received = await target.length();
    task.total = task.received;
    task.speed = 0;
    task.error = null;

    if (PublicStorage.supported) {
      final slash = task.relativePath.lastIndexOf('/');
      final relativeDir = slash > 0
          ? task.relativePath.substring(0, slash)
          : '';
      final uri = await PublicStorage.export(
        path: task.localPath,
        fileName: task.fileName,
        relativeDir: relativeDir,
        mime: mimeForName(task.fileName),
      );
      if (uri != null) {
        task.publicUri = uri;
        try {
          await target.delete();
        } catch (_) {
          // Se conserva la copia privada si no se pudo borrar.
        }
      }
    }

    await _notifications.showDownloadFinished(
      fileName: task.fileName,
      target: task.publicUri != null
          ? 'uri:${task.publicUri}'
          : 'file:${task.localPath}',
      details: formatBytes(task.received),
    );
  }

  void _updateSpeed(DownloadTask task) {
    final now = DateTime.now();
    final elapsed = now.difference(task.lastTickAt).inMilliseconds;
    if (elapsed >= 500) {
      final delta = task.received - task.lastTickBytes;
      task.speed = elapsed > 0 ? delta * 1000 / elapsed : 0;
      task.lastTickAt = now;
      task.lastTickBytes = task.received;
    }
  }

  void _notify({bool force = false}) {
    _syncForeground();
    final now = DateTime.now();
    if (!force && now.difference(_lastNotify).inMilliseconds < 400) return;
    _lastNotify = now;
    notifyListeners();
  }

  void _syncForeground() {
    final running = <DownloadTask>[
      for (final task in _tasks)
        if (task.status == DownloadStatus.downloading ||
            task.status == DownloadStatus.queued)
          task,
    ];
    final active = running.isNotEmpty;
    final count = running.length;
    if (active == _foregroundActive && count == _foregroundCount) return;
    _foregroundActive = active;
    _foregroundCount = count;
    final text = switch (count) {
      0 => '',
      1 => 'Descargando ${running.first.fileName}',
      _ => 'Descargando $count archivos...',
    };
    DownloadForeground.sync(active: active, text: text);
  }

  void _scheduleSave() => _persist();

  void _persist() {
    unawaited(
      JsonStore.write(_fileName, [for (final task in _tasks) task.toJson()]),
    );
  }

  static bool _isRetryable(Object error) {
    if (error is _RetryDownloadException) return true;
    if (error is FileSystemException) return false;
    if (error is DioException) {
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.transformTimeout:
        case DioExceptionType.connectionError:
        case DioExceptionType.unknown:
          return true;
        case DioExceptionType.badResponse:
          final code = error.response?.statusCode;
          return code == null || code == 408 || code == 429 || code >= 500;
        case DioExceptionType.badCertificate:
        case DioExceptionType.cancel:
          return false;
      }
    }
    return false;
  }

  static String _friendlyError(Object error) {
    if (error is FileSystemException) {
      final code = error.osError?.errorCode;
      if (code == 28) {
        return 'No hay espacio suficiente en el almacenamiento.';
      }
      if (code == 13) {
        return 'Sin permiso para guardar en el almacenamiento.';
      }
      return 'No se pudo guardar el archivo (${error.message}).';
    }
    if (error is ApiException) return error.message;
    if (error is DioException) {
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
          return 'El servidor tardo demasiado en aceptar la conexion.';
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.transformTimeout:
          return 'Se perdio la conexion durante la descarga.';
        case DioExceptionType.connectionError:
          return 'Sin conexion con el servidor. Comprueba tu red.';
        case DioExceptionType.badCertificate:
          return 'Certificado del servidor no valido.';
        case DioExceptionType.cancel:
          return 'Descarga cancelada.';
        case DioExceptionType.badResponse:
          final code = error.response?.statusCode;
          if (code == 403) {
            return 'El servidor rechazo la descarga (403).';
          }
          if (code == 404) {
            return 'El archivo ya no existe en el servidor (404).';
          }
          if (code != null && code >= 500) {
            return 'El servidor no esta disponible ahora ($code).';
          }
          return 'El servidor respondio con error ($code).';
        case DioExceptionType.unknown:
          return 'La conexion se interrumpio. Puedes reanudar la descarga.';
      }
    }
    return 'No se pudo descargar. Puedes reanudar la descarga.';
  }

  @override
  void dispose() {
    DownloadForeground.sync(active: false, text: '');
    super.dispose();
  }
}
