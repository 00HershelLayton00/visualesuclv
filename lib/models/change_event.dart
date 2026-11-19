enum ChangeEventType { updated, disappeared, restored }

/// Novedad detectada en una carpeta favorita.
class ChangeEvent {
  ChangeEvent({
    required this.folderUrl,
    required this.folderName,
    required this.type,
    this.added = const [],
    this.removed = const [],
    this.totalAdded = 0,
    this.totalRemoved = 0,
    required this.at,
    this.read = false,
  });

  final String folderUrl;
  final String folderName;
  final ChangeEventType type;
  final List<String> added;
  final List<String> removed;
  final int totalAdded;
  final int totalRemoved;
  final DateTime at;
  bool read;

  bool get hasItems => added.isNotEmpty || removed.isNotEmpty;

  Map<String, dynamic> toJson() => {
    'folder_url': folderUrl,
    'folder_name': folderName,
    'type': type.name,
    'added': added,
    'removed': removed,
    'total_added': totalAdded,
    'total_removed': totalRemoved,
    'at': at.toIso8601String(),
    'read': read,
  };

  static ChangeEvent? fromJson(dynamic data) {
    if (data is! Map) return null;
    final folderUrl = data['folder_url']?.toString();
    if (folderUrl == null) return null;
    final typeName = data['type']?.toString() ?? 'updated';
    final type = ChangeEventType.values.firstWhere(
      (value) => value.name == typeName,
      orElse: () => ChangeEventType.updated,
    );
    return ChangeEvent(
      folderUrl: folderUrl,
      folderName: data['folder_name']?.toString() ?? folderUrl,
      type: type,
      added: (data['added'] as List? ?? const [])
          .map((item) => item.toString())
          .toList(),
      removed: (data['removed'] as List? ?? const [])
          .map((item) => item.toString())
          .toList(),
      totalAdded:
          (data['total_added'] as num?)?.toInt() ??
          (data['added'] as List? ?? const []).length,
      totalRemoved:
          (data['total_removed'] as num?)?.toInt() ??
          (data['removed'] as List? ?? const []).length,
      at: DateTime.tryParse(data['at']?.toString() ?? '') ?? DateTime.now(),
      read: data['read'] == true,
    );
  }
}
