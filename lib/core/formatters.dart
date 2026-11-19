/// Formateo de tamanos, fechas y texto para busqueda.
library;

const Map<String, String> _diacritics = {
  'á': 'a',
  'à': 'a',
  'ä': 'a',
  'â': 'a',
  'ã': 'a',
  'é': 'e',
  'è': 'e',
  'ë': 'e',
  'ê': 'e',
  'í': 'i',
  'ì': 'i',
  'ï': 'i',
  'î': 'i',
  'ó': 'o',
  'ò': 'o',
  'ö': 'o',
  'ô': 'o',
  'õ': 'o',
  'ú': 'u',
  'ù': 'u',
  'ü': 'u',
  'û': 'u',
  'ñ': 'n',
  'ç': 'c',
};

/// Minusculas sin acentos, con la misma longitud que la entrada.
String foldText(String input) {
  final buffer = StringBuffer();
  for (final rune in input.toLowerCase().runes) {
    final char = String.fromCharCode(rune);
    buffer.write(_diacritics[char] ?? char);
  }
  return buffer.toString();
}

String formatBytes(int? bytes) {
  if (bytes == null || bytes < 0) return '—';
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var value = bytes / 1024;
  var index = 0;
  while (value >= 1024 && index < units.length - 1) {
    value /= 1024;
    index++;
  }
  final text = value >= 100
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1).replaceFirst('.0', '');
  return '$text ${units[index]}';
}

String formatSpeed(double bytesPerSecond) {
  if (bytesPerSecond <= 0) return '';
  return '${formatBytes(bytesPerSecond.round())}/s';
}

String _two(int value) => value.toString().padLeft(2, '0');

String formatDateTime(DateTime? date) {
  if (date == null) return '—';
  return '${_two(date.day)}/${_two(date.month)}/${date.year} '
      '${_two(date.hour)}:${_two(date.minute)}';
}

String formatRelative(DateTime? date) {
  if (date == null) return '—';
  final now = DateTime.now();
  final diff = now.difference(date);
  if (diff.isNegative) return 'ahora mismo';
  if (diff.inSeconds < 60) return 'ahora mismo';
  if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'hace ${diff.inHours} h';
  if (diff.inDays == 1) return 'ayer';
  if (diff.inDays < 30) return 'hace ${diff.inDays} dias';
  return formatDateTime(date);
}

String formatDuration(Duration? duration) {
  if (duration == null) return '--:--';
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);
  if (hours > 0) return '$hours:${_two(minutes)}:${_two(seconds)}';
  return '${_two(minutes)}:${_two(seconds)}';
}

/// Numero con separador de miles: 30 006.
String formatCount(int value) {
  final text = value.toString();
  final buffer = StringBuffer();
  for (var index = 0; index < text.length; index++) {
    if (index > 0 && (text.length - index) % 3 == 0) buffer.write(' ');
    buffer.write(text[index]);
  }
  return buffer.toString();
}
