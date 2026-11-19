import '../core/media_types.dart';

/// Elemento remoto (carpeta o archivo) dentro del servidor.
class RemoteEntry {
  const RemoteEntry({
    required this.name,
    required this.url,
    required this.isDirectory,
    this.modified,
    this.size,
  });

  final String name;
  final String url;
  final bool isDirectory;
  final DateTime? modified;
  final int? size;

  MediaKind get kind => kindForName(name, isDirectory: isDirectory);

  String get extension {
    final dot = name.lastIndexOf('.');
    return dot >= 0 ? name.substring(dot + 1).toLowerCase() : '';
  }

  /// Huella estable para detectar cambios en una carpeta.
  String get fingerprint =>
      '$name|${isDirectory ? 'd' : 'f'}|${size ?? -1}|'
      '${modified?.millisecondsSinceEpoch ?? 0}';

  Map<String, dynamic> toJson() => {
    'name': name,
    'url': url,
    'dir': isDirectory,
    'modified': modified?.millisecondsSinceEpoch,
    'size': size,
  };

  static RemoteEntry? fromJson(dynamic data) {
    if (data is! Map) return null;
    final name = data['name']?.toString();
    final url = data['url']?.toString();
    if (name == null || url == null) return null;
    final modifiedMs = data['modified'];
    return RemoteEntry(
      name: name,
      url: url,
      isDirectory: data['dir'] == true,
      modified: modifiedMs is num
          ? DateTime.fromMillisecondsSinceEpoch(modifiedMs.toInt())
          : null,
      size: (data['size'] as num?)?.toInt(),
    );
  }
}
