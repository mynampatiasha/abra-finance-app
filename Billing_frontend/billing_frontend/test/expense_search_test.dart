// Tests for the universal expense search. Run with:
//   flutter test test/expense_search_test.dart

import 'package:abra_finance/core/services/expenses_service.dart';
import 'package:abra_finance/features/billing/widgets/expense_search.dart';
import 'package:flutter_test/flutter_test.dart';

Expense exp({
  String id = 'e1',
  String? number = 'EXP000011',
  String date = '2026-09-05',
  String account = 'Transportation Charges',
  double amount = 1000,
  double tax = -180,
  double total = 820,
  String paidThrough = 'IDFC First Bank',
  String? vendor,
  String? invoice,
  String? customer,
  bool billable = false,
  String? project,
  double billableAmount = 0,
  List<String> tags = const [],
  String? notes,
  List<ItemizedExpenseData> items = const [],
  ReceiptFile? receipt,
  List<ProofFile> proofs = const [],
}) =>
    Expense(
      id: id,
      expenseNumber: number,
      date: date,
      expenseAccount: account,
      amount: amount,
      tax: tax,
      total: total,
      paidThrough: paidThrough,
      vendor: vendor,
      invoiceNumber: invoice,
      customerName: customer,
      isBillable: billable,
      project: project,
      markupPercentage: 0,
      billableAmount: billableAmount,
      reportingTags: tags,
      notes: notes,
      isItemized: items.isNotEmpty,
      itemizedExpenses: items,
      receiptFile: receipt,
      proofFiles: proofs,
      proofFile: proofs.isEmpty ? null : proofs.first,
      createdAt: '2026-09-05T00:00:00.000Z',
      updatedAt: '2026-09-05T00:00:00.000Z',
    );

ProofFile proof(String name) => ProofFile(filename: 'proof-1.jpg', originalName: name, size: 10, mimetype: 'image/jpeg');

bool hit(Expense e, String query) =>
    ExpenseSearch.matches(ExpenseSearch.textFor(e), ExpenseSearch.tokens(query));


bool strict(Expense e, String query) => ExpenseSearch.matchesStrict(ExpenseSearch.strictFor(e), query);

