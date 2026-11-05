import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meldcalc/services/mmat_data_service.dart';
import 'package:meldcalc/views/mmat_heatmap_view.dart';

void main() {
  testWidgets('MmatHeatmapView initializes and renders controls', (WidgetTester tester) async {
    await tester.runAsync(() async {
      await MmatDataService.instance.loadHospitals();
    });

    await tester.pumpWidget(const MaterialApp(home: MmatHeatmapView()));
    await tester.pump();

    // Verify app bar title
    expect(find.text('Regional MMaT Heatmap'), findsOneWidget);

    // Verify search and info action icons
    expect(find.byIcon(Icons.search), findsOneWidget);
    expect(find.byIcon(Icons.info_outline), findsOneWidget);
  });
}
