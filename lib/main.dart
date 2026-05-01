import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'dart:math';
import 'dart:async';

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
  const MyApp({super.key});

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
      home: const MyHomePage(title: 'MELD 3.0 Calculator'),
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

  // Results
  int nameld = 0;
  int meld = 0;
  int meld3 = 0;
  double meldDouble = 0;
  double meld3Double = 0;

  // Survival Predicted (%)
  double survival30 = 0;
  double survival60 = 0;
  double survival90 = 0;

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

  @override
  void initState() {
    super.initState();
    _setupListeners();
    _calculateMELD();
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
        if (controller.text.isEmpty) {
          controller.text = getTemp();
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
    inactivityTimer = Timer(const Duration(seconds: 8), () {
      FocusManager.instance.primaryFocus?.unfocus();
    });
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
      if (text.isEmpty) return double.parse(fallback);
      return double.tryParse(text) ?? double.parse(fallback);
    }

    double cr = tryParse(myControllerCr.text, crTemp);
    double inr = tryParse(myControllerINR.text, inrTemp);
    double tb = tryParse(myControllerTB.text, tbTemp);
    double na = tryParse(myControllerNa.text, naTemp);
    double alb = tryParse(myControllerAlb.text, albTemp);

    double cr3 = cr;

    // Apply clinical constraints
    if (dialysis) {
      cr = 4.0;
      cr3 = 3.0;
    }

    if (cr > 4.0) cr = 4.0;
    if (cr3 > 3.0) cr3 = 3.0;
    if (cr < 1.0) {
      cr = 1.0;
      cr3 = 1.0;
    }

    if (tb < 1.0) tb = 1.0;
    if (inr < 1.0) inr = 1.0;

    if (na < 125) na = 125;
    if (na > 137) na = 137;

    // Bug fix: clamp albumin to physiologically plausible range so extreme
    // entries (e.g. alb = 10) do not push MELD 3.0 below its minimum.
    if (alb < 1.0) alb = 1.0;
    if (alb > 6.0) alb = 6.0;

    // Original MELD
    meldDouble = (3.78 * (log(tb)) + 11.20 * (log(inr)) + 9.57 * (log(cr)) + 6.43);
    meld = meldDouble.round();

    // Na-MELD
    nameld = (meldDouble + 1.32 * (137 - na) - (0.033 * meldDouble * (137 - na))).round();

    // MELD 3.0 (Kim et al. Gastroenterology 2021)
    meld3Double = (4.56 * log(tb) + 0.82 * (137 - na) - 0.24 * (137 - na) * log(tb) +
        9.09 * log(inr) + 11.14 * log(cr3) + 1.85 * (3.5 - alb) -
        1.83 * (3.5 - alb) * log(cr3) + 6);

    if (female) {
      meld3Double += 1.33;
    }

    // Enforce OPTN minimum score floor of 6
    if (meld3Double < 6) meld3Double = 6;

    meld3 = meld3Double.round();

    // Survival predictions based on PMC8608337 (Kim et al. 2021, Table 4)
    // Model: Survival(t) = S0(t) ^ exp(0.18 * (MELD3.0 − 10))
    // S0 values represent baseline cumulative survival at reference MELD3.0 = 10.
    // TODO: verify S0(60d)=0.99138 and S0(90d)=0.99086 against Table 4 of PMC8608337.
    // The two differ by only 0.00052, yielding nearly identical 60-day and 90-day
    // predictions (e.g. 94.9% vs 94.6% at MELD 20), which is clinically implausible.
    // Expected difference should be comparable to the 30d→60d drop of ~0.00563.
    final riskFactor = exp(0.18 * (meld3Double - 10));
    survival30 = pow(0.99701, riskFactor) * 100;
    survival60 = pow(0.99138, riskFactor) * 100;
    survival90 = pow(0.99086, riskFactor) * 100;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: Row(
          children: [
            const _LiverLogo(size: 32),
            const SizedBox(width: 10),
            Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
          ],
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        actions: [
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
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 2),
              _buildResultsSection(context),
              const SizedBox(height: 8),
              _buildSurvivalSection(context),
              const SizedBox(height: 10),
              _buildInputSection(context),
              const SizedBox(height: 6),
              Center(
                child: Text(
                  'Calculations adjust based on current clinical standards.',
                  style: TextStyle(fontSize: 9, color: cs.onSurfaceVariant.withAlpha(120)),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResultsSection(BuildContext context) {
    return Row(
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
          Text(
            'PREDICTED SURVIVAL & MORTALITY (MELD 3.0)',
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: cs.onSurfaceVariant),
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
                      activeColor: activeColor,
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

  void _showInfoDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final cs = Theme.of(context).colorScheme;
        final cardColor =
            Theme.of(context).cardTheme.color ?? cs.surfaceContainerLow;
        return Container(
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(30)),
          ),
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
                  const _LiverLogo(size: 40),
                  const SizedBox(width: 12),
                  Text(
                    'MELD 3.0 Calculator',
                    style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: cs.onSurface),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'This calculator is based on the following reference:',
                style: TextStyle(fontSize: 16, color: cs.onSurface),
              ),
              const SizedBox(height: 12),
              Text(
                'Kim WR, Mannalithara A, Heimbach JK, Kamath PS, Asrani SK, Biggins SW, Wood NL, Gentry SE, Kwong AJ. MELD 3.0: The Model for End-stage Liver Disease Updated for the Modern Era. Gastroenterology. 2021 Sep 2:S0016-5085(21)03469-7. doi: 10.1053/j.gastro.2021.08.050. Epub ahead of print. PMID: 34481845.',
                style: TextStyle(
                    fontSize: 14,
                    color: cs.onSurfaceVariant,
                    fontStyle: FontStyle.italic),
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
        );
      },
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
