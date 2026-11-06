import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:upgrader/upgrader.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:http/http.dart' as http;
import 'package:meldcalc/models/meld_calculator.dart';
import 'package:meldcalc/services/mmat_data_service.dart';
import 'package:meldcalc/views/mmat_heatmap_view.dart';
import 'dart:async';
import 'dart:convert';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarBrightness: Brightness.light,
  ));
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  final Upgrader? upgrader;
  const MyApp({super.key, this.upgrader});

  static const _seedColor = Color(0xFF007AFF);

  ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _seedColor,
        brightness: brightness,
        surface: isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0xFF3A3A3C) : const Color(0xFFF2F2F7),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        labelStyle: const TextStyle(fontSize: 14),
        hintStyle: const TextStyle(fontSize: 14),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MELD Calc',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      home: UpgradeAlert(
        dialogStyle: UpgradeDialogStyle.cupertino,
        upgrader: upgrader ??
            Upgrader(
              durationUntilAlertAgain: const Duration(days: 1),
              countryCode: 'US',
              debugLogging: kDebugMode,
            ),
        barrierDismissible: true,
        showLater: true,
        showIgnore: true,
        child: const MyHomePage(title: 'MELD 3.0 Calculator'),
      ),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});
  final String title;

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  Timer? inactivityTimer;

  // Results calculated via MeldCalculator model
  MeldResult _result = const MeldResult(
    meld: 0,
    nameld: 0,
    meld3: 0,
    meldDouble: 0,
    meld3Double: 0,
    survival30: 0,
    survival60: 0,
    survival90: 0,
  );

  int get meld => _result.meld;
  int get nameld => _result.nameld;
  int get meld3 => _result.meld3;
  double get meldDouble => _result.meldDouble;
  double get meld3Double => _result.meld3Double;
  double get survival30 => _result.survival30;
  double get survival60 => _result.survival60;
  double get survival90 => _result.survival90;

  // State
  bool dialysis = false;
  bool female = false;

  // Controllers
  final myControllerNa = TextEditingController(text: '140');
  final myControllerINR = TextEditingController(text: '1.0');
  final myControllerTB = TextEditingController(text: '1.0');
  final myControllerCr = TextEditingController(text: '1.0');
  final myControllerAlb = TextEditingController(text: '3.5');

  // Focus Nodes
  final focusNodeNa = FocusNode();
  final focusNodeINR = FocusNode();
  final focusNodeTB = FocusNode();
  final focusNodeCr = FocusNode();
  final focusNodeAlb = FocusNode();

  // Temp values to restore if empty
  String naTemp = '140';
  String inrTemp = '1.0';
  String tbTemp = '1.0';
  String crTemp = '1.0';
  String albTemp = '3.5';

  // Default values for reset
  static const _defaults = {
    'na': '140',
    'inr': '1.0',
    'tb': '1.0',
    'cr': '1.0',
    'alb': '3.5',
  };

  // User's Home Transplant Center (persisted)
  MmatHospital? _homeCenter;

  @override
  void initState() {
    super.initState();
    _setupListeners();
    _calculateMELD();
    _loadHomeCenter();
    _triggerMmatSync();
    WidgetsBinding.instance.addPostFrameCallback((_) => _showDisclaimerIfNeeded());
  }

  void _triggerMmatSync() {
    MmatDataService.instance.syncInBackground().then((_) {
      if (mounted) {
        _loadHomeCenter();
      }
    });
  }

  Future<void> _loadHomeCenter() async {
    final center = await MmatDataService.instance.getSavedCenter();
    if (mounted) {
      setState(() => _homeCenter = center);
    }
  }

  void _openMmatMap() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MmatHeatmapView(
          patientScore: meld3,
          initialHospitalCode: _homeCenter?.code,
        ),
      ),
    );
    if (!mounted) return;
    _loadHomeCenter();
  }

  void _showCenterPicker() async {
    final hospitals = await MmatDataService.instance.loadHospitals();
    if (!mounted) return;
    showSearch(
      context: context,
      delegate: _HospitalPickerSearchDelegate(
        hospitals: hospitals,
        currentCode: _homeCenter?.code,
        onClear: () async {
          await MmatDataService.instance.saveCenter(null);
          if (mounted) _loadHomeCenter();
        },
        onSelected: (h) async {
          await MmatDataService.instance.saveCenter(h);
          if (mounted) _loadHomeCenter();
        },
      ),
    );
  }

  Future<void> _showDisclaimerIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final shown = prefs.getBool('disclaimer_shown') ?? false;
    if (!shown && mounted) {
      await prefs.setBool('disclaimer_shown', true);
      if (!mounted) return;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          final cs = Theme.of(ctx).colorScheme;
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                Icon(CupertinoIcons.exclamationmark_triangle_fill,
                    color: Colors.orange, size: 24),
                const SizedBox(width: 10),
                const Text('Important Disclaimer'),
              ],
            ),
            content: Text(
              'This app is intended for educational and reference purposes only.\n\n'
              'It is NOT a clinical tool and must NOT be used to make decisions '
              'about patient care, diagnosis, or treatment.\n\n'
              'Always consult current institutional protocols and qualified '
              'healthcare professionals for patient management.',
              style: TextStyle(fontSize: 14, color: cs.onSurface, height: 1.5),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('I Understand'),
              ),
            ],
          );
        },
      );
    }
  }

  void _setupListeners() {
    void onValueChange() {
      setState(() {
        _calculateMELD();
      });
      _resetInactivityTimer();
    }

    myControllerCr.addListener(onValueChange);
    myControllerNa.addListener(onValueChange);
    myControllerINR.addListener(onValueChange);
    myControllerTB.addListener(onValueChange);
    myControllerAlb.addListener(onValueChange);

    _addFocusBehavior(focusNodeCr, myControllerCr, (val) => crTemp = val, () => crTemp);
    _addFocusBehavior(focusNodeTB, myControllerTB, (val) => tbTemp = val, () => tbTemp);
    _addFocusBehavior(focusNodeINR, myControllerINR, (val) => inrTemp = val, () => inrTemp);
    _addFocusBehavior(focusNodeNa, myControllerNa, (val) => naTemp = val, () => naTemp);
    _addFocusBehavior(focusNodeAlb, myControllerAlb, (val) => albTemp = val, () => albTemp);
  }

  void _addFocusBehavior(FocusNode node, TextEditingController controller,
      Function(String) setTemp, String Function() getTemp) {
    node.addListener(() {
      if (node.hasFocus) {
        setTemp(controller.text);
        controller.text = '';
        inactivityTimer?.cancel();
      } else {
        final parsed = double.tryParse(controller.text);
        if (controller.text.isEmpty || parsed == null || !parsed.isFinite) {
          controller.text = getTemp();
        } else {
          setTemp(controller.text);
        }
        _startInactivityTimer();
      }
    });
  }

  void _resetInactivityTimer() {
    inactivityTimer?.cancel();
    _startInactivityTimer();
  }

  void _startInactivityTimer() {
    inactivityTimer?.cancel();
    inactivityTimer = Timer(const Duration(milliseconds: 3000), () {
      if (_isCurrentValueInRange()) {
        FocusManager.instance.primaryFocus?.unfocus();
      }
    });
  }

  bool _isCurrentValueInRange() {
    final fields = [
      (node: focusNodeNa, controller: myControllerNa, min: 120.0, max: 160.0),
      (node: focusNodeCr, controller: myControllerCr, min: 0.5, max: 20.0),
      (node: focusNodeTB, controller: myControllerTB, min: 0.1, max: 80.0),
      (node: focusNodeINR, controller: myControllerINR, min: 0.5, max: 20.0),
      (node: focusNodeAlb, controller: myControllerAlb, min: 1.5, max: 6.0),
    ];
    for (final field in fields) {
      if (field.node.hasFocus) {
        final value = double.tryParse(field.controller.text);
        if (value == null) return false;
        return value >= field.min && value <= field.max;
      }
    }
    // No field is focused: keyboard is already dismissed, nothing to do.
    return false;
  }

  // Feature: reset all fields to defaults
  void _resetValues() {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      dialysis = false;
      female = false;
      myControllerCr.text = _defaults['cr']!;
      myControllerTB.text = _defaults['tb']!;
      myControllerINR.text = _defaults['inr']!;
      myControllerNa.text = _defaults['na']!;
      myControllerAlb.text = _defaults['alb']!;
      crTemp = _defaults['cr']!;
      tbTemp = _defaults['tb']!;
      inrTemp = _defaults['inr']!;
      naTemp = _defaults['na']!;
      albTemp = _defaults['alb']!;
      _calculateMELD();
    });
  }

  // Feature: copy score to clipboard with SnackBar feedback
  void _copyToClipboard(BuildContext context, String label, int value) {
    final text = '$label: $value';
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$text copied'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // Feature: UNOS-based MELD interpretation badge
  ({String label, Color color}) _getMeldInterpretation(int score) {
    if (score < 10) return (label: 'Low', color: const Color(0xFF34C759));
    if (score < 20) return (label: 'Moderate', color: Colors.orange);
    if (score < 30) return (label: 'High', color: Colors.deepOrange);
    return (label: 'Critical', color: Colors.red);
  }

  @override
  void dispose() {
    inactivityTimer?.cancel();
    myControllerNa.dispose();
    myControllerINR.dispose();
    myControllerTB.dispose();
    myControllerCr.dispose();
    myControllerAlb.dispose();
    focusNodeCr.dispose();
    focusNodeNa.dispose();
    focusNodeTB.dispose();
    focusNodeINR.dispose();
    focusNodeAlb.dispose();
    super.dispose();
  }

  void _calculateMELD() {
    double tryParse(String text, String fallback) {
      if (text.isEmpty) return double.tryParse(fallback) ?? 1.0;
      final val = double.tryParse(text);
      if (val == null || !val.isFinite) {
        return double.tryParse(fallback) ?? 1.0;
      }
      return val;
    }

    _result = MeldCalculator.calculate(
      cr: tryParse(myControllerCr.text, crTemp),
      inr: tryParse(myControllerINR.text, inrTemp),
      tb: tryParse(myControllerTB.text, tbTemp),
      na: tryParse(myControllerNa.text, naTemp),
      alb: tryParse(myControllerAlb.text, albTemp),
      dialysis: dialysis,
      female: female,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: Text(
          widget.title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        actions: [
          // Regional MMaT Heatmap button
          IconButton(
            onPressed: _openMmatMap,
            icon: const Icon(CupertinoIcons.map,
                color: Color(0xFF007AFF), size: 24.0),
            tooltip: 'Regional MMaT Heatmap',
          ),
          // Feature: reset button
          IconButton(
            onPressed: _resetValues,
            icon: Icon(CupertinoIcons.arrow_counterclockwise,
                color: cs.onSurfaceVariant, size: 22.0),
            tooltip: 'Reset',
          ),
          IconButton(
            onPressed: _showInfoDialog,
            icon: const Icon(CupertinoIcons.info_circle_fill,
                color: Color(0xFF007AFF), size: 28.0),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusScope.of(context).unfocus(),
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 2),
                _buildResultsSection(context),
                const SizedBox(height: 6),
                _buildSurvivalSection(context),
                const SizedBox(height: 6),
                _buildInputSection(context),
                const SizedBox(height: 8),
                _buildMmatSection(context),
                const SizedBox(height: 6),
                Center(
                  child: Text(
                    'Calculations adjust based on current clinical standards.',
                    style: TextStyle(fontSize: 9, color: cs.onSurfaceVariant.withAlpha(120)),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMmatSection(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mmat = _homeCenter?.medianMeld ?? 31;
    final hasCenter = _homeCenter != null;
    final exceptionScore = mmat - 3;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasCenter
              ? const Color(0xFF007AFF).withAlpha(100)
              : cs.outlineVariant.withAlpha(80),
          width: hasCenter ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 30 : 10),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row: Title & Map button
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF007AFF).withAlpha(22),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    CupertinoIcons.building_2_fill,
                    size: 16,
                    color: Color(0xFF007AFF),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'Donor Center MMaT',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: hasCenter
                                  ? const Color(0xFF2E7D32).withAlpha(25)
                                  : cs.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              hasCenter ? 'Local Cohort' : 'National Default',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                                color: hasCenter
                                    ? const Color(0xFF2E7D32)
                                    : cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        '150 NM donor cohort benchmark for liver allocation',
                        style: TextStyle(
                          fontSize: 10,
                          color: cs.onSurfaceVariant.withAlpha(180),
                        ),
                      ),
                    ],
                  ),
                ),
                // Regional Heatmap Button
                InkWell(
                  onTap: _openMmatMap,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF007AFF).withAlpha(16),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: const Color(0xFF007AFF).withAlpha(40),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(CupertinoIcons.map,
                            size: 12, color: Color(0xFF007AFF)),
                        SizedBox(width: 4),
                        Text(
                          'Map',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF007AFF),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Donor Center Search / Input Bar
            InkWell(
              onTap: _showCenterPicker,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF3A3A3C)
                      : const Color(0xFFF2F2F7),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: hasCenter
                        ? const Color(0xFF007AFF).withAlpha(80)
                        : cs.outlineVariant.withAlpha(60),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      hasCenter
                          ? CupertinoIcons.check_mark_circled_solid
                          : CupertinoIcons.search,
                      size: 16,
                      color: hasCenter
                          ? const Color(0xFF007AFF)
                          : cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: hasCenter
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _homeCenter!.name,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  '${_homeCenter!.city}, ${_homeCenter!.state}  •  OPTN Code: ${_homeCenter!.code}',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            )
                          : Text(
                              'Enter or select donor hospital...',
                              style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurfaceVariant.withAlpha(160),
                              ),
                            ),
                    ),
                    if (hasCenter) ...[
                      GestureDetector(
                        onTap: () async {
                          await MmatDataService.instance.saveCenter(null);
                          if (mounted) _loadHomeCenter();
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Icon(
                            CupertinoIcons.clear_circled_solid,
                            size: 16,
                            color: cs.onSurfaceVariant.withAlpha(180),
                          ),
                        ),
                      ),
                      const SizedBox(width: 2),
                    ],
                    Text(
                      hasCenter ? 'Change' : 'Select',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF007AFF),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),

            // Metrics Badges Row: MMaT Score & Standard Exception Benchmark
            Row(
              children: [
                // Local or National MMaT
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: hasCenter
                          ? const Color(0xFF007AFF).withAlpha(16)
                          : cs.surfaceContainerHighest.withAlpha(120),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          hasCenter ? 'DONOR MMaT' : 'NATIONAL MMaT',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                            color: hasCenter
                                ? const Color(0xFF007AFF)
                                : cs.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              '$mmat',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: hasCenter
                                    ? const Color(0xFF007AFF)
                                    : cs.onSurface,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Median',
                              style: TextStyle(
                                fontSize: 10,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Standard Exception Benchmark (MMaT - 3)
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF8E44AD).withAlpha(16),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'STANDARD EXCEPTION',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                            color: Color(0xFF8E44AD),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              '$exceptionScore',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF8E44AD),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'MMaT − 3',
                              style: TextStyle(
                                fontSize: 10,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultsSection(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
              child: _buildResultCard(context, 'Orig MELD', meld, Colors.blueGrey)),
          const SizedBox(width: 8),
          Expanded(
              child: _buildResultCard(context, 'Na-MELD', nameld, Colors.indigo)),
          const SizedBox(width: 8),
          Expanded(
              child: _buildResultCard(
                  context, 'MELD 3.0', meld3, const Color(0xFF007AFF),
                  showInterpretation: true)),
        ],
      ),
    );
  }

  Widget _buildResultCard(
      BuildContext context, String label, int value, Color color,
      {bool showInterpretation = false}) {
    final interpretation =
        showInterpretation ? _getMeldInterpretation(value) : null;
    return GestureDetector(
      // Feature: long-press copies score to clipboard
      onLongPress: () => _copyToClipboard(context, label, value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
              // Bug fix: withOpacity() is deprecated; use withAlpha()
              color: color.withAlpha(38),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Text(
              label,
              style: const TextStyle(
                  color: Colors.white, fontSize: 9, fontWeight: FontWeight.w500),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 1),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value.toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
              ),
            ),
            // Feature: UNOS interpretation badge on MELD 3.0 card
            if (interpretation != null) ...[
              const SizedBox(height: 3),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(51),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  interpretation.label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSurvivalSection(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cardColor =
        Theme.of(context).cardTheme.color ?? cs.surfaceContainerLow;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withAlpha(60)),
      ),
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              'PREDICTED SURVIVAL & MORTALITY (MELD 3.0)',
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: cs.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 10),
          // Feature: each column shows survival + mortality together
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildSurvivalColumn(context, '30-Day', survival30),
              _buildSurvivalColumn(context, '60-Day', survival60),
              _buildSurvivalColumn(context, '90-Day', survival90),
            ],
          ),
        ],
      ),
    );
  }

  // Feature: combined survival + mortality column
  Widget _buildSurvivalColumn(
      BuildContext context, String label, double survival) {
    final cs = Theme.of(context).colorScheme;
    final mortality = 100 - survival;
    return Column(
      children: [
        Text(label,
            style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
        const SizedBox(height: 2),
        Text(
          '${survival.toStringAsFixed(1)}%',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: survival < 50
                ? Colors.redAccent
                : survival < 80
                    ? Colors.orange
                    : Colors.green.shade600,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          '${mortality.toStringAsFixed(1)}% mort',
          style: TextStyle(
            fontSize: 9,
            color: mortality > 50
                ? Colors.redAccent
                : mortality > 20
                    ? Colors.orange
                    : cs.onSurfaceVariant.withAlpha(160),
          ),
        ),
      ],
    );
  }

  Widget _buildInputSection(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final inputBg =
        isDark ? const Color(0xFF3A3A3C) : const Color(0xFFF2F2F7);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _buildToggleItem(
                    context,
                    'Dialysis',
                    '2x/wk or CRRT',
                    dialysis,
                    (val) => setState(() {
                      dialysis = val;
                      _calculateMELD();
                    }),
                    Colors.orange,
                    inputBg,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildToggleItem(
                    context,
                    'Female',
                    'Biological',
                    female,
                    (val) => setState(() {
                      female = val;
                      _calculateMELD();
                    }),
                    const Color(0xFF34C759),
                    inputBg,
                  ),
                ),
              ],
            ),
            Divider(
                height: 16,
                thickness: 1,
                color: cs.outlineVariant.withAlpha(60)),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 6,
              crossAxisSpacing: 10,
              // Taller than default to accommodate field label + range hint text
              childAspectRatio: 2.2,
              children: [
                _buildInputField(context, 'Creatinine', 'Cr mg/dL',
                    myControllerCr, focusNodeCr, '0.5 – 20'),
                _buildInputField(context, 'Bilirubin', 'TB mg/dL',
                    myControllerTB, focusNodeTB, '0.1 – 80'),
                _buildInputField(context, 'INR', 'INR', myControllerINR,
                    focusNodeINR, '0.5 – 20'),
                _buildInputField(context, 'Sodium', 'Na mEq/L',
                    myControllerNa, focusNodeNa, '120 – 160'),
                _buildInputField(context, 'Albumin', 'Alb g/dL',
                    myControllerAlb, focusNodeAlb, '1.5 – 6.0'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToggleItem(
      BuildContext context,
      String title,
      String subtitle,
      bool value,
      Function(bool) onChanged,
      Color activeColor,
      Color bgColor) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            // Bug fix: withOpacity() deprecated; use withAlpha()
            color: value ? activeColor.withAlpha(77) : Colors.transparent,
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: cs.onSurface),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                SizedBox(
                  height: 20,
                  width: 34,
                  child: Transform.scale(
                    scale: 0.7,
                    child: Switch(
                      value: value,
                      onChanged: onChanged,
                      activeThumbColor: activeColor,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                  fontSize: 9, color: cs.onSurfaceVariant.withAlpha(150)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputField(
      BuildContext context,
      String label,
      String hint,
      TextEditingController controller,
      FocusNode node,
      // Feature: clinical range displayed under the field label
      String range) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(hint,
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: cs.onSurfaceVariant)),
            const Spacer(),
            // Feature: show valid clinical range as faint hint
            Text(range,
                style: TextStyle(
                    fontSize: 8,
                    color: cs.onSurfaceVariant.withAlpha(120))),
          ],
        ),
        const SizedBox(height: 2),
        Expanded(
          child: TextFormField(
            controller: controller,
            focusNode: node,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: cs.onSurface),
            decoration: InputDecoration(
              hintText: label,
              contentPadding: const EdgeInsets.symmetric(vertical: 4),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReference(ColorScheme cs,
      {required String label, required String citation}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: cs.onSurface),
        ),
        const SizedBox(height: 4),
        Text(
          citation,
          style: TextStyle(
              fontSize: 13,
              color: cs.onSurfaceVariant,
              fontStyle: FontStyle.italic),
        ),
      ],
    );
  }

  void _showInfoDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final cs = Theme.of(context).colorScheme;
        final cardColor =
            Theme.of(context).cardTheme.color ?? cs.surfaceContainerLow;
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.92,
          expand: false,
          builder: (_, scrollController) => Container(
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(30)),
            ),
            padding: const EdgeInsets.fromLTRB(32, 16, 32, 32),
            child: SingleChildScrollView(
              controller: scrollController,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: cs.outlineVariant,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      const _LiverLogo(size: 28),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'MELD 3.0 Calculator',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: cs.onSurface),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF007AFF).withAlpha(12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF007AFF).withAlpha(35)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Version 3.3.0  •  MMaT Cohort',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: cs.onSurface),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${MmatDataService.instance.cohortYearRange} (${MmatDataService.instance.donorHospitalCount} donor hospitals)',
                                style: TextStyle(
                                    fontSize: 10,
                                    color: cs.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.tonalIcon(
                          onPressed: () {
                            Navigator.pop(context);
                            _checkForUpdatesDialog(context);
                          },
                          icon: const Icon(CupertinoIcons.arrow_clockwise, size: 13),
                          label: const Text('Check Updates',
                              style: TextStyle(
                                  fontSize: 11, fontWeight: FontWeight.w600)),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'References',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: cs.onSurface),
                  ),
                  const SizedBox(height: 12),
                  _buildReference(
                    cs,
                    label: 'Original MELD',
                    citation:
                        'Kamath PS, Wiesner RH, Malinchoc M, et al. '
                        'A model to predict survival in patients with end-stage liver disease. '
                        'Hepatology. 2001;33(2):464-470. '
                        'doi: 10.1053/jhep.2001.22172. PMID: 11172350.',
                  ),
                  const SizedBox(height: 10),
                  _buildReference(
                    cs,
                    label: 'MELD-Na (Na-MELD)',
                    citation:
                        'Kim WR, Biggins SW, Kremers WK, et al. '
                        'Hyponatremia and Mortality among Patients on the Liver-Transplant Waiting List. '
                        'N Engl J Med. 2008;359(10):1018-1026. '
                        'doi: 10.1056/NEJMoa0801209. PMID: 18768945.',
                  ),
                  const SizedBox(height: 10),
                  _buildReference(
                    cs,
                    label: 'MELD 3.0',
                    citation:
                        'Kim WR, Mannalithara A, Heimbach JK, Kamath PS, Asrani SK, '
                        'Biggins SW, Wood NL, Gentry SE, Kwong AJ. '
                        'MELD 3.0: The Model for End-stage Liver Disease Updated for the Modern Era. '
                        'Gastroenterology. 2021 Sep 2:S0016-5085(21)03469-7. '
                        'doi: 10.1053/j.gastro.2021.08.050. PMID: 34481845.',
                  ),
                  const SizedBox(height: 10),
                  _buildReference(
                    cs,
                    label: 'Regional MMaT (OPTN Policy)',
                    citation:
                        'Organ Procurement and Transplantation Network (OPTN). '
                        'Median MELD at Transplant (MMaT) by Donor Hospital Cohort (150 Nautical Miles). '
                        'Updated semi-annually per OPTN liver allocation policy.',
                  ),
                  const SizedBox(height: 24),
                  Divider(color: cs.outlineVariant),
                  const SizedBox(height: 16),
                  Text(
                    'App built by Marc Melcher, MD, PhD.',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: cs.onSurface),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _checkForUpdatesDialog(BuildContext context) async {
    final cs = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Checking for App Store & OPTN MMaT updates...'),
              ],
            ),
          ),
        ),
      ),
    );

    // 1. Check OPTN MMaT GitHub Sync
    final mmatResult =
        await MmatDataService.instance.checkForUpdates(force: true);

    // 2. Check App Store version
    String? appStoreVersion;
    String? trackViewUrl;
    String? releaseNotes;
    String installedVersion = '3.3.0';
    try {
      final info = await PackageInfo.fromPlatform();
      installedVersion = info.version.isNotEmpty ? info.version : '3.3.0';
      final bundleId = 'com.bookmarc.meldcalculator';
      final response = await http
          .get(Uri.parse(
              'https://itunes.apple.com/lookup?bundleId=$bundleId&country=US'))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['resultCount'] > 0) {
          appStoreVersion = data['results'][0]['version'];
          trackViewUrl = data['results'][0]['trackViewUrl'];
          releaseNotes = data['results'][0]['releaseNotes'];
        }
      }
    } catch (_) {}

    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // dismiss loading

    final isNewerApp = appStoreVersion != null &&
        MmatDataService.isVersionNewer(appStoreVersion, installedVersion);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(CupertinoIcons.arrow_clockwise_circle_fill,
                color: Color(0xFF007AFF), size: 24),
            SizedBox(width: 8),
            Text('Updates Status'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'OPTN MMaT Dataset:',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: cs.onSurface),
            ),
            const SizedBox(height: 2),
            Text(
              mmatResult.message,
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            Text(
              'App Version:',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: cs.onSurface),
            ),
            const SizedBox(height: 2),
            Text(
              isNewerApp
                  ? 'New version available: v$appStoreVersion (Installed: v$installedVersion)'
                  : 'Installed: v$installedVersion (Up to date)',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight:
                      isNewerApp ? FontWeight.bold : FontWeight.normal,
                  color: isNewerApp
                      ? const Color(0xFF007AFF)
                      : cs.onSurfaceVariant),
            ),
            if (isNewerApp && releaseNotes != null && releaseNotes.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withAlpha(100),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  releaseNotes,
                  style: TextStyle(
                      fontSize: 11, color: cs.onSurfaceVariant),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
        actions: [
          if (trackViewUrl != null)
            FilledButton(
              onPressed: () async {
                final uri = Uri.parse(trackViewUrl!);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri,
                      mode: LaunchMode.externalApplication);
                }
              },
              child: const Text('Update on App Store'),
            ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _loadHomeCenter();
            },
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _LiverLogo extends StatelessWidget {
  final double size;
  const _LiverLogo({this.size = 32});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0x1A007AFF),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: CustomPaint(
        painter: _LiverPainter(color: const Color(0xFF007AFF)),
      ),
    );
  }
}

