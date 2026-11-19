import 'package:flutter/material.dart';

import '../core/formatters.dart';

/// Texto con las coincidencias de busqueda resaltadas.
class HighlightedText extends StatelessWidget {
  const HighlightedText({
    super.key,
    required this.text,
    required this.query,
    this.style,
    this.highlightStyle,
    this.maxLines = 1,
  });

  final String text;
  final String query;
  final TextStyle? style;
  final TextStyle? highlightStyle;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final baseStyle =
        style ??
        const TextStyle(fontWeight: FontWeight.w600, fontSize: 15, height: 1.2);
    final markStyle =
        highlightStyle ??
        baseStyle.copyWith(color: scheme.primary, fontWeight: FontWeight.w800);

    final terms = query
        .trim()
        .split(RegExp(r'\s+'))
        .where((term) => term.isNotEmpty)
        .toList();
    if (terms.isEmpty) {
      return Text(
        text,
        style: baseStyle,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
      );
    }

    final folded = foldText(text);
    final ranges = <List<int>>[];
    for (final term in terms) {
      final foldedTerm = foldText(term);
      var start = 0;
      while (foldedTerm.isNotEmpty) {
        final index = folded.indexOf(foldedTerm, start);
        if (index < 0) break;
        ranges.add([index, index + foldedTerm.length]);
        start = index + foldedTerm.length;
      }
    }
    if (ranges.isEmpty) {
      return Text(
        text,
        style: baseStyle,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
      );
    }
    ranges.sort((a, b) => a[0].compareTo(b[0]));

    final spans = <TextSpan>[];
    var cursor = 0;
    for (final range in ranges) {
      final start = range[0].clamp(cursor, text.length);
      final end = range[1].clamp(start, text.length);
      if (start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, start)));
      }
      if (end > start) {
        spans.add(TextSpan(text: text.substring(start, end), style: markStyle));
      }
      cursor = end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor)));
    }

    return RichText(
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(style: baseStyle, children: spans),
    );
  }
}
