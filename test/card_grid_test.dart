// Card grids used to size rows with `childAspectRatio`, which ties a cell's
// height to the viewport *width*: the same card that fitted on a wide window
// was squeezed on a narrow one and its content overflowed the bottom. The
// app also lets readers change text size, which no ratio can anticipate.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:edumate_pro/widgets/common.dart';

/// Same shape as the admin overview's stat card: an icon chip, a big number
/// and a label.
///
/// [resilient] is the card as it is now — the number shrinks rather than
/// overflows. Passing false gives the original rigid shape, which is what
/// isolates the grid's own contribution: with a height derived from an
/// aspect ratio it is squeezed out of the bottom, with a real row height it
/// is not.
Widget _statCard({bool resilient = true}) => Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              child: const Icon(Icons.child_care_outlined, size: 18),
            ),
            const SizedBox(height: 8),
            if (resilient)
              const Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text('1234',
                      maxLines: 1,
                      style: TextStyle(
                          fontSize: 26, fontWeight: FontWeight.w800)),
                ),
              )
            else
              const Text('1234',
                  style:
                      TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
            if (resilient)
              const Flexible(
                child: Text('Learners enrolled',
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              )
            else
              const Text('Learners enrolled', maxLines: 1),
          ],
        ),
      ),
    );

Future<void> _pumpGrid(
  WidgetTester tester, {
  required Size surface,
  required double textScale,
  required int columns,
  bool resilient = true,
  double rowHeight = 140,
  double sidebar = 0,
}) async {
  await tester.binding.setSurfaceSize(surface);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        size: surface,
        textScaler: TextScaler.linear(textScale),
      ),
      child: Scaffold(
        body: Padding(
          // The admin overview sits beside a fixed-width sidebar, so the
          // grid never gets the whole window. Leaving that out is what let
          // an earlier version of this test pass while the real screen
          // overflowed.
          padding: EdgeInsets.only(left: sidebar),
          child: SingleChildScrollView(
          child: CardGrid(
            columns: columns,
            rowHeight: rowHeight,
            children: List.generate(
                4, (_) => _statCard(resilient: resilient)),
          ),
        ),
        ),
      ),
    ),
  ));
  await tester.pump();
}

void main() {
  // The exact reported geometry: a 1100px window with the 248px sidebar,
  // four columns, and a card that does not shrink to fit. The cell lands at
  // ~186px wide, where the card's content needs 135px of height.
  testWidgets('a rigid card fits beside the sidebar', (tester) async {
    await _pumpGrid(tester,
        surface: const Size(1100, 800),
        textScale: 1.0,
        columns: 4,
        sidebar: 248,
        resilient: false);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the row is tall enough for the card to render at full size',
      (tester) async {
    await _pumpGrid(tester,
        surface: const Size(1100, 800),
        textScale: 1.0,
        columns: 4,
        sidebar: 248,
        resilient: false);
    // 135px of content: a shorter row would shrink the number instead.
    expect(tester.getSize(find.byType(Card).first).height,
        greaterThanOrEqualTo(135));
  });

  // The reported failure: a narrow desktop window, four columns, a card
  // that does not shrink to fit. A real row height has to be enough on its
  // own — the card's own resilience is a second line of defence, not the
  // reason this works.
  testWidgets('a rigid card still fits a narrow four-column layout',
      (tester) async {
    await _pumpGrid(tester,
        surface: const Size(820, 700),
        textScale: 1.0,
        columns: 4,
        resilient: false);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a rigid card fits across widths', (tester) async {
    for (final (width, columns) in const [
      (360.0, 2),
      (600.0, 2),
      (820.0, 4),
      (1600.0, 4),
    ]) {
      await _pumpGrid(tester,
          surface: Size(width, 800),
          textScale: 1.0,
          columns: columns,
          resilient: false);
      expect(tester.takeException(), isNull,
          reason: 'overflowed at ${width}px with $columns columns');
    }
  });

  testWidgets('stat cards fit across widths and column counts',
      (tester) async {
    for (final (width, columns) in const [
      (360.0, 2),
      (600.0, 2),
      (820.0, 4),
      (1100.0, 4),
      (1600.0, 4),
    ]) {
      await _pumpGrid(tester,
          surface: Size(width, 800), textScale: 1.0, columns: columns);
      expect(tester.takeException(), isNull,
          reason: 'overflowed at ${width}px with $columns columns');
    }
  });

  testWidgets('stat cards fit when the reader enlarges text',
      (tester) async {
    for (final scale in const [1.0, 1.3, 1.6, 2.0]) {
      await _pumpGrid(tester,
          surface: const Size(820, 900), textScale: scale, columns: 4);
      expect(tester.takeException(), isNull,
          reason: 'overflowed at text scale $scale');
    }
  });

  testWidgets('row height grows with text size but stays bounded',
      (tester) async {
    Future<double> heightAt(double scale) async {
      await _pumpGrid(tester,
          surface: const Size(1100, 900), textScale: scale, columns: 4);
      return tester.getSize(find.byType(Card).first).height;
    }

    final normal = await heightAt(1.0);
    final large = await heightAt(1.5);
    final huge = await heightAt(3.0);

    expect(large, greaterThan(normal));
    // Clamped, so a card never turns into a page.
    expect(huge, lessThanOrEqualTo(140 * 1.8 + 0.01));
  });
}
