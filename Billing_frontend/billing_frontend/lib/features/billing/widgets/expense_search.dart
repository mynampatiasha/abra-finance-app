// =============================================================================
// EXPENSE SEARCH — two ways to search, chosen on the screen
//
//   STRICT  The exact text you type, as a phrase, inside ONE of the columns the
//           table shows (number, date, account, vendor, customer, invoice number,
//           paid through). A number must be the WHOLE amount: 560 finds 560.00 and
//           EXP000560, never 78560. Notes, tags, item lines and file names are not
//           searched.
//   LOOSE   Anything, anywhere: every word typed must be found, in any order, in
//           any field (also notes, tags, item lines, file names), and a number may
//           be part of a bigger number.
//
// Upper / lower case never matters. Pure Dart: no screen, no server.
// =============================================================================

import '../../../core/services/expenses_service.dart';

enum SearchMode { strict, loose }

/// What a table cell holds, so a number is coloured the way it was matched
enum FieldKind { text, money, serial, date }

/// One row of the "All Accounts" dropdown
class AccountOption {
  final String name;
  final int count;
  const AccountOption(this.name, this.count);
}

/// What strict search looks at for one expense (only what the table shows)
class StrictEntry {
  final List<String> fields; // lower-case text of each column
  final Set<String> amounts; // "560.00" for amount, tax, total (sign ignored)
  final Set<int> serials; // 11 for EXP000011, 2161 for Ref-02161 (leading zeros ignored)
  final Set<int> years; // 2026
  StrictEntry(this.fields, this.amounts, this.serials, this.years);
}

class ExpenseSearch {
  // A character nobody types, placed between fields so that a word can never
  // match "across" two fields (the end of one and the start of the next).
  static const String _sep = '\u0001';

  static const List<String> _months = [
    'January', 'February', 'March', 'April', 'May', 'June', 'July',
    'August', 'September', 'October', 'November', 'December',
  ];

  // ───────────────────────── shared helpers ─────────────────────────

  /// "₹1,000", "rs 1,000", "1000.5" -> "1000" / "1000.5". null when it is not an amount.
  static String? _asNumber(String token) {
    var t = token.trim().replaceAll(',', '').replaceAll('₹', '').trim();
    if (t.startsWith('rs.')) {
      t = t.substring(3).trim();
    } else if (t.startsWith('rs')) {
      t = t.substring(2).trim();
    }
    if (t.isEmpty) return null;
    return RegExp(r'^-?\d+(\.\d+)?$').hasMatch(t) ? t : null;
  }

  static String _key(double v) => v.abs().toStringAsFixed(2);

  /// The ways a date can be typed: 2026-09-05, 05 Sep 2026, 05/09/2026, September 2026 ...
  static List<String> _dateForms(String raw) {
    final out = <String>[raw];
    final d = DateTime.tryParse(raw);
    if (d == null) return out;
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final year = d.year.toString();
    final month = _months[d.month - 1];
    final short = month.substring(0, 3);
    out.addAll([
      '$dd $short $year', // 05 Sep 2026  (as shown in the list)
      '$dd/$mm/$year',
      '$dd-$mm-$year',
      '$month $year',
      '$month ${d.day}',
    ]);
    return out;
  }

  // ───────────────────────── LOOSE ─────────────────────────

