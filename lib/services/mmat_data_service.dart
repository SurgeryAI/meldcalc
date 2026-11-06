import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:csv/csv.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'mmat_file_cache.dart';

/// Metadata manifest describing an active OPTN MMaT dataset cohort.
class MmatManifest {
  final String cohortVersion;
  final String cohortBeginDate;
  final String cohortEndDate;
  final int donorHospitalCount;
  final String manifestUrl;
  final String csvUrl;
  final String coordinatesUrl;
  final String lastUpdated;

  const MmatManifest({
    required this.cohortVersion,
    required this.cohortBeginDate,
    required this.cohortEndDate,
    required this.donorHospitalCount,
    required this.manifestUrl,
    required this.csvUrl,
    required this.coordinatesUrl,
    required this.lastUpdated,
  });

  factory MmatManifest.fromJson(Map<String, dynamic> json) {
    return MmatManifest(
      cohortVersion: json['cohort_version']?.toString() ?? '2025.09',
      cohortBeginDate: json['cohort_begin_date']?.toString() ?? '09/01/2025',
      cohortEndDate: json['cohort_end_date']?.toString() ?? '08/31/2026',
      donorHospitalCount: (json['donor_hospital_count'] as num?)?.toInt() ?? 5887,
      manifestUrl: json['manifest_url']?.toString() ??
          'https://raw.githubusercontent.com/SurgeryAI/meldcalc/main/assets/mmat_manifest.json',
      csvUrl: json['csv_url']?.toString() ??
          'https://raw.githubusercontent.com/SurgeryAI/meldcalc/main/assets/mmat_data.csv',
      coordinatesUrl: json['coordinates_url']?.toString() ??
          'https://raw.githubusercontent.com/SurgeryAI/meldcalc/main/assets/mmat_coordinates.json',
      lastUpdated: json['last_updated']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'cohort_version': cohortVersion,
        'cohort_begin_date': cohortBeginDate,
        'cohort_end_date': cohortEndDate,
        'donor_hospital_count': donorHospitalCount,
        'manifest_url': manifestUrl,
        'csv_url': csvUrl,
        'coordinates_url': coordinatesUrl,
        'last_updated': lastUpdated,
      };
}

/// Result of an on-demand or background MMaT update check.
class MmatSyncResult {
  final bool success;
  final bool updated;
  final String message;
  final String activeCohortVersion;

  const MmatSyncResult({
    required this.success,
    required this.updated,
    required this.message,
    required this.activeCohortVersion,
  });
}

/// Represents a single OPTN donor hospital entry with MMaT score and coordinates.
class MmatHospital {
  final String state;
  final String city;
  final String code;
  final String name;
  final int medianMeld;
  final String cohortBeginDate;
  final String cohortEndDate;
  final double latitude;
  final double longitude;

  const MmatHospital({
    required this.state,
    required this.city,
    required this.code,
    required this.name,
    required this.medianMeld,
    required this.cohortBeginDate,
    required this.cohortEndDate,
    required this.latitude,
    required this.longitude,
  });

  /// 150 nautical miles in meters (OPTN policy standard allocation radius)
  static const double allocationRadiusMeters = 150.0 * 1852.0; // 277,800 meters

  @override
  String toString() => '$name ($code) in $city, $state: MMaT $medianMeld';
}

/// Aggregated regional location (e.g. for multiple hospitals in the same city/coordinate)
class MmatLocationGroup {
  final String city;
  final String state;
  final double latitude;
  final double longitude;
  final int representativeScore;
  final List<MmatHospital> hospitals;

  const MmatLocationGroup({
    required this.city,
    required this.state,
    required this.latitude,
    required this.longitude,
    required this.representativeScore,
    required this.hospitals,
  });
}

/// Service class responsible for parsing OPTN MMaT CSV data, resolving coordinates,
/// and syncing updated cohorts over-the-air from GitHub with offline fallback.
class MmatDataService {
  MmatDataService._();
  static final MmatDataService instance = MmatDataService._();

  static const String _defaultRemoteManifestUrl =
      'https://raw.githubusercontent.com/SurgeryAI/meldcalc/main/assets/mmat_manifest.json';
  static const String _prefSavedCenterCode = 'user_home_hospital_code';
  static const String _prefActiveVersionKey = 'mmat_active_cohort_version';

  static const String _cachedManifestFilename = 'mmat_manifest_cached.json';
  static const String _cachedCsvFilename = 'mmat_data_cached.csv';
  static const String _cachedCoordinatesFilename = 'mmat_coordinates_cached.json';

  List<MmatHospital>? _cachedHospitals;
  List<MmatLocationGroup>? _cachedGroups;
  MmatManifest? _activeManifest;
  bool _isLiveSynced = false;

