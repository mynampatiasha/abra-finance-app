// Tests for the expense-proof logic. They run on the same Dart engine the phone
// uses (where whole numbers such as 800 are real ints, not doubles), so they
// catch the kind of mistake that only shows up on a phone.
//
//   flutter test test/expense_proof_logic_test.dart

import 'dart:typed_data';

import 'package:abra_finance/core/services/expenses_service.dart';
import 'package:abra_finance/core/utils/file_mime.dart';
import 'package:abra_finance/features/billing/pages/expenses_list_page.dart' show ExpenseStats;
import 'package:abra_finance/features/billing/widgets/expense_proof_manager.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _proof(String name, {int size = 1000}) => {
      'filename': 'proof-$name.png',
      'originalName': name,
      'size': size, // an int, as the phone receives it
      'mimetype': 'image/png',
      'uploadedAt': '2026-10-16T05:00:00.000Z',
    };

Map<String, dynamic> _expense({Map<String, dynamic>? proofFile, List<Map<String, dynamic>>? proofFiles}) => {
      '_id': 'exp1',
      'date': '2026-10-10',
      'expenseAccount': 'Travel Expenses',
      'amount': 800, // whole numbers: ints on a phone
      'tax': 0,
      'total': 800,
      'paidThrough': 'Cash',
      'isBillable': false,
      'expenseNumber': 'EXP000005',
      if (proofFile != null) 'proofFile': proofFile,
      if (proofFiles != null) 'proofFiles': proofFiles,
    };

Uint8List _bytes(int n) => Uint8List(n);

