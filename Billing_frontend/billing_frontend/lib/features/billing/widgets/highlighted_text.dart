import 'package:flutter/material.dart';

import 'expense_search.dart';

/// Text with the parts the search found coloured; nothing else changes.
class HighlightedText extends StatelessWidget {
  final String text;
  final String query;
  final bool strict;
  final FieldKind kind;
  final String? rawDate;
  final TextStyle style;
  final TextOverflow overflow;

  const HighlightedText(
    this.text, {
    super.key,
    required this.query,
    required this.strict,
    required this.style,
    this.kind = FieldKind.text,
    this.rawDate,
    this.overflow = TextOverflow.ellipsis,
  });

  static const Color _mark = Color(0xFFFFE08A);

  @override
  Widget build(BuildContext context) {
    final ranges = query.trim().isEmpty
        ? const <List<int>>[]
        : ExpenseSearch.highlightRanges(text, query,
            strict: strict, kind: kind, rawDate: rawDate);
    if (ranges.isEmpty) return Text(text, style: style, overflow: overflow);
    final marked = style.copyWith(backgroundColor: _mark);
    final parts = <TextSpan>[];
    var at = 0;
    for (final r in ranges) {
      if (r[0] > at) parts.add(TextSpan(text: text.substring(at, r[0])));
      parts.add(TextSpan(text: text.substring(r[0], r[1]), style: marked));
      at = r[1];
    }
    if (at < text.length) parts.add(TextSpan(text: text.substring(at)));
    return Text.rich(TextSpan(style: style, children: parts), overflow: overflow);
  }
}