class _LiverPainter extends CustomPainter {
  final Color color;
  _LiverPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path();
    // Modern abstract liver shape
    path.moveTo(size.width * 0.2, size.height * 0.4);
    path.quadraticBezierTo(
        size.width * 0.1, size.height * 0.2, size.width * 0.5, size.height * 0.2);
    path.quadraticBezierTo(
        size.width * 0.9, size.height * 0.2, size.width * 0.8, size.height * 0.5);
    path.quadraticBezierTo(
        size.width * 0.9, size.height * 0.8, size.width * 0.5, size.height * 0.8);
    path.quadraticBezierTo(
        size.width * 0.2, size.height * 0.8, size.width * 0.1, size.height * 0.5);
    path.close();

    final detailPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = size.width * 0.1
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(path, paint);
    canvas.drawLine(
      Offset(size.width * 0.4, size.height * 0.5),
      Offset(size.width * 0.6, size.height * 0.5),
      detailPaint,
    );
    canvas.drawLine(
      Offset(size.width * 0.5, size.height * 0.4),
      Offset(size.width * 0.5, size.height * 0.6),
      detailPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _HospitalPickerSearchDelegate extends SearchDelegate<MmatHospital?> {
  final List<MmatHospital> hospitals;
  final String? currentCode;
  final VoidCallback? onClear;
  final ValueChanged<MmatHospital> onSelected;

  _HospitalPickerSearchDelegate({
    required this.hospitals,
    this.currentCode,
    this.onClear,
    required this.onSelected,
  }) : super(searchFieldLabel: 'Search hospital, city, or state...');

  @override
  List<Widget>? buildActions(BuildContext context) => [
        if (query.isNotEmpty)
          IconButton(icon: const Icon(Icons.clear), onPressed: () => query = ''),
      ];

  @override
  Widget? buildLeading(BuildContext context) => IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => close(context, null),
      );

  @override
  Widget buildResults(BuildContext context) => _buildList(context);

  @override
  Widget buildSuggestions(BuildContext context) => _buildList(context);

  Widget _buildList(BuildContext context) {
    final q = query.trim().toLowerCase();
    final results = q.isEmpty
        ? hospitals.take(25).toList()
        : hospitals
            .where((h) =>
                h.name.toLowerCase().contains(q) ||
                h.city.toLowerCase().contains(q) ||
                h.state.toLowerCase() == q ||
                h.code.toLowerCase().contains(q))
            .take(50)
            .toList();

    final showClearOption = currentCode != null && q.isEmpty;
    final totalCount = results.length + (showClearOption ? 1 : 0);

    return ListView.builder(
      itemCount: totalCount,
      itemBuilder: (ctx, index) {
        if (showClearOption && index == 0) {
          return ListTile(
            dense: true,
            leading: const Icon(Icons.clear, color: Colors.grey, size: 22),
            title: const Text('Reset to National MMaT (31)',
                style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: const Text('Clear hospital-specific benchmark'),
            onTap: () {
              close(context, null);
              onClear?.call();
            },
          );
        }

        final i = showClearOption ? index - 1 : index;
        final h = results[i];
        final isCurrent = h.code == currentCode;
        final color = MmatHeatmapView.getScoreColor(h.medianMeld);

        return ListTile(
          dense: true,
          leading: isCurrent
              ? const Icon(Icons.star, color: Colors.amber, size: 22)
              : const Icon(Icons.local_hospital_outlined, size: 22),
          title: Text(h.name, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text('${h.city}, ${h.state} • Code: ${h.code}'),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: color.withAlpha(30),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'MMaT ${h.medianMeld}',
              style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 12),
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
