/// Utilidades para normalizar y manipular URLs del servidor.
library;

import 'dart:convert';

final RegExp _multiSlash = RegExp(r'/{2,}');

/// Colapsa barras duplicadas conservando esquema y host.
String collapseSlashes(String url) {
  final trimmed = url.trim();
  final match = RegExp(r'^(https?://[^/]+)(/.*)?$').firstMatch(trimmed);
  if (match == null) return trimmed;
  final authority = match.group(1)!;
  final path = (match.group(2) ?? '/').replaceAll(_multiSlash, '/');
  return '$authority$path';
}

/// URL canonica de una carpeta: sin query/fragmento y con barra final.
String canonicalFolderUrl(String url) {
  var value = collapseSlashes(url);
  final hashIndex = value.indexOf('#');
  if (hashIndex >= 0) value = value.substring(0, hashIndex);
  final queryIndex = value.indexOf('?');
  if (queryIndex >= 0) value = value.substring(0, queryIndex);
  if (!value.endsWith('/')) value = '$value/';
  return value;
}

/// URL del directorio padre (con barra final). Devuelve null si es la raiz.
String? parentUrlOf(String url) {
  final uri = Uri.parse(collapseSlashes(url));
  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (segments.isEmpty) return null;
  segments.removeLast();
  final encoded = segments.map(Uri.encodeComponent).join('/');
  final path = encoded.isEmpty ? '/' : '/$encoded/';
  return '${uri.scheme}://${uri.authority}$path';
}

/// Resuelve un enlace (relativo o absoluto) contra la pagina actual.
String resolveUrl(String baseUrl, String href) {
  final trimmed = href.trim();
  try {
    final resolved = Uri.parse(baseUrl).resolve(trimmed);
    return collapseSlashes(resolved.toString());
  } on FormatException {
    return collapseSlashes(_fallbackResolve(baseUrl, trimmed));
  }
}

/// Resolucion de respaldo para enlaces con codificacion invalida.
String _fallbackResolve(String baseUrl, String href) {
  final base = Uri.parse(baseUrl);
  var path = href;
  if (!path.startsWith('/')) {
    final basePath = base.path.endsWith('/')
        ? base.path
        : base.path.substring(0, base.path.lastIndexOf('/') + 1);
    path = '$basePath$href';
  }
  final encoded = path
      .split('/')
      .map((segment) {
        if (segment.isEmpty) return segment;
        try {
          return Uri.encodeComponent(Uri.decodeComponent(segment));
        } catch (_) {
          return Uri.encodeComponent(segment);
        }
      })
      .join('/');
  return '${base.scheme}://${base.authority}$encoded';
}

/// Ruta legible: "Series / NETFLIX / Squid Game".
String displayPathOf(String url) {
  final uri = Uri.parse(url);
  return uri.pathSegments.where((s) => s.isNotEmpty).join(' / ');
}

/// Nombre visible del ultimo segmento de la URL.
String fileNameOf(String url) {
  final uri = Uri.parse(url);
  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (segments.isEmpty) return uri.host;
  return segments.last;
}

/// Limpia caracteres no validos para nombres de archivo y limita su longitud
/// en bytes (los sistemas de archivos permiten ~255 bytes por nombre).
String sanitizeSegment(String value) {
  var out = value.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
  out = out.replaceAll(RegExp(r'[\x00-\x1f]'), '');
  if (out.isEmpty || out == '.' || out == '..') out = 'sin-nombre';
  return _limitUtf8Bytes(out, 180);
}

String _limitUtf8Bytes(String input, int maxBytes) {
  final bytes = utf8.encode(input);
  if (bytes.length <= maxBytes) return input;

  var base = input;
  var extension = '';
  final dot = input.lastIndexOf('.');
  if (dot > 0 && input.length - dot <= 12) {
    extension = input.substring(dot);
    base = input.substring(0, dot);
  }
  final extensionBytes = utf8.encode(extension);
  final limit = (maxBytes - extensionBytes.length).clamp(1, maxBytes);
  final baseBytes = utf8.encode(base);
  var cut = limit.clamp(0, baseBytes.length);
  while (cut > 0 && cut < baseBytes.length && (baseBytes[cut] & 0xC0) == 0x80) {
    cut--;
  }
  final truncated = utf8.decode(
    baseBytes.sublist(0, cut),
    allowMalformed: true,
  );
  return truncated.isEmpty ? extension : '$truncated$extension';
}

/// Ruta relativa local (segura) a partir de la URL.
String localRelativePathOf(String url) {
  final uri = Uri.parse(url);
  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (segments.isEmpty) return sanitizeSegment(uri.host);
  return segments.map(sanitizeSegment).join('/');
}

/// Compara dos URLs de carpeta ignorando diferencias de barras.
bool isSameFolder(String a, String b) =>
    canonicalFolderUrl(a) == canonicalFolderUrl(b);
