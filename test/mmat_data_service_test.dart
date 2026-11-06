import 'package:flutter_test/flutter_test.dart';
import 'package:meldcalc/services/mmat_data_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('MmatDataService loads and parses mmat_data.csv with coordinates and manifest', () async {
    final service = MmatDataService.instance;
    final hospitals = await service.loadHospitals();

    expect(hospitals.isNotEmpty, true);
    expect(hospitals.length >= 5000, true);

    // Verify first hospital (Providence Alaska Medical Center)
    final first = hospitals.first;
    expect(first.state, 'AK');
    expect(first.city, 'Anchorage');
    expect(first.code, '020001-NMB');
    expect(first.medianMeld >= 6 && first.medianMeld <= 40, true);
    expect(first.latitude > 60.0, true);
    expect(first.longitude < -140.0, true);

    // Verify dynamic cohort getters
    expect(service.cohortBeginDate.isNotEmpty, true);
    expect(service.cohortEndDate.isNotEmpty, true);
    expect(service.cohortYearRange.contains('–'), true);
    expect(service.activeCohortVersion.isNotEmpty, true);

    // Verify groups
    final groups = await service.loadLocationGroups();
    expect(groups.isNotEmpty, true);

    // Verify stats
    final stats = service.getScoreStatistics(hospitals);
    expect(stats.min >= 6, true);
    expect(stats.max <= 40, true);
    expect(stats.average > 20, true);
  });

  test('isVersionNewer handles semantic and cohort version comparisons accurately', () {
    // Two-digit vs single-digit month (lexicographical comparison would fail this)
    expect(MmatDataService.isVersionNewer('2025.10', '2025.9'), isTrue);
    expect(MmatDataService.isVersionNewer('2025.9', '2025.10'), isFalse);

    // Standard semver
    expect(MmatDataService.isVersionNewer('3.0.2', '3.0.1'), isTrue);
    expect(MmatDataService.isVersionNewer('3.1.0', '3.0.1'), isTrue);
    expect(MmatDataService.isVersionNewer('4.0.0', '3.9.9'), isTrue);
    expect(MmatDataService.isVersionNewer('3.0.1', '3.0.1'), isFalse);
    expect(MmatDataService.isVersionNewer('2.9.0', '3.0.1'), isFalse);

    // With prefixes and build metadata
    expect(MmatDataService.isVersionNewer('v3.0.2', '3.0.1'), isTrue);
    expect(MmatDataService.isVersionNewer('3.0.1+2', '3.0.1+1'), isTrue);
  });
}
