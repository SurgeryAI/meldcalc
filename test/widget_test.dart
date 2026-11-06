// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility that Flutter provides. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:upgrader/upgrader.dart';
import 'package:meldcalc/main.dart';

void main() {
  testWidgets('App starts and shows title and MMaT benchmark', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({'disclaimer_shown': true});

    final testUpgrader = Upgrader(
      client: MockClient((_) async => http.Response(jsonEncode({'resultCount': 0, 'results': []}), 200)),
      upgraderOS: MockUpgraderOS(ios: true),
    )..installPackageInfo(
        packageInfo: PackageInfo(
          appName: 'MELD 3.0 Calc',
          packageName: 'com.bookmarc.meldcalculator',
          version: '1.0.0',
          buildNumber: '1',
        ),
      );

    // Build our app with testUpgrader and trigger frames
    await tester.pumpWidget(MyApp(upgrader: testUpgrader));
    await tester.pumpAndSettle();

    // Verify that the title is present.
    expect(find.text('MELD 3.0 Calculator'), findsOneWidget);

    // Verify score headers
    expect(find.text('Orig MELD'), findsOneWidget);
    expect(find.text('Na-MELD'), findsOneWidget);
    expect(find.text('MELD 3.0'), findsOneWidget);

    // Verify that survival card is present
    expect(find.textContaining('PREDICTED SURVIVAL'), findsOneWidget);

    // Verify that MMaT benchmark section is present
    expect(find.textContaining('MMaT'), findsWidgets);

    // Verify that lab field labels are present.
    expect(find.text('Cr mg/dL'), findsOneWidget);
    expect(find.text('TB mg/dL'), findsOneWidget);
  });

  testWidgets('Invalid input restores previous valid value on blur', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({'disclaimer_shown': true});

    final testUpgrader = Upgrader(
      client: MockClient((_) async => http.Response(jsonEncode({'resultCount': 0, 'results': []}), 200)),
      upgraderOS: MockUpgraderOS(ios: true),
    )..installPackageInfo(
        packageInfo: PackageInfo(
          appName: 'MELD 3.0 Calc',
          packageName: 'com.bookmarc.meldcalculator',
          version: '1.0.0',
          buildNumber: '1',
        ),
      );

    await tester.pumpWidget(MyApp(upgrader: testUpgrader));
    await tester.pumpAndSettle();

    // Find Creatinine field (initial value 1.0)
    final crFinder = find.widgetWithText(TextFormField, '1.0').first;
    expect(crFinder, findsOneWidget);

    // Tap to focus and enter invalid text "."
    await tester.tap(crFinder);
    await tester.pump();
    await tester.enterText(crFinder, '.');
    await tester.pump();

    // Unfocus by tapping outside the input fields inside the body
    await tester.tap(find.text('Orig MELD'));
    await tester.pumpAndSettle();

    // Field should safely restore the valid fallback value rather than staying "."
    expect(find.text('.'), findsNothing);
    expect(find.widgetWithText(TextFormField, '1.0'), findsWidgets);
  });

  testWidgets('MMaT benchmark card serves as streamlined link to heatmap without donor hospital entry', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({'disclaimer_shown': true});

    final testUpgrader = Upgrader(
      client: MockClient((_) async => http.Response(jsonEncode({'resultCount': 0, 'results': []}), 200)),
      upgraderOS: MockUpgraderOS(ios: true),
    )..installPackageInfo(
        packageInfo: PackageInfo(
          appName: 'MELD 3.0 Calc',
          packageName: 'com.bookmarc.meldcalculator',
          version: '1.0.0',
          buildNumber: '1',
        ),
      );

    await tester.pumpWidget(MyApp(upgrader: testUpgrader));
    await tester.pumpAndSettle();

    // Verify the card acts as a clean link to the MMaT Allocation Heatmap
    expect(find.text('MMaT Allocation Heatmap'), findsOneWidget);
    expect(find.text('Interactive'), findsOneWidget);

    // Verify there is no donor hospital entry or selection on the card
    expect(find.textContaining('Enter or select donor hospital'), findsNothing);
    expect(find.text('Donor Center MMaT'), findsNothing);
  });
}
