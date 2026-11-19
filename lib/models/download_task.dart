import 'package:dio/dio.dart';

enum DownloadStatus { queued, downloading, paused, completed, failed, canceled }

/// Descarga de un archivo del sitio.
class DownloadTask {
  DownloadTask({
    required this.id,
    required this.url,
    required this.fileName,
    required this.relativePath,
    required this.localPath,
    this.received = 0,
    this.total = 0,
    this.status = DownloadStatus.queued,
    this.error,
    this.publicUri,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String id;
  final String url;
  final String fileName;
  final String relativePath;
  final String localPath;
  int received;
  int total;
  DownloadStatus status;
  String? error;

  /// URI publico en Descargas/Visuales (Android 10+) cuando se exporto.
  String? publicUri;
  final DateTime createdAt;

  double speed = 0;
  DateTime lastTickAt = DateTime.now();
  int lastTickBytes = 0;
  CancelToken? cancelToken;

  bool get isActive =>
      status == DownloadStatus.queued ||
      status == DownloadStatus.downloading ||
      status == DownloadStatus.paused;

  bool get isFinished => status == DownloadStatus.completed;

  double get progress {
    if (status == DownloadStatus.completed) return 1;
    if (total <= 0) return 0;
    return (received / total).clamp(0.0, 1.0);
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'url': url,
    'file_name': fileName,
    'relative_path': relativePath,
    'local_path': localPath,
    'received': received,
    'total': total,
    'status': status.name,
    'error': error,
    'public_uri': publicUri,
    'created_at': createdAt.toIso8601String(),
  };

  static DownloadTask? fromJson(dynamic data) {
    if (data is! Map) return null;
    final url = data['url']?.toString();
    final localPath = data['local_path']?.toString();
    if (url == null || localPath == null) return null;
    final statusName = data['status']?.toString() ?? 'queued';
    final status = DownloadStatus.values.firstWhere(
      (value) => value.name == statusName,
      orElse: () => DownloadStatus.queued,
    );
    return DownloadTask(
      id:
          data['id']?.toString() ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      url: url,
      fileName: data['file_name']?.toString() ?? 'archivo',
      relativePath: data['relative_path']?.toString() ?? '',
      localPath: localPath,
      received: (data['received'] as num?)?.toInt() ?? 0,
      total: (data['total'] as num?)?.toInt() ?? 0,
      status: status,
      error: data['error']?.toString(),
      publicUri: data['public_uri']?.toString(),
      createdAt: DateTime.tryParse(data['created_at']?.toString() ?? ''),
    );
  }
}
