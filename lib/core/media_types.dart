import 'package:flutter/material.dart';

import 'formatters.dart';

enum MediaKind {
  folder,
  video,
  audio,
  image,
  archive,
  document,
  book,
  app,
  other,
}

const Set<String> _videoExtensions = {
  'mp4',
  'mkv',
  'avi',
  'mov',
  'wmv',
  'flv',
  'webm',
  'm4v',
  'mpg',
  'mpeg',
  'ts',
  'vob',
  '3gp',
  'ogv',
  'divx',
};
const Set<String> _audioExtensions = {
  'mp3',
  'wav',
  'flac',
  'ogg',
  'm4a',
  'aac',
  'wma',
  'opus',
  'mid',
};
const Set<String> _imageExtensions = {
  'jpg',
  'jpeg',
  'png',
  'gif',
  'bmp',
  'webp',
  'tiff',
  'svg',
  'heic',
};
const Set<String> _archiveExtensions = {
  'zip',
  'rar',
  '7z',
  'tar',
  'gz',
  'bz2',
  'xz',
  'iso',
  'tgz',
};
const Set<String> _documentExtensions = {
  'pdf',
  'doc',
  'docx',
  'ppt',
  'pptx',
  'xls',
  'xlsx',
  'txt',
  'rtf',
  'csv',
  'srt',
  'sub',
  'nfo',
};
const Set<String> _bookExtensions = {
  'epub',
  'mobi',
  'azw3',
  'fb2',
  'cbr',
  'cbz',
  'djvu',
};

MediaKind kindForName(String name, {bool isDirectory = false}) {
  if (isDirectory) return MediaKind.folder;
  final dot = name.lastIndexOf('.');
  final extension = dot >= 0 ? name.substring(dot + 1).toLowerCase() : '';
  if (_videoExtensions.contains(extension)) return MediaKind.video;
  if (_audioExtensions.contains(extension)) return MediaKind.audio;
  if (_imageExtensions.contains(extension)) return MediaKind.image;
  if (_archiveExtensions.contains(extension)) return MediaKind.archive;
  if (_bookExtensions.contains(extension)) return MediaKind.book;
  if (_documentExtensions.contains(extension)) return MediaKind.document;
  if (extension == 'apk') return MediaKind.app;
  return MediaKind.other;
}

bool canPlayInApp(MediaKind kind) =>
    kind == MediaKind.video ||
    kind == MediaKind.audio ||
    kind == MediaKind.image;

IconData iconForKind(MediaKind kind, {bool folderOpen = false}) {
  switch (kind) {
    case MediaKind.folder:
      return folderOpen ? Icons.folder_open_rounded : Icons.folder_rounded;
    case MediaKind.video:
      return Icons.movie_rounded;
    case MediaKind.audio:
      return Icons.music_note_rounded;
    case MediaKind.image:
      return Icons.image_rounded;
    case MediaKind.archive:
      return Icons.folder_zip_rounded;
    case MediaKind.document:
      return Icons.description_rounded;
    case MediaKind.book:
      return Icons.menu_book_rounded;
    case MediaKind.app:
      return Icons.android_rounded;
    case MediaKind.other:
      return Icons.insert_drive_file_rounded;
  }
}

Color colorForKind(MediaKind kind, ColorScheme scheme) {
  switch (kind) {
    case MediaKind.folder:
      return scheme.primary;
    case MediaKind.video:
      return const Color(0xFF7C4DFF);
    case MediaKind.audio:
      return const Color(0xFF00897B);
    case MediaKind.image:
      return const Color(0xFF00838F);
    case MediaKind.archive:
      return const Color(0xFFEF6C00);
    case MediaKind.document:
      return const Color(0xFF546E7A);
    case MediaKind.book:
      return const Color(0xFF8D6E63);
    case MediaKind.app:
      return const Color(0xFF2E7D32);
    case MediaKind.other:
      return scheme.outline;
  }
}

