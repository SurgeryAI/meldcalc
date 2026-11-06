import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/mmat_data_service.dart';

/// Interactive geographic heatmap & radius overlay view of the USA
/// displaying Median MELD at Transplant (MMaT) scores based on the
/// OPTN 150-nautical-mile donor hospital calculation radius.
class MmatHeatmapView extends StatefulWidget {
  final int? patientScore;
  final String? initialHospitalCode;

  const MmatHeatmapView({
    super.key,
    this.patientScore,
    this.initialHospitalCode,
  });

  /// Temperature color scale: hotter colors represent higher MMaT scores
  static Color getScoreColor(int score) {
    if (score >= 34) {
      return const Color(0xFFC62828); // Crimson Red (34+)
    } else if (score >= 32) {
      return const Color(0xFFFF7043); // Coral / Orange (32-33)
    } else if (score == 31) {
      return const Color(0xFFFBC02D); // Gold / Yellow (31 National Median)
    } else if (score == 30) {
      return const Color(0xFF00897B); // Medical Teal (30)
    } else {
      return const Color(0xFF1976D2); // Cool Blue (<= 29)
    }
  }

  @override
  State<MmatHeatmapView> createState() => _MmatHeatmapViewState();
}

class _MmatHeatmapViewState extends State<MmatHeatmapView> {
  final MapController _mapController = MapController();
  final MmatDataService _service = MmatDataService.instance;

  // Google Maps tile configuration
  static const String _googleMapsApiKey =
      String.fromEnvironment('GOOGLE_MAPS_API_KEY', defaultValue: '');

  // Google Maps layer type: 'm' = Roadmap, 'p' = Terrain, 'y' = Hybrid (Satellite + labels)
  String _mapType = 'm';

  List<MmatHospital> _allHospitals = [];
  List<MmatLocationGroup> _allGroups = [];
  bool _isLoading = true;
  String? _errorMessage;

  // View toggles
  bool _showRadiuses = true;
  bool _showMarkers = false;
  int _scoreFilterMin = 0; // 0 = all
  bool _isLegendExpanded = true;

  // User's saved home transplant center code
  String? _savedCenterCode;

  // Selected item for bottom sheet / detail card
  MmatLocationGroup? _selectedGroup;

  // Search controller
  final TextEditingController _searchCtrl = TextEditingController();

  static const LatLng _usaCenter = LatLng(39.8283, -98.5795);
  static const double _initialZoom = 4.9; // ~1200-mile span across typical mobile viewport
  static const double _usaOverviewZoom = 4.2;
  static const int _nationalMedian = 31;

  LatLng _currentLocation = _usaCenter;
  bool _hasLocation = false;