void main() {
  group('words typed', () {
    test('blank or spaces mean no search; words are split on any spaces and lower-cased', () {
      expect(ExpenseSearch.tokens(''), isEmpty);
      expect(ExpenseSearch.tokens('   '), isEmpty);
      expect(ExpenseSearch.tokens('  Fuel   IDFC '), ['fuel', 'idfc']);
    });
  });

  group('what it finds (it used to find only account, vendor, customer, invoice number)', () {
    final e = exp(
      vendor: 'SIP STYLE',
      invoice: 'VND-001',
      customer: 'Rimox Marketing',
      project: 'Warehouse Move',
      notes: 'Diesel for the Tata 407',
      tags: ['Branch: Kasthuri Nagar', 'Urgent'],
      billable: true,
      billableAmount: 1150,
      receipt: ReceiptFile(filename: 'r.pdf', originalName: 'fuel_receipt.pdf', path: 'x', size: 1, mimetype: 'application/pdf'),
      proofs: [proof('EXP000011_Proof-1_2026-09-05_1124.jpg')],
      items: [ItemizedExpenseData(expenseAccount: 'Fuel Charges', amount: 640, description: 'Diesel 20 litres')],
    );

    test('the four old fields still work', () {
      expect(hit(e, 'transportation'), isTrue);
      expect(hit(e, 'sip style'), isTrue);
      expect(hit(e, 'rimox'), isTrue);
      expect(hit(e, 'vnd-001'), isTrue);
    });

    test('expense number, paid-through, project, notes, tags', () {
      expect(hit(e, 'exp000011'), isTrue);
      expect(hit(e, 'EXP000011'), isTrue);
      expect(hit(e, 'idfc'), isTrue);
      expect(hit(e, 'warehouse'), isTrue);
      expect(hit(e, 'tata 407'), isTrue);
      expect(hit(e, 'kasthuri'), isTrue);
      expect(hit(e, 'urgent'), isTrue);
      expect(hit(e, 'billable'), isTrue);
    });

    test('item lines, proof file names and the receipt name', () {
      expect(hit(e, 'fuel charges'), isTrue);
      expect(hit(e, 'diesel 20'), isTrue);
      expect(hit(e, 'itemized'), isTrue);
      expect(hit(e, 'proof-1'), isTrue);
      expect(hit(e, 'fuel_receipt'), isTrue);
    });

    test('things that are not on the expense are not found', () {
      expect(hit(e, 'zzz'), isFalse);
      expect(hit(e, 'hdfc'), isFalse);
      expect(hit(e, 'exp000012'), isFalse);
    });
  });

  group('dates: found however they are typed', () {
    final e = exp(date: '2026-09-05');
    test('as stored, as shown in the list, with slashes or dashes', () {
      expect(hit(e, '2026-09-05'), isTrue);
      expect(hit(e, '2026-09'), isTrue);
      expect(hit(e, '05 sep 2026'), isTrue);
      expect(hit(e, '05/09/2026'), isTrue);
      expect(hit(e, '05-09-2026'), isTrue);
    });
    test('month names, full or short, with or without the year', () {
      expect(hit(e, 'september'), isTrue);
      expect(hit(e, 'sep'), isTrue);
      expect(hit(e, 'sep 2026'), isTrue);
      expect(hit(e, 'september 2026'), isTrue);
      expect(hit(e, 'oct'), isFalse);
      expect(hit(e, '2025'), isFalse);
    });
    test('a date with a time stored after it still works', () {
      expect(hit(exp(date: '2026-09-05T00:00:00.000Z'), '05 sep 2026'), isTrue);
    });
  });

  group('amounts', () {
    final e = exp(amount: 1000, tax: -180, total: 820);
    test('typed as 1000, 1,000, ₹1000, rs 1,000 or 1000.00', () {
      for (final q in ['1000', '1,000', '₹1000', '₹1,000', 'rs 1,000', 'rs1000', '1000.00', '820', '820.00']) {
        expect(hit(e, q), isTrue, reason: q);
      }
    });
    test('a tax shown as -180.00 is found by typing 180', () {
      expect(hit(e, '180'), isTrue);
      expect(hit(e, '180.00'), isTrue);
    });
    test('decimals and the billable amount', () {
      final d = exp(amount: 1234.5, total: 1234.5, tax: 0, billable: true, billableAmount: 1500.25);
      expect(hit(d, '1234.5'), isTrue);
      expect(hit(d, '1,234.50'), isTrue);
      expect(hit(d, '1500.25'), isTrue);
    });
    test('an amount that is not there is not found', () {
      expect(hit(e, '7777'), isFalse);
      expect(hit(e, '1000000'), isFalse);
    });
  });

  group('several words', () {
    final e = exp(account: 'Fuel Charges', paidThrough: 'IDFC First Bank', vendor: 'Indian Oil');
    test('all words must be found, in any order, in different fields', () {
      expect(hit(e, 'fuel idfc'), isTrue);
      expect(hit(e, 'idfc fuel oil'), isTrue);
      expect(hit(e, 'fuel hdfc'), isFalse);
    });
    test('a word never matches across the end of one field and the start of the next', () {
      final x = exp(number: 'AB', account: 'CD', vendor: null, paidThrough: 'EF');
      expect(hit(x, 'abcd'), isFalse);
      expect(hit(x, 'cdef'), isFalse);
      expect(hit(x, 'ab cd ef'), isTrue);
    });
  });

  group('the saved text stays correct when a row changes', () {
    test('a proof added later becomes searchable only after the row is refreshed', () {
      final e = exp();
      final index = ExpenseSearchIndex();
      expect(ExpenseSearch.matches(index.textFor(e), ['newscan']), isFalse);
      e.setProofs([proof('NewScan.jpg')]);
      // the old text is still cached until the page tells the index
      expect(ExpenseSearch.matches(index.textFor(e), ['newscan']), isFalse);
      index.invalidate(e.id);
      expect(ExpenseSearch.matches(index.textFor(e), ['newscan']), isTrue);
    });
    test('clear() rebuilds everything', () {
      final index = ExpenseSearchIndex();
      final a = exp(id: 'a', vendor: 'First');
      index.textFor(a);
      index.clear();
      expect(index.textFor(exp(id: 'a', vendor: 'Second')).contains('second'), isTrue);
    });
  });

  group('speed', () {
    test('5,000 expenses: building the text once and then searching is quick', () {
      final list = List.generate(
          5000,
          (i) => exp(
              id: 'id$i',
              number: 'EXP${i.toString().padLeft(6, '0')}',
              date: '2026-0${1 + i % 9}-${10 + i % 18}',
              account: ['Fuel Charges', 'Rent expenses', 'Travel Expenses'][i % 3],
              vendor: 'Vendor $i',
              amount: 100.0 + i,
              total: 100.0 + i,
              notes: 'note number $i for the month'));
      final index = ExpenseSearchIndex();
      final sw = Stopwatch()..start();
      for (final e in list) {
        index.textFor(e);
      }
      final build = sw.elapsedMilliseconds;
      sw.reset();
      var found = 0;
      for (final q in ['fuel', 'vendor 4999', 'rent oct', '1,234', 'exp004000', 'zzz']) {
        final words = ExpenseSearch.tokens(q);
        found += list.where((e) => ExpenseSearch.matches(index.textFor(e), words)).length;
      }
      final search = sw.elapsedMilliseconds;
      // ignore: avoid_print
      print('build ${build} ms for 5,000 expenses; 6 searches ${search} ms (found $found)');
      expect(build, lessThan(2000));
      expect(search, lessThan(1000));
      expect(found, greaterThan(0));
    });
  });

  group('STRICT: the exact words, inside one column that the table shows', () {
    final office = exp(id: 'o', number: 'EXP000001', account: 'Office Expenses', vendor: 'Prem Nandan', amount: 600, tax: 0, total: 600);
    final puja = exp(id: 'p', number: 'EXP000002', account: 'Puja Expenses', vendor: 'Keerti Patil', amount: 250, tax: 0, total: 250, notes: 'Pooja oil office expenses');

    test('"office expenses" finds the Office Expenses account and NOT Puja Expenses that only mention it in a note', () {
      expect(strict(office, 'office expenses'), isTrue);
      expect(strict(puja, 'office expenses'), isFalse);
      // loose search still finds both
      expect(hit(puja, 'office expenses'), isTrue);
    });

    test('the words must be together in one column (Prem + Office are in two different columns)', () {
      expect(strict(office, 'prem office'), isFalse);
      expect(hit(office, 'prem office'), isTrue); // loose
      expect(strict(office, 'prem nandan'), isTrue);
      expect(strict(office, 'prem na'), isTrue); // typing as you go
    });

    test('a phrase starts at the start of a word: "off" finds Office, "ice" does not', () {
      expect(strict(office, 'off'), isTrue);
      expect(strict(office, 'expenses'), isTrue);
      expect(strict(office, 'ice'), isFalse);
      expect(hit(office, 'ice'), isTrue); // loose
    });

    test('capital letters and extra spaces do not matter', () {
      expect(strict(office, '  OFFICE    expenses '), isTrue);
    });

    test('notes, tags, item lines and file names are not searched in strict, only in loose', () {
      final e = exp(notes: 'diesel for the truck', tags: ['Urgent'], proofs: [proof('scan_a.jpg')], items: [ItemizedExpenseData(expenseAccount: 'Fuel', amount: 5, description: 'ten litres')]);
      for (final q in ['diesel', 'urgent', 'scan_a', 'ten litres']) {
        expect(strict(e, q), isFalse, reason: q);
        expect(hit(e, q), isTrue, reason: q);
      }
    });

    test('expense number, invoice number and paid-through are searched', () {
      final e = exp(number: 'EXP000011', invoice: 'VND-001', paidThrough: 'IDFC First Bank');
      expect(strict(e, 'exp000011'), isTrue);
      expect(strict(e, 'vnd-001'), isTrue);
      expect(strict(e, 'idfc first'), isTrue);
      expect(strict(e, 'hdfc'), isFalse);
    });

    test('dates in the usual ways', () {
      final e = exp(date: '2026-09-05');
      for (final q in ['2026-09-05', '2026-09', '05 sep 2026', '05/09/2026', '05-09-2026', 'september', 'sep 2026', 'september 2026']) {
        expect(strict(e, q), isTrue, reason: q);
      }
      expect(strict(e, 'oct'), isFalse);
    });
  });

  group('STRICT: a number is the WHOLE number', () {
    test('560 finds 560.00 but never 78560 (loose still finds both)', () {
      final a = exp(id: 'a', number: 'EXP000100', amount: 560, tax: 0, total: 560);
      final b = exp(id: 'b', number: 'EXP000101', amount: 78560, tax: 0, total: 78560);
      expect(strict(a, '560'), isTrue);
      expect(strict(a, '560.00'), isTrue);
      expect(strict(b, '560'), isFalse);
      expect(hit(b, '560'), isTrue);
    });

    test('commas and the rupee mark are ignored: 1,000  ₹1000  rs 1,000', () {
      final e = exp(amount: 1000, tax: 0, total: 1000);
      for (final q in ['1000', '1,000', '₹1,000', '₹ 1000', 'rs 1,000', '1000.0', '1000.00']) {
        expect(strict(e, q), isTrue, reason: q);
      }
      expect(strict(e, '10'), isFalse);
      expect(strict(e, '100'), isFalse);
      expect(strict(e, '10000'), isFalse);
    });

    test('tax shown as -180.00 is found by 180 or -180, and the billable amount too', () {
      final e = exp(amount: 1000, tax: -180, total: 820, billable: true, billableAmount: 1150.5);
      expect(strict(e, '180'), isTrue);
      expect(strict(e, '-180'), isTrue);
      expect(strict(e, '820'), isTrue);
      expect(strict(e, '1150.50'), isTrue);
      expect(strict(e, '1150.5'), isTrue);
      expect(strict(e, '82'), isFalse);
    });

    test('the number part of an expense or invoice number matches whole, leading zeros ignored', () {
      final e = exp(number: 'EXP002161', invoice: 'Ref-00560', amount: 600, tax: 0, total: 600);
      expect(strict(e, '2161'), isTrue);
      expect(strict(e, '560'), isTrue);
      expect(strict(e, '216'), isFalse);
      expect(strict(e, '61'), isFalse);
      expect(strict(e, '56'), isFalse);
    });

    test('a four-digit number can be the year; shorter ones are not dates', () {
      final e = exp(date: '2026-09-05', amount: 600, tax: 0, total: 600);
      expect(strict(e, '2026'), isTrue);
      expect(strict(e, '2025'), isFalse);
      expect(strict(e, '20'), isFalse);
      expect(strict(e, '5'), isFalse);
    });

    test('a number does not fall back to matching inside text', () {
      final e = exp(number: 'EXP000001', vendor: 'Gate 560 Transport', amount: 100, tax: 0, total: 100);
      expect(strict(e, '560'), isFalse); // the vendor name is text, not an amount
      expect(strict(e, 'gate 560'), isTrue); // typed as a phrase it is found
    });

    test('nothing typed means everything matches', () {
      expect(strict(exp(), ''), isTrue);
      expect(strict(exp(), '   '), isTrue);
    });
  });

  group('loose search ignores a lone currency mark', () {
    test('"rs 1,000" works because rs is not a word to look for', () {
      expect(ExpenseSearch.tokens('rs 1,000'), ['1,000']);
      expect(ExpenseSearch.tokens('₹ 500'), ['500']);
      expect(hit(exp(amount: 1000, tax: 0, total: 1000, paidThrough: 'Cash'), 'rs 1,000'), isTrue);
    });
  });

  group('the All Accounts dropdown', () {
    test('lists only the accounts really used, with counts, by name', () {
      final list = [
        exp(id: '1', account: 'Transportation Charges'),
        exp(id: '2', account: 'Office Expenses'),
        exp(id: '3', account: 'Transportation Charges'),
        exp(id: '4', account: 'puja Expenses'),
        exp(id: '5', account: ''),
        exp(id: '6', account: 'Office Expenses'),
        exp(id: '7', account: 'Transportation Charges'),
      ];
      final o = ExpenseSearch.accountOptions(list);
      expect(o.map((x) => '${x.name} (${x.count})').toList(), ['Office Expenses (2)', 'puja Expenses (1)', 'Transportation Charges (3)']);
    });
    test('no expenses means no accounts', () {
      expect(ExpenseSearch.accountOptions(const []), isEmpty);
    });
    test('the counts add up to the expenses that have an account', () {
      final list = List.generate(50, (i) => exp(id: 'x$i', account: 'A${i % 7}'));
      expect(ExpenseSearch.accountOptions(list).fold<int>(0, (s, o) => s + o.count), 50);
    });
  });

  group('the saved strict text stays correct when a row changes', () {
    test('invalidate / clear drop both kinds of saved text', () {
      final index = ExpenseSearchIndex();
      final e = exp(id: 'z', vendor: 'First Vendor');
      expect(ExpenseSearch.matchesStrict(index.strictFor(e), 'first'), isTrue);
      index.invalidate('z');
      expect(ExpenseSearch.matchesStrict(index.strictFor(exp(id: 'z', vendor: 'Second Vendor')), 'second'), isTrue);
      index.clear();
      expect(ExpenseSearch.matches(index.textFor(exp(id: 'z', vendor: 'Third')), ['third']), isTrue);
    });
  });

  group('highlight: only the text the search found is coloured', () {
    List<List<int>> hr(String text, String q, {bool strict = true, FieldKind kind = FieldKind.text, String? rawDate}) =>
        ExpenseSearch.highlightRanges(text, q, strict: strict, kind: kind, rawDate: rawDate);

    test('strict phrase: only the words typed, at a word start', () {
      expect(hr('Office Expenses', 'office exp'), [[0, 10]]);
      expect(hr('Office Expenses', 'ice'), isEmpty);
      expect(hr('Puja Expenses', 'office expenses'), isEmpty);
    });

    test('strict amount: the whole number is coloured, never part of a bigger one', () {
      expect(hr('₹450.00', '450', kind: FieldKind.money), [[1, 7]]);
      expect(hr('₹10000.00', '450', kind: FieldKind.money), isEmpty);
      expect(hr('₹1000.00', '1,000', kind: FieldKind.money), [[1, 8]]);
      expect(hr('₹-180.00', '180', kind: FieldKind.money), [[2, 8]]);
    });

    test('strict number in an expense / invoice number: the digits that equal it', () {
      expect(hr('EXP000450', '450', kind: FieldKind.serial), [[3, 9]]);
      expect(hr('EXP002450', '450', kind: FieldKind.serial), isEmpty);
      expect(hr('Ref-00450', '450', kind: FieldKind.serial), [[4, 9]]);
    });

    test('strict date: the year for a 4-digit number, the whole date for other forms', () {
      expect(hr('05/09/2026', '2026', kind: FieldKind.date, rawDate: '2026-09-05'), [[6, 10]]);
      expect(hr('05/09/2026', '20', kind: FieldKind.date, rawDate: '2026-09-05'), isEmpty);
      expect(hr('05/09/2026', 'sep 2026', kind: FieldKind.date, rawDate: '2026-09-05'), [[0, 10]]);
      expect(hr('05/09/2026', '05/09', kind: FieldKind.date, rawDate: '2026-09-05'), [[0, 5]]);
    });

    test('loose: every typed word, anywhere, merged when they touch', () {
      expect(hr('Prem Nandan', 'prem nan', strict: false), [[0, 4], [5, 8]]);
      expect(hr('₹78560.00', '560', strict: false, kind: FieldKind.money), [[3, 6]]);
      expect(hr('Office Expenses', 'off office', strict: false), [[0, 6]]);
    });

    test('nothing typed colours nothing', () {
      expect(hr('Office', ''), isEmpty);
      expect(hr('Office', '   ', strict: false), isEmpty);
    });
  });
}
