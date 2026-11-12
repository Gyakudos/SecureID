import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:secure_id/ui/widgets/pattern_pad.dart';
import 'package:secure_id/ui/widgets/pin_pad.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Center(child: child)),
      ),
    );
  }

  testWidgets('reports a complete six-digit PIN', (tester) async {
    String? entered;
    await pump(tester, PinPad(onCompleted: (value) => entered = value));

    for (final digit in ['1', '2', '3', '4', '5', '6']) {
      await tester.tap(find.text(digit));
      await tester.pump();
    }

    expect(entered, '123456');
  });

  testWidgets('backspace removes the last digit', (tester) async {
    String? entered;
    await pump(tester, PinPad(onCompleted: (value) => entered = value));

    for (final digit in ['1', '2', '3', '4']) {
      await tester.tap(find.text(digit));
      await tester.pump();
    }
    await tester.tap(find.byIcon(Icons.backspace_outlined));
    await tester.pump();
    for (final digit in ['4', '5', '6']) {
      await tester.tap(find.text(digit));
      await tester.pump();
    }

    expect(entered, '123456');
  });

  testWidgets('ignores input while disabled', (tester) async {
    String? entered;
    await pump(
      tester,
      PinPad(enabled: false, onCompleted: (value) => entered = value),
    );

    for (final digit in ['1', '2', '3', '4', '5', '6']) {
      await tester.tap(find.text(digit));
      await tester.pump();
    }

    expect(entered, isNull);
  });

  testWidgets('reports a drawn pattern', (tester) async {
    List<int>? entered;
    await pump(
      tester,
      PatternPad(size: 280, onCompleted: (value) => entered = value),
    );

    const pad = 44.8;
    const step = 95.2;
    final topLeft = tester.getTopLeft(find.byType(PatternPad));
    Offset center(int index) =>
        topLeft + Offset(pad + (index % 3) * step, pad + (index ~/ 3) * step);

    final gesture = await tester.startGesture(center(0));
    await gesture.moveTo(center(0) + const Offset(2, 0));
    await tester.pump();
    await gesture.moveTo(center(1));
    await tester.pump();
    await gesture.moveTo(center(2));
    await tester.pump();
    await gesture.moveTo(center(5));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(entered, [0, 1, 2, 5]);
  });

  testWidgets('ignores patterns with fewer than four dots', (tester) async {
    List<int>? entered;
    await pump(
      tester,
      PatternPad(size: 280, onCompleted: (value) => entered = value),
    );

    const pad = 44.8;
    const step = 95.2;
    final topLeft = tester.getTopLeft(find.byType(PatternPad));
    Offset center(int index) =>
        topLeft + Offset(pad + (index % 3) * step, pad + (index ~/ 3) * step);

    final gesture = await tester.startGesture(center(0));
    await gesture.moveTo(center(0) + const Offset(2, 0));
    await tester.pump();
    await gesture.moveTo(center(1));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(entered, isNull);
  });

  testWidgets('draws a vertical stroke inside a scroll view', (tester) async {
    List<int>? entered;
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            controller: scrollController,
            child: Column(
              children: [
                PatternPad(size: 280, onCompleted: (value) => entered = value),
                const SizedBox(height: 1200),
              ],
            ),
          ),
        ),
      ),
    );

    const pad = 44.8;
    const step = 95.2;
    final topLeft = tester.getTopLeft(find.byType(PatternPad));
    Offset center(int index) =>
        topLeft + Offset(pad + (index % 3) * step, pad + (index ~/ 3) * step);

    // A single vertical drag used to scroll the page instead of drawing.
    final gesture = await tester.startGesture(center(0));
    await gesture.moveTo(center(3));
    await tester.pump();
    await gesture.moveTo(center(6));
    await tester.pump();
    await gesture.moveTo(center(7));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(entered, [0, 3, 6, 7]);
    expect(scrollController.offset, 0);
  });

  testWidgets('adds dots skipped by a fast stroke', (tester) async {
    List<int>? entered;
    await pump(
      tester,
      PatternPad(size: 280, onCompleted: (value) => entered = value),
    );

    const pad = 44.8;
    const step = 95.2;
    final topLeft = tester.getTopLeft(find.byType(PatternPad));
    Offset center(int index) =>
        topLeft + Offset(pad + (index % 3) * step, pad + (index ~/ 3) * step);

    // One move from 0 to 2 passes over 1, and one move from 2 to 8 passes over
    // 5. Both intermediate dots must be recorded.
    final gesture = await tester.startGesture(center(0));
    await gesture.moveTo(center(2));
    await tester.pump();
    await gesture.moveTo(center(8));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(entered, [0, 1, 2, 5, 8]);
  });
}