  /// Active cohort begin date (e.g. "09/01/2025").
  String get cohortBeginDate {
    if (_activeManifest != null) return _activeManifest!.cohortBeginDate;
    if (_cachedHospitals != null && _cachedHospitals!.isNotEmpty) {
      return _cachedHospitals!.first.cohortBeginDate;
    }
    return '09/01/2025';
  }

  /// Active cohort end date (e.g. "08/31/2026").
  String get cohortEndDate {
    if (_activeManifest != null) return _activeManifest!.cohortEndDate;
    if (_cachedHospitals != null && _cachedHospitals!.isNotEmpty) {
      return _cachedHospitals!.first.cohortEndDate;
    }
    return '08/31/2026';
  }

  /// Active cohort year range string (e.g. "2025–2026").
  String get cohortYearRange {
    final b = cohortBeginDate.split('/').last;
    final e = cohortEndDate.split('/').last;
    return '$b–$e';
  }

  /// Total donor hospitals in the active cohort.
  int get donorHospitalCount =>
      _activeManifest?.donorHospitalCount ?? _cachedHospitals?.length ?? 5887;

  /// Active cohort version tag (e.g. "2025.09").
  String get activeCohortVersion => _activeManifest?.cohortVersion ?? '2025.09';

  /// Whether active data is running from an updated remote cache rather than bundled initial asset.
  bool get isLiveSynced => _isLiveSynced;

  /// Whether the dataset has already been loaded into memory.
  bool get isLoaded => _cachedHospitals != null && _cachedGroups != null;

  /// Pre-warms the MMaT dataset in the background so opening the map is instantaneous.
  Future<void> preWarm() async {
    if (isLoaded) return;
    try {
      await loadHospitals();
    } catch (_) {}
  }

  /// Loads and parses MMaT data from local cache or bundled assets.
  Future<List<MmatHospital>> loadHospitals({bool forceReload = false}) async {
    if (!forceReload && _cachedHospitals != null) {
      return _cachedHospitals!;
    }

    // 1. Load active manifest
    await _loadActiveManifest();

    // 2. Load coordinates JSON (prefer local cache over bundled asset)
    String? coordsJsonString = await readCachedFile(_cachedCoordinatesFilename);
    coordsJsonString ??= await rootBundle.loadString('assets/mmat_coordinates.json');
    final Map<String, dynamic> coordsMap = jsonDecode(coordsJsonString);

    // 3. Load CSV data (prefer local cache over bundled asset)
    String? csvString = await readCachedFile(_cachedCsvFilename);
    if (csvString != null && csvString.contains('donor_hospital_code')) {
      _isLiveSynced = true;
    } else {
      csvString = await rootBundle.loadString('assets/mmat_data.csv');
      _isLiveSynced = false;
    }

    // 4. Parse CSV rows
    final List<List<dynamic>> rows = Csv(dynamicTyping: false).decode(csvString);

    if (rows.isEmpty) {
      _cachedHospitals = [];
      _cachedGroups = [];
      return [];
    }

    final hospitals = <MmatHospital>[];
    final dataRows = rows.sublist(1); // skip header row

    for (final row in dataRows) {
      if (row.length < 5) continue;

      final state = row[0].toString().trim().toUpperCase();
      final city = row[1].toString().trim();
      final code = row[2].toString().trim();
      final name = row[3].toString().trim();
      final meld = int.tryParse(row[4].toString().trim()) ?? 0;
      final beginDate = row.length > 5 ? row[5].toString().trim() : cohortBeginDate;
      final endDate = row.length > 6 ? row[6].toString().trim() : cohortEndDate;

      if (state.isEmpty || city.isEmpty || meld == 0) continue;

      // Coordinate lookup key: "city|state" in lowercase
      final key = '${city.toLowerCase()}|$state';
      double lat = 39.8283; // default US geographic center fallback
      double lng = -98.5795;

      final coords = coordsMap[key];
      if (coords is List && coords.length >= 2) {
        lat = (coords[0] as num).toDouble();
        lng = (coords[1] as num).toDouble();
      }

      hospitals.add(MmatHospital(
        state: state,
        city: city,
        code: code,
        name: name,
        medianMeld: meld,
        cohortBeginDate: beginDate,
        cohortEndDate: endDate,
        latitude: lat,
        longitude: lng,
      ));
    }

    _cachedHospitals = hospitals;
    _buildGroups(hospitals);

    return hospitals;
  }