  @override
  void initState() {
    super.initState();
    _loadData();
    _initLocation();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _initLocation() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedLat = prefs.getDouble('cached_user_lat');
      final cachedLng = prefs.getDouble('cached_user_lng');
      if (cachedLat != null && cachedLng != null && mounted) {
        setState(() {
          _currentLocation = LatLng(cachedLat, cachedLng);
          _hasLocation = true;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _centerOn1200Miles(_currentLocation);
        });
        return; // Fast path: cached location used immediately with zero network delay
      }

      // Query IP location service for current location only if not previously cached
      final client = http.Client();
      try {
        final res = await client
            .get(Uri.parse('http://ip-api.com/json'))
            .timeout(const Duration(milliseconds: 1200));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          if (data['status'] == 'success' && data['lat'] != null && data['lon'] != null) {
            final lat = (data['lat'] as num).toDouble();
            final lng = (data['lon'] as num).toDouble();
            await prefs.setDouble('cached_user_lat', lat);
            await prefs.setDouble('cached_user_lng', lng);
            if (mounted) {
              setState(() {
                _currentLocation = LatLng(lat, lng);
                _hasLocation = true;
              });
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _centerOn1200Miles(_currentLocation);
              });
            }
          }
        }
      } finally {
        client.close();
      }
    } catch (_) {
      // Fallback: center on default USA location showing 1200 miles
      if (!_hasLocation && mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _centerOn1200Miles(_usaCenter);
        });
      }
    }
  }

  void _centerOn1200Miles(LatLng center) {
    // 1200 miles span = 600 miles radius from center
    // 1 deg latitude ≈ 69.0 miles
    final dLat = 600.0 / 69.0;
    final cosLat = math.cos(center.latitude * math.pi / 180.0).abs();
    final dLng = 600.0 / (69.0 * (cosLat > 0.1 ? cosLat : 1.0));
    final bounds = LatLngBounds(
      LatLng(center.latitude - dLat, center.longitude - dLng),
      LatLng(center.latitude + dLat, center.longitude + dLng),
    );
    try {
      _mapController.fitCamera(CameraFit.bounds(
        bounds: bounds,
        padding: const EdgeInsets.all(16),
      ));
    } catch (_) {
      _mapController.move(center, _initialZoom);
    }
  }

  Future<void> _loadData() async {
    try {
      final hospitals = await _service.loadHospitals();
      final groups = await _service.loadLocationGroups();

      if (mounted) {
        setState(() {
          _allHospitals = hospitals;
          _allGroups = groups;
          _isLoading = false;
        });

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _centerOn1200Miles(_currentLocation);
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load MMaT dataset: $e';
          _isLoading = false;
        });
      }
    }
  }

  Color _getDisplayColor(int mmatScore) {
    return MmatHeatmapView.getScoreColor(mmatScore);
  }

  List<MmatLocationGroup> get _filteredGroups {
    if (_scoreFilterMin <= 0) return _allGroups;
    return _allGroups
        .where((g) => g.representativeScore >= _scoreFilterMin)
        .toList();
  }

  void _onGroupTapped(MmatLocationGroup group) {
    setState(() => _selectedGroup = group);
    _showHospitalDetailsSheet(group);
  }

  void _flyTo(double lat, double lng, [double zoom = 9.0]) {
    _mapController.move(LatLng(lat, lng), zoom);
  }

  void _showHospitalDetailsSheet(MmatLocationGroup group) {
    final cs = Theme.of(context).colorScheme;
    final color = MmatHeatmapView.getScoreColor(group.representativeScore);
    final diffFromNational = group.representativeScore - _nationalMedian;
    final diffStr = diffFromNational > 0
        ? '+$diffFromNational above national median ($_nationalMedian)'
        : diffFromNational < 0
            ? '$diffFromNational below national median ($_nationalMedian)'
            : 'Equal to national median ($_nationalMedian)';

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (sheetCtx, setSheetState) {
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.45,
              minChildSize: 0.3,
              maxChildSize: 0.85,
              builder: (_, scrollController) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: ListView(
                controller: scrollController,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: cs.onSurface.withAlpha(50),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: color.withAlpha(35),
                          border: Border.all(color: color, width: 1.5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: [
                            const Text(
                              'MMaT',
                              style: TextStyle(
                                  fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              '${group.representativeScore}',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: color,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${group.city}, ${group.state}',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              diffStr,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: color,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '150 NM Calculation Radius • ${group.hospitals.length} Donor Hospital(s)',
                              style: TextStyle(
                                fontSize: 11,
                                color: cs.onSurface.withAlpha(160),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF8E44AD).withAlpha(16),
                      border: Border.all(
                        color: const Color(0xFF8E44AD).withAlpha(60),
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.star_rounded,
                          size: 20,
                          color: Color(0xFF8E44AD),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Standard Exception: ${group.representativeScore - 3}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: Color(0xFF8E44AD),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Candidates with standard exception in this donor cohort receive MMaT − 3 (${group.representativeScore - 3}).',
                                style: const TextStyle(fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Donor Hospitals in Cluster (${group.hospitals.length})',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  ...group.hospitals.map((h) {
                    final isHome = _savedCenterCode == h.code;
                    return Card(
                      elevation: 0,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      color: cs.surfaceContainerHighest.withAlpha(60),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(
                          color: isHome ? cs.primary : cs.outlineVariant.withAlpha(100),
                          width: isHome ? 1.5 : 1.0,
                        ),
                      ),
                      child: ListTile(
                        dense: true,
                        leading: isHome
                            ? Tooltip(
                                message: 'My Saved Transplant Center',
                                child: Icon(Icons.star, color: cs.primary, size: 22),
                              )
                            : null,
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                h.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600, fontSize: 13),
                              ),
                            ),
                            if (isHome)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: cs.primary.withAlpha(30),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text('My Center',
                                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: cs.primary)),
                              ),
                          ],
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Code: ${h.code} • Cohort: ${h.cohortBeginDate} – ${h.cohortEndDate}',
                              style: const TextStyle(fontSize: 11),
                            ),
                            const SizedBox(height: 4),
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: const Size(50, 24),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              icon: Icon(isHome ? Icons.check : Icons.star_border, size: 14),
                              label: Text(
                                isHome ? 'Saved as My Center' : 'Set as My Transplant Center',
                                style: const TextStyle(fontSize: 11),
                              ),
                              onPressed: () async {
                                await _service.saveCenter(isHome ? null : h);
                                final updated = await _service.getSavedCenter();
                                if (mounted) {
                                  setState(() => _savedCenterCode = updated?.code);
                                  setSheetState(() {});
                                }
                              },
                            ),
                          ],
                        ),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: MmatHeatmapView.getScoreColor(h.medianMeld).withAlpha(40),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${h.medianMeld}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: MmatHeatmapView.getScoreColor(h.medianMeld),
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            );
          },
        );
      },
    );
  },
).whenComplete(() {
  if (mounted) {
    setState(() => _selectedGroup = null);
  }
});
  }

  void _showHospitalSearch() {
    showSearch(
      context: context,
      delegate: _HospitalSearchDelegate(
        hospitals: _allHospitals,
        onSelected: (h) {
          _flyTo(h.latitude, h.longitude, 10.0);
          final matchGroup = _allGroups.firstWhere(
            (g) =>
                (g.latitude - h.latitude).abs() < 0.01 &&
                (g.longitude - h.longitude).abs() < 0.01,
            orElse: () => MmatLocationGroup(
              city: h.city,
              state: h.state,
              latitude: h.latitude,
              longitude: h.longitude,
              representativeScore: h.medianMeld,
              hospitals: [h],
            ),
          );
          _onGroupTapped(matchGroup);
        },
      ),
    );
  }

  void _showInfoDialog() {
    final service = MmatDataService.instance;
    final cohortText = '${service.cohortBeginDate} – ${service.cohortEndDate}';
    final syncStatus = service.isLiveSynced ? 'Online GitHub Sync (Active)' : 'Bundled Asset';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('OPTN MMaT Policy & Cohort'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Median MELD at Transplant (MMaT)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 6),
              Text(
                'MMaT is calculated for each donor hospital in the United States based on a 365-day cohort of liver recipients age 12+ transplanted within a 150 nautical mile (NM) radius.\n\n'
                '• Active Cohort: $cohortText\n'
                '• Data Source: $syncStatus\n'
                '• 150 Nautical Miles = ~172.6 statute miles (277.8 km)\n'
                '• Exception scores are tied directly to the MMaT around the candidate\'s transplant hospital.',
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.sync, size: 16),
            label: const Text('Check for Updates'),
            onPressed: () async {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Checking GitHub for latest OPTN MMaT cohort...'),
                  duration: Duration(seconds: 2),
                ),
              );
              final res = await service.checkForUpdates();
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(res.message),
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(seconds: 4),
                ),
              );
              if (res.updated) {
                _loadData();
              }
            },
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Regional MMaT Heatmap',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Search hospitals or cities',
            onPressed: _allHospitals.isEmpty ? null : _showHospitalSearch,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.layers_outlined),
            tooltip: 'Google Maps Layer',
            onSelected: (type) => setState(() => _mapType = type),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'm',
                child: Row(
                  children: [
                    Icon(_mapType == 'm' ? Icons.check : Icons.map_outlined,
                        size: 18, color: const Color(0xFF007AFF)),
                    const SizedBox(width: 8),
                    const Text('Google Roadmap'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'p',
                child: Row(
                  children: [
                    Icon(_mapType == 'p' ? Icons.check : Icons.terrain_outlined,
                        size: 18, color: const Color(0xFF007AFF)),
                    const SizedBox(width: 8),
                    const Text('Google Terrain'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'y',
                child: Row(
                  children: [
                    Icon(_mapType == 'y' ? Icons.check : Icons.satellite_alt_outlined,
                        size: 18, color: const Color(0xFF007AFF)),
                    const SizedBox(width: 8),
                    const Text('Google Satellite (Hybrid)'),
                  ],
                ),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'OPTN Policy Info',
            onPressed: _showInfoDialog,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Loading OPTN MMaT dataset (5,887 hospitals)...'),
                ],
              ),
            )
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.red),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : Stack(
                  children: [
                    // The Map Canvas
                    FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: _currentLocation,
                        initialZoom: _initialZoom,
                        minZoom: 3.0,
                        maxZoom: 16.0,
                      ),
                      children: [
                        // Google Maps Map Tiles / Basemap Layer
                        TileLayer(
                          urlTemplate: _googleMapsApiKey.isNotEmpty
                              ? 'https://tile.googleapis.com/v1/2dtiles/{z}/{x}/{y}?key=$_googleMapsApiKey'
                              : 'https://mt{s}.google.com/vt/lyrs=$_mapType&x={x}&y={y}&z={z}',
                          subdomains: const ['0', '1', '2', '3'],
                          userAgentPackageName: 'com.bookmarc.meldcalculator',
                          tileBuilder: (isDark && _mapType == 'm')
                              ? darkModeTileBuilder
                              : null,
                        ),

                        // 150 Nautical Mile Radius Heatmap Layer
                        if (_showRadiuses)
                          CircleLayer(
                            circles: _filteredGroups.map((g) {
                              final color = _getDisplayColor(g.representativeScore);
                              return CircleMarker(
                                point: LatLng(g.latitude, g.longitude),
                                radius: MmatHospital.allocationRadiusMeters,
                                useRadiusInMeter: true,
                                color: color.withAlpha(28),
                                borderColor: color.withAlpha(90),
                                borderStrokeWidth: 0.8,
                              );
                            }).toList(),
                          ),

                        // Interactive Center Markers
                        if (_showMarkers)
                          MarkerLayer(
                            markers: _filteredGroups.map((g) {
                              final color = _getDisplayColor(g.representativeScore);
                              final isSelected = _selectedGroup != null &&
                                  (_selectedGroup!.latitude - g.latitude).abs() < 0.001 &&
                                  (_selectedGroup!.longitude - g.longitude).abs() < 0.001;
                              return Marker(
                                point: LatLng(g.latitude, g.longitude),
                                width: isSelected ? 38 : 32,
                                height: isSelected ? 38 : 32,
                                child: GestureDetector(
                                  onTap: () => _onGroupTapped(g),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: color,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                          color: isSelected
                                              ? Colors.amberAccent
                                              : Colors.white,
                                          width: isSelected ? 3.0 : 1.5),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withAlpha(60),
                                          blurRadius: isSelected ? 8 : 4,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: Center(
                                      child: Text(
                                        '${g.representativeScore}',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: isSelected ? 12 : 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),

                        // Current Location Marker
                        if (_hasLocation)
                          MarkerLayer(
                            markers: [
                              Marker(
                                point: _currentLocation,
                                width: 24,
                                height: 24,
                                child: Tooltip(
                                  message: 'Current Location',
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF007AFF),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                          color: Colors.white, width: 2.5),
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(0xFF007AFF)
                                              .withAlpha(120),
                                          blurRadius: 8,
                                          spreadRadius: 2,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),

                    // Top Filter & Control Chips
                    Positioned(
                      top: 10,
                      left: 10,
                      right: 10,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _buildFilterChip(
                              label: 'All (${_allHospitals.length})',
                              selected: _scoreFilterMin == 0,
                              onSelected: (_) =>
                                  setState(() => _scoreFilterMin = 0),
                            ),
                            const SizedBox(width: 8),
                            _buildFilterChip(
                              label: 'MMaT ≥ 34 (High)',
                              selected: _scoreFilterMin == 34,
                              onSelected: (selected) =>
                                  setState(() => _scoreFilterMin = selected ? 34 : 0),
                              badgeColor: const Color(0xFFD32F2F),
                            ),
                            const SizedBox(width: 8),
                            _buildFilterChip(
                              label: 'MMaT ≥ 31 (≥ National)',
                              selected: _scoreFilterMin == 31,
                              onSelected: (selected) =>
                                  setState(() => _scoreFilterMin = selected ? 31 : 0),
                              badgeColor: const Color(0xFFFFA000),
                            ),
                            const SizedBox(width: 8),
                            _buildFilterChip(
                              label: '150 NM Radiuses',
                              selected: _showRadiuses,
                              onSelected: (v) =>
                                  setState(() => _showRadiuses = v),
                            ),
                            const SizedBox(width: 8),
                            _buildFilterChip(
                              label: 'Hospital Pins',
                              selected: _showMarkers,
                              onSelected: (v) =>
                                  setState(() => _showMarkers = v),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Bottom Floating Legend
                    Positioned(
                      bottom: 16,
                      left: 16,
                      child: _buildLegendCard(cs),
                    ),

                    // Bottom-Right Quick Action FABs
                    Positioned(
                      bottom: 16,
                      right: 16,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FloatingActionButton.small(
                            heroTag: 'recenter_loc',
                            tooltip: 'Center Current Location (1200 mi)',
                            onPressed: () =>
                                _centerOn1200Miles(_currentLocation),
                            child: const Icon(Icons.my_location),
                          ),
                          const SizedBox(height: 8),
                          FloatingActionButton.small(
                            heroTag: 'recenter_usa',
                            tooltip: 'Full USA View',
                            onPressed: () => _flyTo(
                                _usaCenter.latitude,
                                _usaCenter.longitude,
                                _usaOverviewZoom),
                            child: const Icon(Icons.public),
                          ),
                          const SizedBox(height: 8),
                          FloatingActionButton.small(
                            heroTag: 'zoom_in',
                            tooltip: 'Zoom in',
                            onPressed: () {
                              final z = _mapController.camera.zoom + 1.0;
                              _mapController.move(
                                  _mapController.camera.center, z);
                            },
                            child: const Icon(Icons.add),
                          ),
                          const SizedBox(height: 8),
                          FloatingActionButton.small(
                            heroTag: 'zoom_out',
                            tooltip: 'Zoom out',
                            onPressed: () {
                              final z = _mapController.camera.zoom - 1.0;
                              _mapController.move(
                                  _mapController.camera.center, z);
                            },
                            child: const Icon(Icons.remove),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool selected,
    required ValueChanged<bool> onSelected,
    Color? badgeColor,
  }) {
    return FilterChip(
      selected: selected,
      onSelected: onSelected,
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (badgeColor != null) ...[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: badgeColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
          ],
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
      elevation: 2,
    );
  }

  Widget _buildLegendCard(ColorScheme cs) {
    return Card(
      elevation: 4,
      color: cs.surface.withAlpha(235),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: () => setState(() => _isLegendExpanded = !_isLegendExpanded),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'MMaT Legend',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _isLegendExpanded
                        ? Icons.keyboard_arrow_down
                        : Icons.keyboard_arrow_up,
                    size: 16,
                  ),
                ],
              ),
            ),
            if (_isLegendExpanded) ...[
              const SizedBox(height: 6),
              _buildLegendRow('≥ 34', 'Very High', const Color(0xFFC62828)),
              _buildLegendRow('32–33', 'High', const Color(0xFFFF7043)),
              _buildLegendRow('31', 'National Median', const Color(0xFFFBC02D)),
              _buildLegendRow('30', 'Moderate', const Color(0xFF00897B)),
              _buildLegendRow('< 30', 'Lower', const Color(0xFF1976D2)),
              const SizedBox(height: 4),
              Text(
                'Radius: 150 NM',
                style: TextStyle(
                  fontSize: 10,
                  fontStyle: FontStyle.italic,
                  color: cs.onSurface.withAlpha(150),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLegendRow(String range, String label, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$range ($label)',
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

/// Search delegate for finding hospitals by name, city, or state.
class _HospitalSearchDelegate extends SearchDelegate<MmatHospital?> {
  final List<MmatHospital> hospitals;
  final ValueChanged<MmatHospital> onSelected;

  _HospitalSearchDelegate({
    required this.hospitals,
    required this.onSelected,
  });

  @override
  List<Widget>? buildActions(BuildContext context) {
    return [
      if (query.isNotEmpty)
        IconButton(icon: const Icon(Icons.clear), onPressed: () => query = ''),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () => close(context, null),
    );
  }

  @override
  Widget buildResults(BuildContext context) => _buildSearchResults(context);

  @override
  Widget buildSuggestions(BuildContext context) => _buildSearchResults(context);

  Widget _buildSearchResults(BuildContext context) {
    final q = query.trim().toLowerCase();
    final results = q.isEmpty
        ? hospitals.take(20).toList()
        : hospitals
            .where((h) =>
                h.name.toLowerCase().contains(q) ||
                h.city.toLowerCase().contains(q) ||
                h.state.toLowerCase() == q ||
                h.code.toLowerCase().contains(q))
            .take(50)
            .toList();

    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (ctx, i) {
        final h = results[i];
        final color = MmatHeatmapView.getScoreColor(h.medianMeld);
        return ListTile(
          dense: true,
          title: Text(h.name, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text('${h.city}, ${h.state} • Code: ${h.code}'),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: color.withAlpha(35),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withAlpha(120)),
            ),
            child: Text(
              '${h.medianMeld}',
              style: TextStyle(fontWeight: FontWeight.bold, color: color),
            ),
          ),
          onTap: () {
            close(context, h);
            onSelected(h);
          },
        );
      },
    );
  }
}