void main() {
  expenseStatsTests();
  proofKindTests();
  mimeForDownloadTests();

  group('Expense proofs — reading the server data', () {
    test('an expense with no proof has an empty list and no first proof', () {
      final e = Expense.fromJson(_expense());
      expect(e.proofFiles, isEmpty);
      expect(e.proofFile, isNull);
    });

    test('an OLD expense (single proofFile) is read as a one-item list', () {
      final e = Expense.fromJson(_expense(proofFile: _proof('old receipt.png')));
      expect(e.proofFiles.length, 1);
      expect(e.proofFiles.first.originalName, 'old receipt.png');
      expect(e.proofFile!.originalName, 'old receipt.png');
    });

    test('the new proofFiles list is read in order and proofFile is the first', () {
      final e = Expense.fromJson(_expense(
        proofFile: _proof('a.png'),
        proofFiles: [_proof('a.png'), _proof('b.png'), _proof('c.pdf')],
      ));
      expect(e.proofFiles.map((p) => p.originalName), ['a.png', 'b.png', 'c.pdf']);
      expect(e.proofFile!.originalName, 'a.png');
    });

    test('when both exist the list wins (no duplicate of the first proof)', () {
      final e = Expense.fromJson(_expense(
        proofFile: _proof('a.png'),
        proofFiles: [_proof('a.png'), _proof('b.png')],
      ));
      expect(e.proofFiles.length, 2);
    });
  });

  group('Expense.setProofs — updating one row without reloading', () {
    test('replaces the list and keeps proofFile equal to the first', () {
      final e = Expense.fromJson(_expense(proofFile: _proof('a.png')));
      e.setProofs([
        ProofFile.fromJson(_proof('x.png')),
        ProofFile.fromJson(_proof('y.png')),
      ]);
      expect(e.proofFiles.length, 2);
      expect(e.proofFile!.originalName, 'x.png');
    });

    test('deleting the last proof clears both', () {
      final e = Expense.fromJson(_expense(proofFile: _proof('a.png')));
      e.setProofs([]);
      expect(e.proofFiles, isEmpty);
      expect(e.proofFile, isNull);
    });

    test('everything else on the expense is untouched', () {
      final e = Expense.fromJson(_expense(proofFile: _proof('a.png')));
      e.setProofs([ProofFile.fromJson(_proof('z.png'))]);
      expect(e.total, 800);
      expect(e.expenseAccount, 'Travel Expenses');
      expect(e.expenseNumber, 'EXP000005');
    });
  });

  group('ProofImageCache — each picture is downloaded once', () {
    setUp(() => ProofImageCache.instance.clear());

    test('a stored picture comes straight back', () {
      final b = _bytes(10);
      ProofImageCache.instance.put('u1', b);
      expect(identical(ProofImageCache.instance.peek('u1'), b), isTrue);
      expect(ProofImageCache.instance.peek('missing'), isNull);
    });

    test('keeps at most 24 pictures, dropping the oldest first', () {
      for (var i = 0; i < 30; i++) {
        ProofImageCache.instance.put('u$i', _bytes(10));
      }
      expect(ProofImageCache.instance.peek('u0'), isNull);
      expect(ProofImageCache.instance.peek('u5'), isNull);
      expect(ProofImageCache.instance.peek('u6'), isNotNull); // 30 - 24 = first kept
      expect(ProofImageCache.instance.peek('u29'), isNotNull);
    });

    test('a picture that was just used is the last to be dropped', () {
      for (var i = 0; i < 24; i++) {
        ProofImageCache.instance.put('u$i', _bytes(10));
      }
      ProofImageCache.instance.peek('u0'); // use the oldest
      ProofImageCache.instance.put('new', _bytes(10)); // forces one out
      expect(ProofImageCache.instance.peek('u0'), isNotNull);
      expect(ProofImageCache.instance.peek('u1'), isNull);
    });

    test('also stays under 40 MB in total', () {
      const nine = 9 * 1024 * 1024;
      for (var i = 0; i < 5; i++) {
        ProofImageCache.instance.put('big$i', _bytes(nine));
      }
      expect(ProofImageCache.instance.peek('big0'), isNull); // 45 MB > 40 MB → oldest out
      expect(ProofImageCache.instance.peek('big4'), isNotNull);
    });

    test('putting the same picture again replaces it (no double counting)', () {
      const nine = 9 * 1024 * 1024;
      for (var i = 0; i < 10; i++) {
        ProofImageCache.instance.put('same', _bytes(nine));
      }
      expect(ProofImageCache.instance.peek('same'), isNotNull);
      ProofImageCache.instance.put('other', _bytes(nine));
      expect(ProofImageCache.instance.peek('same'), isNotNull); // 18 MB, nothing evicted
    });

    test('a deleted proof is removed from memory', () {
      ProofImageCache.instance.put('u1', _bytes(10));
      ProofImageCache.instance.remove('u1');
      expect(ProofImageCache.instance.peek('u1'), isNull);
    });
  });
}

// The summary cards read these numbers. On the phone whole numbers arrive as
// ints; a strict double conversion threw there and the cards stayed at ₹0.00.
void expenseStatsTests() {
  group('ExpenseStats — numbers as the phone receives them', () {
    test('whole numbers (ints) are accepted — the old code threw here', () {
      final s = ExpenseStats.fromJson({
        'totalExpenses': 1000, // int
        'totalBillable': 0,
        'expenseCount': 3,
        'expensesByAccount': {'Travel': 800, 'Fuel': 200}, // int values
        'expensesByVendor': {'Man Power': 800},
      });
      expect(s.totalExpenses, 1000.0);
      expect(s.totalBillable, 0.0);
      expect(s.expenseCount, 3);
      expect(s.expensesByAccount['Travel'], 800.0);
      expect(s.expensesByVendor['Man Power'], 800.0);
    });

    test('decimals still work, and mixed ints / decimals together', () {
      final s = ExpenseStats.fromJson({
        'totalExpenses': 1234.5,
        'totalBillable': 10,
        'expenseCount': 2,
        'expensesByAccount': {'A': 1.5, 'B': 2},
        'expensesByVendor': {},
      });
      expect(s.totalExpenses, 1234.5);
      expect(s.totalBillable, 10.0);
      expect(s.expensesByAccount['A'], 1.5);
      expect(s.expensesByAccount['B'], 2.0);
    });

    test('missing / null / text values become 0 instead of failing', () {
      final s = ExpenseStats.fromJson({
        'totalExpenses': null,
        'totalBillable': '25.5',
        'expensesByAccount': null,
      });
      expect(s.totalExpenses, 0.0);
      expect(s.totalBillable, 25.5);
      expect(s.expenseCount, 0);
      expect(s.expensesByAccount, isEmpty);
      expect(s.expensesByVendor, isEmpty);
    });
  });
}

