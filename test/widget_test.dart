// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility that Flutter provides. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:meldcalc/main.dart';

void main() {
  testWidgets('App starts and shows title', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(MyApp());

    // Verify that the title is present.
    expect(find.text('MELD 3.0 Calc'), findsOneWidget);

    // Verify that some lab values are present (default values).
    expect(find.text('Cr mg/dL'), findsOneWidget);
    expect(find.text('Bilirubin mg/dl'), findsOneWidget);
  });
}
