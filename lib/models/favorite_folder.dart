/// Carpeta guardada en favoritos con la huella de su ultimo listado.
class FavoriteFolder {
  FavoriteFolder({
    required this.url,
    required this.name,
    required this.path,
    List<String>? snapshot,
    this.initialized = false,
    this.lastChecked,
    this.missing = false,
    this.lastError,
  }) : snapshot = snapshot ?? <String>[];

  final String url;
  String name;
  final String path;
  List<String> snapshot;
  bool initialized;
  DateTime? lastChecked;
  bool missing;
  String? lastError;

  Map<String, dynamic> toJson() => {
    'url': url,
    'name': name,
    'path': path,
    'snapshot': snapshot,
    'initialized': initialized,
    'last_checked': lastChecked?.toIso8601String(),
    'missing': missing,
    'last_error': lastError,
  };

  static FavoriteFolder? fromJson(dynamic data) {
    if (data is! Map) return null;
    final url = data['url']?.toString();
    if (url == null || url.isEmpty) return null;
    return FavoriteFolder(
      url: url,
      name: data['name']?.toString() ?? url,
      path: data['path']?.toString() ?? '',
      snapshot: (data['snapshot'] as List? ?? const [])
          .map((item) => item.toString())
          .toList(),
      initialized: data['initialized'] == true,
      lastChecked: DateTime.tryParse(data['last_checked']?.toString() ?? ''),
      missing: data['missing'] == true,
      lastError: data['last_error']?.toString(),
    );
  }
}
