import 'package:abra_finance/features/billing/widgets/mobile_page_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<List<int>> _pump(WidgetTester t,
    {required int page, required int total, double width = 360}) async {
  t.view.physicalSize = Size(width, 700);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.resetPhysicalSize);
  final picked = <int>[];
  await t.pumpWidget(MaterialApp(
      home: Scaffold(
          body: MobilePageBar(
    currentPage: page,
    totalPages: total,
    summary: 'Showing 1–20 of 3196',
    onPage: picked.add,
  ))));
  return picked;
}

void main() {
  test('the five numbers follow the current page', () {
    expect(MobilePageBar.window(1, 160), [1, 2, 3, 4, 5]);
    expect(MobilePageBar.window(3, 160), [1, 2, 3, 4, 5]);
    expect(MobilePageBar.window(10, 160), [8, 9, 10, 11, 12]);
    expect(MobilePageBar.window(160, 160), [156, 157, 158, 159, 160]);
    expect(MobilePageBar.window(2, 3), [1, 2, 3]);
    expect(MobilePageBar.window(1, 1), [1]);
  });

  testWidgets('fits a 360 px phone with no layout error, says which page', (t) async {
    await _pump(t, page: 10, total: 160);
    expect(t.takeException(), isNull);
    expect(find.text('Showing 1–20 of 3196'), findsOneWidget);
    expect(find.text('Page 10 of 160'), findsOneWidget);
    expect(find.text('160'), findsOneWidget); // last page is reachable
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('tapping a number, next and previous change the page', (t) async {
    final picked = await _pump(t, page: 10, total: 160);
    await t.tap(find.text('11'));
    await t.tap(find.byIcon(Icons.chevron_right));
    await t.tap(find.byIcon(Icons.chevron_left));
    await t.ensureVisible(find.text('160'));
    await t.tap(find.text('160'));
    expect(picked, [11, 11, 9, 160]);
  });

  testWidgets('the current page cannot be tapped again; first page has no previous', (t) async {
    final picked = await _pump(t, page: 1, total: 160);
    await t.tap(find.text('1'));
    await t.tap(find.byIcon(Icons.chevron_left));
    expect(picked, isEmpty);
  });

  testWidgets('the dropdown jumps straight to any page', (t) async {
    final picked = await _pump(t, page: 10, total: 160);
    await t.tap(find.text('Page 10 of 160'));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(find.text('Page 120'), 300,
        scrollable: find.byType(Scrollable).last);
    await t.tap(find.text('Page 120'));
    await t.pumpAndSettle();
    expect(picked, [120]);
    expect(t.takeException(), isNull);
  });

  testWidgets('a short list shows all its numbers and fits the narrowest phone', (t) async {
    await _pump(t, page: 2, total: 3, width: 320);
    expect(t.takeException(), isNull);
    for (final n in ['1', '2', '3']) {
      expect(find.text(n), findsOneWidget);
    }
  });
}