// Photos uploaded from the phone were stored as "application/octet-stream" and
// the app labelled them "PDF". The file name's extension now decides in that case.
void proofKindTests() {
  ProofFile pf(String name, String mime, {String disk = 'proof-1.bin'}) => ProofFile.fromJson({
        'filename': disk,
        'originalName': name,
        'size': 10,
        'mimetype': mime,
      });

  group('ProofFile image / PDF detection', () {
    test('phone photo stored as octet-stream is an IMAGE (was shown as PDF)', () {
      final p = pf('EXP000011_Proof-6_2026-10-15_1124.jpg', 'application/octet-stream');
      expect(p.isImage, isTrue);
      expect(p.isPdf, isFalse);
    });

    test('octet-stream with .jpeg / .png / .gif / .webp (any case) is an image', () {
      for (final n in ['a.jpeg', 'b.PNG', 'c.Gif', 'd.webp', 'e.JPG']) {
        expect(pf(n, 'application/octet-stream').isImage, isTrue, reason: n);
      }
    });

    test('octet-stream with .pdf is a PDF, not an image', () {
      final p = pf('Invoice.pdf', 'application/octet-stream');
      expect(p.isPdf, isTrue);
      expect(p.isImage, isFalse);
    });

    test('a clear type always wins over the extension', () {
      expect(pf('x.pdf', 'image/png').isImage, isTrue);
      expect(pf('x.pdf', 'image/png').isPdf, isFalse);
      expect(pf('x.jpg', 'application/pdf').isPdf, isTrue);
      expect(pf('x.jpg', 'application/pdf').isImage, isFalse);
    });

    test('falls back to the disk file name when the display name has no extension', () {
      expect(pf('receipt', 'application/octet-stream', disk: 'proof-9.jpg').isImage, isTrue);
      expect(pf('receipt', 'application/octet-stream', disk: 'proof-9.pdf').isPdf, isTrue);
    });

    test('unknown everything is neither image nor PDF', () {
      final p = pf('mystery', 'application/octet-stream');
      expect(p.isImage, isFalse);
      expect(p.isPdf, isFalse);
    });
  });
}

// A browser SAVES a file whose type is "unknown" instead of showing it, so a PDF
// proof must be opened as a PDF even when the server reports octet-stream.
void mimeForDownloadTests() {
  group('mimeForDownload — View opens the file instead of downloading it', () {
    test('unknown type + .pdf name -> application/pdf', () {
      expect(mimeForDownload('application/octet-stream', 'Budget_FY_2026-27.pdf'), 'application/pdf');
    });
    test('unknown type + picture names -> the right image type', () {
      expect(mimeForDownload('application/octet-stream', 'a.JPG'), 'image/jpeg');
      expect(mimeForDownload('application/octet-stream', 'b.jpeg'), 'image/jpeg');
      expect(mimeForDownload('application/octet-stream', 'c.png'), 'image/png');
      expect(mimeForDownload('application/octet-stream', 'd.webp'), 'image/webp');
    });
    test('a clear type from the server is always kept', () {
      expect(mimeForDownload('application/pdf', 'x.jpg'), 'application/pdf');
      expect(mimeForDownload('image/png; charset=binary', 'x.pdf'), 'image/png');
    });
    test('missing type is handled like unknown', () {
      expect(mimeForDownload(null, 'r.pdf'), 'application/pdf');
      expect(mimeForDownload('', 'r.png'), 'image/png');
    });
    test('unknown type and unknown extension stays unknown (no guessing)', () {
      expect(mimeForDownload('application/octet-stream', 'data.bin'), 'application/octet-stream');
      expect(mimeForDownload(null, 'noextension'), 'application/octet-stream');
    });
  });
}
