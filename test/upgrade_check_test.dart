// ignore_for_file: depend_on_referenced_packages
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
  setUp(() async {
    SharedPreferences.setMockInitialValues({'disclaimer_shown': true});
  });

  http.Client createMockClient({String newVersion = '1.0.0'}) {
    return MockClient((request) async {
      final data = {
        'resultCount': 1,
        'results': [
          {
            'version': newVersion,
            'bundleId': 'com.bookmarc.meldcalculator',
            'releaseNotes': 'New OPTN data updates and improvements',
            'trackViewUrl': 'https://apps.apple.com/app/id123',
          }
        ]
      };
      return http.Response(jsonEncode(data), 200);
    });
  }

  testWidgets('UpgradeAlert is present in MyApp widget hierarchy', (WidgetTester tester) async {
    final testUpgrader = Upgrader(
      client: createMockClient(newVersion: '1.0.0'),
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

    final upgradeAlertFinder = find.byType(UpgradeAlert);
    expect(upgradeAlertFinder, findsOneWidget);

    final UpgradeAlert upgradeAlert = tester.widget(upgradeAlertFinder);
    expect(upgradeAlert.barrierDismissible, isTrue,
        reason: 'Alert should be dismissible by tapping outside to encourage rather than require updates');
    expect(upgradeAlert.showLater, isTrue,
        reason: 'Should have Later button so the user is encouraged but not forced to update');
    expect(upgradeAlert.showIgnore, isTrue,
        reason: 'Should have Ignore button allowing the user to skip the version');
  });

  testWidgets('Upgrade prompt displays update and later actions when newer version exists', (WidgetTester tester) async {
    final testUpgrader = Upgrader(
      client: createMockClient(newVersion: '2.0.0'),
      upgraderOS: MockUpgraderOS(ios: true),
    )
      ..installPackageInfo(
        packageInfo: PackageInfo(
          appName: 'MELD 3.0 Calc',
          packageName: 'com.bookmarc.meldcalculator',
          version: '1.0.0',
          buildNumber: '1',
        ),
      )
      ..initialize();

    await tester.pumpAndSettle();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UpgradeAlert(
            upgrader: testUpgrader,
            barrierDismissible: true,
            showLater: true,
            showIgnore: true,
            child: const Center(child: Text('MELD Calculator Content')),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify update prompt dialog is displayed encouraging update
    expect(find.text('Update App?'), findsOneWidget);
    expect(find.text('UPDATE NOW'), findsOneWidget);
    expect(find.text('LATER'), findsOneWidget);
    expect(find.text('IGNORE'), findsOneWidget);

    // Tap LATER to dismiss the prompt without updating
    await tester.tap(find.text('LATER'));
    await tester.pumpAndSettle();

    // Verify dialog is dismissed and underlying app content is fully accessible without requiring update
    expect(find.text('Update App?'), findsNothing);
    expect(find.text('MELD Calculator Content'), findsOneWidget);
  });
}