/// Icono tematico para carpetas conocidas del sitio.
IconData folderIconForName(String name) {
  final key = foldText(name);
  if (key.contains('pelicula')) return Icons.local_movies_rounded;
  if (key.contains('serie') || key.contains('netflix')) {
    return Icons.live_tv_rounded;
  }
  if (key.contains('documental')) return Icons.theaters_rounded;
  if (key.contains('infantil') || key.contains('nino')) {
    return Icons.child_care_rounded;
  }
  if (key.contains('libro') || key.contains('ebook')) {
    return Icons.auto_stories_rounded;
  }
  if (key.contains('mp3') || key.contains('musica') || key.contains('audio')) {
    return Icons.library_music_rounded;
  }
  if (key.contains('reciente') || key.contains('nuevo')) {
    return Icons.new_releases_rounded;
  }
  if (key.contains('peticion')) return Icons.mark_email_unread_rounded;
  if (key.contains('programacion') ||
      key.contains('curso') ||
      key.contains('competitiva')) {
    return Icons.code_rounded;
  }
  if (key.contains('reality')) return Icons.emoji_events_rounded;
  if (key.contains('mochila')) return Icons.backpack_rounded;
  if (key.contains('festival') || key.contains('premio')) {
    return Icons.emoji_events_rounded;
  }
  if (key.contains('streaming')) return Icons.sensors_rounded;
  return Icons.folder_rounded;
}

List<Color> gradientForKind(MediaKind kind, ColorScheme scheme) {
  final base = colorForKind(kind, scheme);
  return [base, Color.lerp(base, scheme.tertiary, 0.55) ?? base];
}

/// Tipo MIME a partir del nombre de archivo (para MediaStore).
String mimeForName(String name) {
  final dot = name.lastIndexOf('.');
  final extension = dot >= 0 ? name.substring(dot + 1).toLowerCase() : '';
  switch (extension) {
    case 'mp4':
    case 'm4v':
      return 'video/mp4';
    case 'mkv':
      return 'video/x-matroska';
    case 'avi':
      return 'video/x-msvideo';
    case 'mov':
      return 'video/quicktime';
    case 'webm':
      return 'video/webm';
    case 'flv':
      return 'video/x-flv';
    case 'mpg':
    case 'mpeg':
      return 'video/mpeg';
    case 'ts':
      return 'video/mp2t';
    case '3gp':
      return 'video/3gpp';
    case 'wmv':
      return 'video/x-ms-wmv';
    case 'ogv':
      return 'video/ogg';
    case 'mp3':
      return 'audio/mpeg';
    case 'm4a':
      return 'audio/mp4';
    case 'aac':
      return 'audio/aac';
    case 'flac':
      return 'audio/flac';
    case 'wav':
      return 'audio/wav';
    case 'ogg':
      return 'audio/ogg';
    case 'opus':
      return 'audio/opus';
    case 'wma':
      return 'audio/x-ms-wma';
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'png':
      return 'image/png';
    case 'gif':
      return 'image/gif';
    case 'webp':
      return 'image/webp';
    case 'bmp':
      return 'image/bmp';
    case 'tif':
    case 'tiff':
      return 'image/tiff';
    case 'svg':
      return 'image/svg+xml';
    case 'heic':
      return 'image/heic';
    case 'zip':
      return 'application/zip';
    case 'rar':
      return 'application/vnd.rar';
    case '7z':
      return 'application/x-7z-compressed';
    case 'tar':
      return 'application/x-tar';
    case 'gz':
      return 'application/gzip';
    case 'iso':
      return 'application/x-iso9660-image';
    case 'pdf':
      return 'application/pdf';
    case 'doc':
      return 'application/msword';
    case 'docx':
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    case 'ppt':
      return 'application/vnd.ms-powerpoint';
    case 'pptx':
      return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
    case 'xls':
      return 'application/vnd.ms-excel';
    case 'xlsx':
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    case 'txt':
    case 'srt':
    case 'sub':
    case 'nfo':
      return 'text/plain';
    case 'epub':
      return 'application/epub+zip';
    case 'mobi':
      return 'application/x-mobipocket-ebook';
    case 'azw3':
      return 'application/vnd.amazon.ebook';
    case 'cbr':
      return 'application/vnd.comicbook-rar';
    case 'cbz':
      return 'application/vnd.comicbook+zip';
    case 'apk':
      return 'application/vnd.android.package-archive';
    default:
      return 'application/octet-stream';
  }
}