  /// What the user typed -> the words to look for. Empty / blank means "no search".
  /// A lone currency mark (rs, ₹, inr) is not a word to look for.
  static List<String> tokens(String query) {
    const marks = {'rs', 'rs.', '₹', 'inr'};
    return query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty && !marks.contains(t))
        .toList();
  }

  /// Every word must appear in [haystack] (the text built by [textFor]).
  static bool matches(String haystack, List<String> tokens) {
    for (final t in tokens) {
      if (haystack.contains(t)) continue;
      final n = _asNumber(t);
      if (n != null && n != t && haystack.contains(n)) continue;
      return false;
    }
    return true;
  }

  static void _add(StringBuffer b, String? s) {
    if (s == null) return;
    final t = s.trim();
    if (t.isEmpty) return;
    b.write(t.toLowerCase());
    b.write(_sep);
  }

  static void _addMoney(StringBuffer b, double v) {
    // "1000.00" and "1000" — typing either finds it; the sign is not needed
    final fixed = v.toStringAsFixed(2);
    b.write(fixed);
    b.write(_sep);
    if (fixed.endsWith('.00')) {
      b.write(fixed.substring(0, fixed.length - 3));
      b.write(_sep);
    }
  }

  /// All the searchable text of one expense, lower case (used by LOOSE).
  static String textFor(Expense e) {
    final b = StringBuffer();
    _add(b, e.expenseNumber);
    for (final f in _dateForms(e.date)) {
      _add(b, f);
    }
    _add(b, e.expenseAccount);
    _add(b, e.vendor);
    _add(b, e.customerName);
    _add(b, e.invoiceNumber);
    _add(b, e.paidThrough);
    _add(b, e.project);
    _add(b, e.notes);
    for (final t in e.reportingTags) {
      _add(b, t);
    }
    _addMoney(b, e.amount);
    _addMoney(b, e.tax);
    _addMoney(b, e.total);
    if (e.isBillable) {
      _add(b, 'billable');
      _addMoney(b, e.billableAmount);
    }
    if (e.isItemized) {
      _add(b, 'itemized');
      for (final i in e.itemizedExpenses) {
        _add(b, i.expenseAccount);
        _add(b, i.description);
        _addMoney(b, i.amount);
      }
    }
    for (final p in e.proofFiles) {
      _add(b, p.originalName);
    }
    if (e.proofFiles.isEmpty) _add(b, e.proofFile?.originalName);
    _add(b, e.receiptFile?.originalName);
    return b.toString();
  }

  // ───────────────────────── STRICT ─────────────────────────

  static String normalise(String q) => q.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  static void _runs(String? s, Set<int> into) {
    if (s == null) return;
    for (final m in RegExp(r'\d+').allMatches(s)) {
      final g = m.group(0)!;
      if (g.length > 15) continue;
      final v = int.tryParse(g);
      if (v != null) into.add(v);
    }
  }

  /// The text of the columns the table shows, plus the numbers that can be matched whole.
  static StrictEntry strictFor(Expense e) {
    final fields = <String>[];
    void add(String? s) {
      final t = s?.trim().toLowerCase();
      if (t != null && t.isNotEmpty) fields.add(t);
    }

    add(e.expenseNumber);
    _dateForms(e.date).forEach(add);
    add(e.expenseAccount);
    add(e.vendor);
    add(e.customerName);
    add(e.invoiceNumber);
    add(e.paidThrough);
    if (e.isBillable) add('billable');

    final amounts = <String>{_key(e.amount), _key(e.tax), _key(e.total)};
    if (e.isBillable) amounts.add(_key(e.billableAmount));
    final serials = <int>{};
    _runs(e.expenseNumber, serials);
    _runs(e.invoiceNumber, serials);
    final years = <int>{};
    final d = DateTime.tryParse(e.date);
    if (d != null) years.add(d.year);
    return StrictEntry(fields, amounts, serials, years);
  }

  static bool _isLetterOrDigit(int c) =>
      (c >= 48 && c <= 57) || (c >= 97 && c <= 122) || (c >= 65 && c <= 90) || c > 127;

  /// [phrase] appears in [field] and begins at the start of a word, so typing
  /// "off" finds "Office Expenses" but typing "ice" does not.
  static bool _phraseAtWordStart(String field, String phrase) {
    var from = 0;
    while (true) {
      final i = field.indexOf(phrase, from);
      if (i < 0) return false;
      if (i == 0 || !_isLetterOrDigit(field.codeUnitAt(i - 1))) return true;
      from = i + 1;
    }
  }

  /// STRICT: the whole typed text as one phrase inside one column; a number as a whole number.
  static bool matchesStrict(StrictEntry en, String query) {
    final q = normalise(query);
    if (q.isEmpty) return true;
    final n = _asNumber(q);
    if (n != null) {
      final v = double.tryParse(n);
      if (v != null && en.amounts.contains(_key(v))) return true;
      if (!n.contains('.') && !n.startsWith('-')) {
        final i = int.tryParse(n);
        if (i != null) {
          if (en.serials.contains(i)) return true;
          if (n.length == 4 && en.years.contains(i)) return true;
        }
      }
      return false; // a number never falls back to "part of some text or bigger number"
    }
    for (final f in en.fields) {
      if (_phraseAtWordStart(f, q)) return true;
    }
    return false;
  }

  // ───────────────────────── highlighting ─────────────────────────

  /// Which parts of [text] (as shown on the screen) are what the search found,
  /// as [start, end) pairs. Follows the same rules as the search itself, so
  /// whatever is coloured is exactly why the row came up.
  /// [rawDate] is the stored date, for [FieldKind.date] only.
  static List<List<int>> highlightRanges(
    String text,
    String query, {
    required bool strict,
    FieldKind kind = FieldKind.text,
    String? rawDate,
  }) {
    final out = <List<int>>[];
    if (text.isEmpty) return out;
    final lower = text.toLowerCase();

    if (strict) {
      final q = normalise(query);
      if (q.isEmpty) return out;
      final n = _asNumber(q);
      if (n != null) {
        final v = double.tryParse(n);
        if (kind == FieldKind.money) {
          final tv = double.tryParse(text.replaceAll('₹', '').replaceAll(',', '').trim());
          if (v != null && tv != null && _key(tv) == _key(v)) {
            final s = text.indexOf(RegExp(r'\d'));
            if (s >= 0) out.add([s, text.length]);
          }
        } else if ((kind == FieldKind.serial || kind == FieldKind.date) &&
            !n.contains('.') &&
            !n.startsWith('-')) {
          final i = int.tryParse(n);
          for (final m in RegExp(r'\d+').allMatches(text)) {
            final g = m.group(0)!;
            if (g.length > 15 || int.tryParse(g) != i) continue;
            if (kind == FieldKind.date && !(n.length == 4 && g.length == 4)) continue;
            out.add([m.start, m.end]);
          }
        }
        return out;
      }
      var from = 0;
      while (true) {
        final i = lower.indexOf(q, from);
        if (i < 0) break;
        if (i == 0 || !_isLetterOrDigit(lower.codeUnitAt(i - 1))) {
          out.add([i, i + q.length]);
        }
        from = i + 1;
      }
      // a date typed as "sep 2026" is found through its other forms: colour it all
      if (out.isEmpty && kind == FieldKind.date && rawDate != null) {
        for (final f in _dateForms(rawDate)) {
          if (_phraseAtWordStart(f.toLowerCase(), q)) {
            out.add([0, text.length]);
            break;
          }
        }
      }
      return out;
    }

    // LOOSE: every typed word, wherever it appears in this text
    for (final t in tokens(query)) {
      final alt = _asNumber(t);
      for (final needle in {t, if (alt != null) alt}) {
        var from = 0;
        while (true) {
          final i = lower.indexOf(needle, from);
          if (i < 0) break;
          out.add([i, i + needle.length]);
          from = i + needle.length;
        }
      }
    }
    return _merge(out);
  }

  static List<List<int>> _merge(List<List<int>> r) {
    if (r.length < 2) return r;
    r.sort((a, b) => a[0].compareTo(b[0]));
    final out = <List<int>>[r.first];
    for (final x in r.skip(1)) {
      if (x[0] <= out.last[1]) {
        if (x[1] > out.last[1]) out.last[1] = x[1];
      } else {
        out.add(x);
      }
    }
    return out;
  }

  // ───────────────────────── account dropdown ─────────────────────────

  /// The accounts that really are on the expenses, with how many each has, by name.
  static List<AccountOption> accountOptions(Iterable<Expense> list) {
    final counts = <String, int>{};
    for (final e in list) {
      final n = e.expenseAccount;
      if (n.trim().isEmpty) continue;
      counts[n] = (counts[n] ?? 0) + 1;
    }
    final out = counts.entries.map((x) => AccountOption(x.key, x.value)).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return out;
  }
}

/// Builds each expense's text once and reuses it while typing. When a row changes
/// (a proof added or removed) its entry is dropped and rebuilt on the next search.
class ExpenseSearchIndex {
  final Map<String, String> _loose = {};
  final Map<String, StrictEntry> _strict = {};

  String textFor(Expense e) => _loose.putIfAbsent(e.id, () => ExpenseSearch.textFor(e));

  StrictEntry strictFor(Expense e) => _strict.putIfAbsent(e.id, () => ExpenseSearch.strictFor(e));

  void invalidate(String expenseId) {
    _loose.remove(expenseId);
    _strict.remove(expenseId);
  }

  void clear() {
    _loose.clear();
    _strict.clear();
  }
}
