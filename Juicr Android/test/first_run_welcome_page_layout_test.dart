import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juicr/src/first_run_welcome_page.dart';

void main() {
  test('acknowledgement direction follows rendered column count', () {
    expect(
      firstRunAcknowledgementTargetIndex(
        index: 0,
        direction: TraversalDirection.down,
        columns: 1,
        itemCount: 5,
      ),
      1,
    );
    expect(
      firstRunAcknowledgementTargetIndex(
        index: 0,
        direction: TraversalDirection.down,
        columns: 2,
        itemCount: 5,
      ),
      2,
    );
  });

  testWidgets('welcome acknowledgements fit narrow screens with large text',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(2)),
          child: FirstRunWelcomePage(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Welcome to Juicr'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(find.byType(Checkbox), findsNWidgets(5));
    expect(tester.takeException(), isNull);

    await tester.drag(find.byType(ListView), const Offset(0, -900));
    await tester.pumpAndSettle();

    expect(find.text('Set up add-ons'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
