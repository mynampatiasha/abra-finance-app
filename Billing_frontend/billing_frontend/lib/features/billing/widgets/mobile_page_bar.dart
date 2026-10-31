import 'package:flutter/material.dart';

const Color _pbNavy = Color(0xFF0D1B3E);

/// Page numbers for phones, shown at the TOP of the list so nobody has to scroll
/// down to change page: "Showing 1–20 of 3196", a "Page 3 of 160" dropdown to jump
/// to any page, and ‹ 1 … 4 5 6 7 8 … 160 › (scrolls sideways when too wide).
class MobilePageBar extends StatelessWidget {
  final int currentPage;
  final int totalPages;
  final String summary; // e.g. "Showing 1–20 of 3196"
  final ValueChanged<int> onPage;

  const MobilePageBar({
    super.key,
    required this.currentPage,
    required this.totalPages,
    required this.summary,
    required this.onPage,
  });

  /// the five numbers around the current page
  static List<int> window(int current, int total) {
    if (total <= 5) return List.generate(total, (i) => i + 1);
    final start = (current - 2).clamp(1, total - 4);
    return List.generate(5, (i) => start + i);
  }

  @override
  Widget build(BuildContext context) {
    final pages = window(currentPage, totalPages);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(bottom: BorderSide(color: Color(0xFFEEF2F7)))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(summary,
                style: TextStyle(
                    fontSize: 12.5,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500),
                overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 8),
          _jump(),
        ]),
        const SizedBox(height: 8),
        // the arrows stay at the two ends; only the numbers between them scroll
        Row(children: [
          _nav(Icons.chevron_left, currentPage > 1,
              () => onPage(currentPage - 1)),
          const SizedBox(width: 4),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (pages.first > 1) ...[
                  _num(1),
                  if (pages.first > 2) _dots(),
                ],
                ...pages.map(_num),
                if (pages.last < totalPages) ...[
                  if (pages.last < totalPages - 1) _dots(),
                  _num(totalPages),
                ],
              ]),
            ),
          ),
          const SizedBox(width: 4),
          _nav(Icons.chevron_right, currentPage < totalPages,
              () => onPage(currentPage + 1)),
        ]),
      ]),
    );
  }

  Widget _jump() => Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
            color: const Color(0xFFF7F9FC),
            border: Border.all(color: const Color(0xFFDDE3EE)),
            borderRadius: BorderRadius.circular(8)),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<int>(
            value: currentPage.clamp(1, totalPages),
            isDense: true,
            icon: const Icon(Icons.expand_more, size: 18, color: _pbNavy),
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: _pbNavy),
            // the closed box says "Page 3 of 160"; the open list is just the numbers
            selectedItemBuilder: (_) => List.generate(
                totalPages,
                (i) => Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Page ${i + 1} of $totalPages'))),
            items: List.generate(
                totalPages,
                (i) => DropdownMenuItem(
                    value: i + 1, child: Text('Page ${i + 1}'))),
            onChanged: (v) {
              if (v != null && v != currentPage) onPage(v);
            },
          ),
        ),
      );

  Widget _dots() => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Text('…', style: TextStyle(color: Colors.grey[400])));

  Widget _num(int page) {
    final active = currentPage == page;
    return GestureDetector(
      onTap: active ? null : () => onPage(page),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        width: 34,
        height: 34,
        decoration: BoxDecoration(
            color: active ? _pbNavy : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: active ? _pbNavy : Colors.grey[300]!)),
        child: Center(
            child: Text('$page',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: active ? FontWeight.bold : FontWeight.normal,
                    color: active ? Colors.white : Colors.grey[700]))),
      ),
    );
  }

  Widget _nav(IconData icon, bool enabled, VoidCallback onTap) =>
      GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
              color: enabled ? Colors.white : Colors.grey[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[300]!)),
          child:
              Icon(icon, size: 18, color: enabled ? _pbNavy : Colors.grey[300]),
        ),
      );
}