  Future<void> _loadActiveManifest() async {
    try {
      final cachedJson = await readCachedFile(_cachedManifestFilename);
      if (cachedJson != null && cachedJson.isNotEmpty) {
        _activeManifest = MmatManifest.fromJson(jsonDecode(cachedJson));
        return;
      }
    } catch (_) {}

    try {
      final bundledJson = await rootBundle.loadString('assets/mmat_manifest.json');
      _activeManifest = MmatManifest.fromJson(jsonDecode(bundledJson));
    } catch (_) {
      _activeManifest = const MmatManifest(
        cohortVersion: '2025.09',
        cohortBeginDate: '09/01/2025',
        cohortEndDate: '08/31/2026',
        donorHospitalCount: 5887,
        manifestUrl: _defaultRemoteManifestUrl,
        csvUrl: 'https://raw.githubusercontent.com/SurgeryAI/meldcalc/main/assets/mmat_data.csv',
        coordinatesUrl:
            'https://raw.githubusercontent.com/SurgeryAI/meldcalc/main/assets/mmat_coordinates.json',
        lastUpdated: '',
      );
    }
  }

  /// Checks the GitHub repository for updated OPTN MMaT dataset manifests.
  /// If a newer cohort is detected, downloads and caches the new CSV locally.
  Future<MmatSyncResult> checkForUpdates({
    bool force = false,
    String? customManifestUrl,
  }) async {
    final manifestUrl = customManifestUrl ?? _activeManifest?.manifestUrl ?? _defaultRemoteManifestUrl;
    final client = http.Client();

    try {
      final manifestUri = Uri.parse(manifestUrl);

      final manifestResp = await client.get(manifestUri).timeout(const Duration(seconds: 6));
      if (manifestResp.statusCode != 200) {
        return MmatSyncResult(
          success: false,
          updated: false,
          message: 'Unable to reach remote manifest (HTTP ${manifestResp.statusCode}).',
          activeCohortVersion: activeCohortVersion,
        );
      }

      final remoteManifest = MmatManifest.fromJson(jsonDecode(manifestResp.body));
      final bool isNewer = isVersionNewer(remoteManifest.cohortVersion, activeCohortVersion);

      if (!isNewer && !force) {
        return MmatSyncResult(
          success: true,
          updated: false,
          message: 'MMaT is already up to date ($cohortBeginDate – $cohortEndDate).',
          activeCohortVersion: activeCohortVersion,
        );
      }

      // Download updated CSV
      final csvResp = await client.get(Uri.parse(remoteManifest.csvUrl)).timeout(const Duration(seconds: 15));
      if (csvResp.statusCode != 200 || csvResp.body.isEmpty) {
        return MmatSyncResult(
          success: false,
          updated: false,
          message: 'Failed to download updated CSV from GitHub.',
          activeCohortVersion: activeCohortVersion,
        );
      }

      final newCsvString = csvResp.body;
      if (!newCsvString.contains('donor_hospital_code') || newCsvString.length < 50000) {
        return MmatSyncResult(
          success: false,
          updated: false,
          message: 'Downloaded CSV failed validation checks.',
          activeCohortVersion: activeCohortVersion,
        );
      }

      // Download updated coordinates if URL exists
      if (remoteManifest.coordinatesUrl.isNotEmpty) {
        try {
          final coordsResp = await client
              .get(Uri.parse(remoteManifest.coordinatesUrl))
              .timeout(const Duration(seconds: 10));
          if (coordsResp.statusCode == 200 && coordsResp.body.length > 1000) {
            await writeCachedFile(_cachedCoordinatesFilename, coordsResp.body);
          }
        } catch (_) {}
      }

      // Save CSV & Manifest locally
      await writeCachedFile(_cachedCsvFilename, newCsvString);
      await writeCachedFile(_cachedManifestFilename, jsonEncode(remoteManifest.toJson()));

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefActiveVersionKey, remoteManifest.cohortVersion);

      _activeManifest = remoteManifest;
      await loadHospitals(forceReload: true);

      return MmatSyncResult(
        success: true,
        updated: true,
        message: 'Updated to OPTN cohort ${remoteManifest.cohortBeginDate} – ${remoteManifest.cohortEndDate}',
        activeCohortVersion: remoteManifest.cohortVersion,
      );
    } catch (e) {
      return MmatSyncResult(
        success: false,
        updated: false,
        message: 'Sync error: $e',
        activeCohortVersion: activeCohortVersion,
      );
    } finally {
      client.close();
    }
  }

  static const String _prefLastSyncCheckTime = 'mmat_last_sync_check_time';

  /// Fire-and-forget background check. Runs at most once every 7 days in the background
  /// to avoid unnecessary network traffic and CPU work on app launch.
  Future<void> syncInBackground() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastCheckMs = prefs.getInt(_prefLastSyncCheckTime) ?? 0;
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      // Only check once a week in the background (MMaT changes semi-annually)
      if (nowMs - lastCheckMs < const Duration(days: 7).inMilliseconds) {
        return;
      }

