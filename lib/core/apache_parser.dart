import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../models/remote_entry.dart';
import 'url_utils.dart';

/// Parsea el listado de directorio de Apache (tabla o formato <pre>).
List<RemoteEntry> parseApacheIndex(String htmlText, String pageUrl) {
  final document = html_parser.parse(htmlText);
  final table = document.querySelector('table');
  if (table != null) {
    final entries = _parseTable(table, pageUrl);
    if (entries.isNotEmpty || document.querySelector('pre') == null) {
      return entries;
    }
  }
  final pre = document.querySelector('pre');
  if (pre != null) return _parsePre(pre, pageUrl);
  return const [];
}

List<RemoteEntry> _parseTable(dom.Element table, String pageUrl) {
  final entries = <RemoteEntry>[];
  for (final row in table.querySelectorAll('tr')) {
    final cells = row.querySelectorAll('td');
    if (cells.length < 4) continue;
    final iconAlt = cells[0].querySelector('img')?.attributes['alt'] ?? '';
    final anchor = cells[1].querySelector('a');
    final href = anchor?.attributes['href'];
    if (anchor == null || href == null) continue;
    if (href.startsWith('?')) continue;
    if (iconAlt == '[PARENTDIR]') continue;
    final name = _cleanName(anchor.text);
    if (name.isEmpty || name.toLowerCase() == 'parent directory') continue;
    final isDirectory = iconAlt == '[DIR]' || href.endsWith('/');
    entries.add(
      RemoteEntry(
        name: name,
        url: resolveUrl(pageUrl, href),
        isDirectory: isDirectory,
        modified: parseApacheDate(cells[2].text),
        size: isDirectory ? null : parseApacheSize(cells[3].text),
      ),
    );
  }
  return entries;
}

List<RemoteEntry> _parsePre(dom.Element pre, String pageUrl) {
  final entries = <RemoteEntry>[];
  final linkPattern = RegExp(
    r'href="([^"]+)"[^>]*>(.*?)</a>(.*)$',
    caseSensitive: false,
  );
  for (final line in pre.innerHtml.split('\n')) {
    final match = linkPattern.firstMatch(line);
    if (match == null) continue;
    final href = match.group(1)!;
    final text = _cleanName(_decodeEntities(match.group(2)!));
    final rest = _decodeEntities(match.group(3)!);
    if (text.isEmpty || text.toLowerCase().contains('parent directory')) {
      continue;
    }
    final isDirectory = href.endsWith('/');
    entries.add(
      RemoteEntry(
        name: text,
        url: resolveUrl(pageUrl, href),
        isDirectory: isDirectory,
        modified: parseApacheDate(rest),
        size: isDirectory ? null : parseApacheSize(rest.trim()),
      ),
    );
  }
  return entries;
}

DateTime? parseApacheDate(String raw) {
  final match = RegExp(
    r'(\d{4})-(\d{2})-(\d{2})\s+(\d{1,2}):(\d{2})',
  ).firstMatch(raw);
  if (match == null) return null;
  return DateTime(
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
    int.parse(match.group(4)!),
    int.parse(match.group(5)!),
  );
}

int? parseApacheSize(String raw) {
  final text = raw.replaceAll('&nbsp;', ' ').trim();
  if (text.isEmpty || text == '-') return null;
  final match = RegExp(r'^([\d.]+)\s*([KMGT])?$').firstMatch(text);
  if (match == null) return null;
  final value = double.tryParse(match.group(1)!);
  if (value == null) return null;
  const factors = <String, int>{
    'K': 1024,
    'M': 1024 * 1024,
    'G': 1024 * 1024 * 1024,
    'T': 1024 * 1024 * 1024 * 1024,
  };
  final unit = match.group(2);
  return (value * (unit == null ? 1 : factors[unit]!)).round();
}

String _cleanName(String value) {
  var out = _decodeEntities(value).replaceAll('\u00a0', ' ').trim();
  while (out.endsWith('/')) {
    out = out.substring(0, out.length - 1).trim();
  }
  return out;
}

String _decodeEntities(String value) {
  var out = value.replaceAll(RegExp('<[^>]*>'), '');
  const entities = {
    '&amp;': '&',
    '&lt;': '<',
    '&gt;': '>',
    '&quot;': '"',
    '&#39;': "'",
    '&apos;': "'",
    '&nbsp;': ' ',
  };
  for (final entry in entities.entries) {
    out = out.replaceAll(entry.key, entry.value);
  }
  return out;
}
