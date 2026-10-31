import 'package:abra_finance/features/billing/pages/invoices_list_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

// The real invoice list page, rendered at phone / tablet / desktop widths with
// no server (so it shows its error state; the top bar is always drawn).
void main() {
  dotenv.testLoad(fileInput: 'API_BASE_URL=http://127.0.0.1:1');

  for (final w in const [320.0, 360.0, 412.0, 768.0]) {
    testWidgets('invoice top bar fits at ${w.toInt()} px', (tester) async {
      tester.view.physicalSize = Size(w, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      final errors = <String>[];
      final old = FlutterError.onError;
      FlutterError.onError = (d) => errors.add(d.exceptionAsString().split('\n').first);
      await tester.pumpWidget(const MaterialApp(home: InvoicesListPage()));
      await tester.pump(const Duration(milliseconds: 300));
      FlutterError.onError = old;

      final field = find.byType(TextField);
      expect(field, findsWidgets);
      final width = tester.getSize(field.first).width;
      // ignore: avoid_print
      print('${w.toInt()}px: search box ${width.toStringAsFixed(0)} px wide, layout errors: ${errors.isEmpty ? 'none' : errors.take(3).join(' | ')}');
      expect(errors.where((e) => e.contains('overflowed')), isEmpty);
      // enough room to type and read (before: about 0-60 px on a phone)
      expect(width, greaterThanOrEqualTo(w < 700 ? w - 40 - 40 : 200));

      // let the page's own network time-out finish so no timer is left running
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 15));
    });
  }
}