      final res = await checkForUpdates();
      await prefs.setInt(_prefLastSyncCheckTime, nowMs);
      if (res.updated) {
        debugPrint('[MmatDataService] Background sync applied: ${res.message}');
      }
    } catch (e) {
      debugPrint('[MmatDataService] Background sync skipped: $e');
    }
  }

  /// Clears any cached downloaded data and reverts to bundled asset files.
  Future<void> clearLocalCache() async {
    await clearCachedFile(_cachedCsvFilename);
    await clearCachedFile(_cachedCoordinatesFilename);
    await clearCachedFile(_cachedManifestFilename);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefActiveVersionKey);
    _isLiveSynced = false;
    _activeManifest = null;
    await loadHospitals(forceReload: true);
  }

  /// Compares two version strings numerically (supports semantic versions, year.month, and build numbers).
  static bool isVersionNewer(String remote, String local) {
    if (remote == local) return false;
    final rParts = remote.replaceAll(RegExp(r'^[vV]'), '').split(RegExp(r'[\.\-\+]'));
    final lParts = local.replaceAll(RegExp(r'^[vV]'), '').split(RegExp(r'[\.\-\+]'));

    final maxLen = max(rParts.length, lParts.length);
    for (int i = 0; i < maxLen; i++) {
      final rStr = i < rParts.length ? rParts[i] : '0';
      final lStr = i < lParts.length ? lParts[i] : '0';

      final rNum = int.tryParse(rStr);
      final lNum = int.tryParse(lStr);

      if (rNum != null && lNum != null) {
        if (rNum > lNum) return true;
        if (rNum < lNum) return false;
      } else {
        final cmp = rStr.compareTo(lStr);
        if (cmp > 0) return true;
        if (cmp < 0) return false;
      }
    }
    return false;
  }

  void _buildGroups(List<MmatHospital> hospitals) {
    final map = <String, List<MmatHospital>>{};
    for (final h in hospitals) {
      final key = '${h.latitude.toStringAsFixed(3)},${h.longitude.toStringAsFixed(3)}';
      map.putIfAbsent(key, () => []).add(h);
    }

    final groups = <MmatLocationGroup>[];
    map.forEach((_, list) {
      if (list.isEmpty) return;
      final scores = list.map((e) => e.medianMeld).toList()..sort();
      final medianScore = scores[scores.length ~/ 2];
      final first = list.first;
      groups.add(MmatLocationGroup(
        city: first.city,
        state: first.state,
        latitude: first.latitude,
        longitude: first.longitude,
        representativeScore: medianScore,
        hospitals: list,
      ));
    });

    _cachedGroups = groups;
  }

  /// Returns geographically aggregated hospital groups for efficient map rendering.
  Future<List<MmatLocationGroup>> loadLocationGroups({bool forceReload = false}) async {
    if (!forceReload && _cachedGroups != null) {
      return _cachedGroups!;
    }
    await loadHospitals(forceReload: forceReload);
    return _cachedGroups ?? [];
  }

  /// Calculates min, max, and average MMaT scores across the dataset.
  ({int min, int max, double average}) getScoreStatistics(List<MmatHospital> hospitals) {
    if (hospitals.isEmpty) return (min: 0, max: 0, average: 0.0);
    int minScore = hospitals.first.medianMeld;
    int maxScore = hospitals.first.medianMeld;
    int total = 0;
    for (final h in hospitals) {
      if (h.medianMeld < minScore) minScore = h.medianMeld;
      if (h.medianMeld > maxScore) maxScore = h.medianMeld;
      total += h.medianMeld;
    }
    return (
      min: minScore,
      max: maxScore,
      average: total / hospitals.length,
    );
  }

  // ── User's Home Center Persistence ─────────────────────────────────────────

  /// Loads the clinician's preferred/home transplant center if previously saved.
  Future<MmatHospital?> getSavedCenter() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_prefSavedCenterCode);
    if (code == null || code.isEmpty) return null;
    return findHospitalByCode(code);
  }

  /// Saves or clears the clinician's preferred/home transplant center.
  Future<void> saveCenter(MmatHospital? hospital) async {
    final prefs = await SharedPreferences.getInstance();
    if (hospital == null) {
      await prefs.remove(_prefSavedCenterCode);
    } else {
      await prefs.setString(_prefSavedCenterCode, hospital.code);
    }
  }

  /// Finds a specific donor hospital by its OPTN code.
  Future<MmatHospital?> findHospitalByCode(String code) async {
    final list = await loadHospitals();
    final normalized = code.trim().toUpperCase();
    for (final h in list) {
      if (h.code.toUpperCase() == normalized) return h;
    }
    return null;
  }
}
