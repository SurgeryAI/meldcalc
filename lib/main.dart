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
    statusBarBrightness: Brightness.light, // For dark text on light background
  ));
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MELD Calc',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF007AFF), // iOS System Blue
          brightness: Brightness.light,
          surface: const Color(0xFFF2F2F7), // iOS System Background
        ),
        textTheme: const TextTheme(
          displaySmall: TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
          titleLarge: TextStyle(fontWeight: FontWeight.w600, fontSize: 20),
          bodyMedium: TextStyle(color: Colors.black54),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          color: Colors.white,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF2F2F7),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          labelStyle: const TextStyle(fontSize: 14, color: Colors.black54),
          hintStyle: const TextStyle(fontSize: 14, color: Colors.black26),
        ),
      ),
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

  @override
  void initState() {
    super.initState();
    _setupListeners();
    _calculateMELD();
  }

  void _setupListeners() {
    // Shared listener for automatic calculation
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

    // Focus listeners to clear field on focus and restore if empty on blur
    _addFocusBehavior(focusNodeCr, myControllerCr, (val) => crTemp = val, () => crTemp);
    _addFocusBehavior(focusNodeTB, myControllerTB, (val) => tbTemp = val, () => tbTemp);
    _addFocusBehavior(focusNodeINR, myControllerINR, (val) => inrTemp = val, () => inrTemp);
    _addFocusBehavior(focusNodeNa, myControllerNa, (val) => naTemp = val, () => naTemp);
    _addFocusBehavior(focusNodeAlb, myControllerAlb, (val) => albTemp = val, () => albTemp);
  }

  void _addFocusBehavior(FocusNode node, TextEditingController controller, Function(String) setTemp, String Function() getTemp) {
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

    double _cr = tryParse(myControllerCr.text, crTemp);
    double _inr = tryParse(myControllerINR.text, inrTemp);
    double _tb = tryParse(myControllerTB.text, tbTemp);
    double _na = tryParse(myControllerNa.text, naTemp);
    double _alb = tryParse(myControllerAlb.text, albTemp);

    double _cr3 = _cr;

    // Apply clinical constraints
    if (dialysis) {
      _cr = 4.0;
      _cr3 = 3.0;
    }
    
    if (_cr > 4.0) _cr = 4.0;
    if (_cr3 > 3.0) _cr3 = 3.0;
    if (_cr < 1.0) {
      _cr = 1.0;
      _cr3 = 1.0;
    }
    
    if (_tb < 1.0) _tb = 1.0;
    if (_inr < 1.0) _inr = 1.0;
    
    if (_na < 125) _na = 125;
    if (_na > 137) _na = 137;
    
    // Original MELD
    meldDouble = (3.78 * (log(_tb)) + 11.20 * (log(_inr)) + 9.57 * (log(_cr)) + 6.43);
    meld = meldDouble.round();

    // Na-MELD
    nameld = (meldDouble + 1.32 * (137 - _na) - (0.033 * meldDouble * (137 - _na))).round();

    // MELD 3.0
    meld3Double = (4.56 * log(_tb) + 0.82 * (137 - _na) - 0.24 * (137 - _na) * log(_tb) +
        9.09 * log(_inr) + 11.14 * log(_cr3) + 1.85 * (3.5 - _alb) - 1.83 * (3.5 - _alb) * log(_cr3) + 6);
    
    if (female) {
      meld3Double += 1.33;
    }
    
    meld3 = meld3Double.round();

    // Survival Predictions based on Stanford & PMC8608337
    // Model: Survival = S0^(exp(0.18 * (MELD - 10)))
    double riskFactor = exp(0.18 * (meld3Double - 10));
    survival30 = pow(0.99701, riskFactor) * 100;
    survival60 = pow(0.99138, riskFactor) * 100;
    survival90 = pow(0.99086, riskFactor) * 100;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
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
          IconButton(
            onPressed: _showInfoDialog,
            icon: const Icon(CupertinoIcons.info_circle_fill, color: Color(0xFF007AFF), size: 28.0),
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
              _buildResultsSection(),
              const SizedBox(height: 8),
              _buildSurvivalSection(),
              const SizedBox(height: 10),
              _buildInputSection(),
              const SizedBox(height: 6),
              const Center(
                child: Text(
                  'Calculations adjust based on current clinical standards.',
                  style: TextStyle(fontSize: 9, color: Colors.black38),
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

  Widget _buildResultsSection() {
    return Row(
      children: [
        Expanded(child: _buildResultCard('Orig MELD', meld.toString(), Colors.blueGrey)),
        const SizedBox(width: 8),
        Expanded(child: _buildResultCard('Na-MELD', nameld.toString(), Colors.indigo)),
        const SizedBox(width: 8),
        Expanded(child: _buildResultCard('MELD 3.0', meld3.toString(), const Color(0xFF007AFF))),
      ],
    );
  }

  Widget _buildResultCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.15),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w500),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 1),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSurvivalSection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF2F2F7)),
      ),
      child: Column(
        children: [
          const Text(
            'PREDICTED SURVIVAL (MELD 3.0)',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black45),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildSurvivalItem('30-Day', survival30),
              _buildSurvivalItem('60-Day', survival60),
              _buildSurvivalItem('90-Day', survival90),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSurvivalItem(String label, double value) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.black38)),
        const SizedBox(height: 2),
        Text(
          '${value.toStringAsFixed(1)}%',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: value < 50 ? Colors.redAccent : value < 80 ? Colors.orange : Colors.green[600],
          ),
        ),
      ],
    );
  }

  Widget _buildInputSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _buildToggleItem(
                    'Dialysis',
                    'X2 or CVVH',
                    dialysis,
                    (val) => setState(() {
                      dialysis = val;
                      _calculateMELD();
                    }),
                    Colors.orange,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildToggleItem(
                    'Female',
                    'Biological',
                    female,
                    (val) => setState(() {
                      female = val;
                      _calculateMELD();
                    }),
                    const Color(0xFF34C759),
                  ),
                ),
              ],
            ),
            const Divider(height: 16, thickness: 1, color: Color(0xFFF2F2F7)),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 6,
              crossAxisSpacing: 10,
              childAspectRatio: 2.6,
              children: [
                _buildInputField('Creatinine', 'Cr mg/dL', myControllerCr, focusNodeCr),
                _buildInputField('Bilirubin', 'TB mg/dL', myControllerTB, focusNodeTB),
                _buildInputField('INR', 'INR', myControllerINR, focusNodeINR),
                _buildInputField('Sodium', 'Na mEq/L', myControllerNa, focusNodeNa),
                _buildInputField('Albumin', 'Alb g/dL', myControllerAlb, focusNodeAlb),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToggleItem(String title, String subtitle, bool value, Function(bool) onChanged, Color activeColor) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFF2F2F7),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: value ? activeColor.withOpacity(0.3) : Colors.transparent,
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
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
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
              style: const TextStyle(fontSize: 9, color: Colors.black38),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputField(String label, String hint, TextEditingController controller, FocusNode node) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(hint, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: Colors.black45)),
        const SizedBox(height: 2),
        Expanded(
          child: TextFormField(
            controller: controller,
            focusNode: node,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
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
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
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
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                const _LiverLogo(size: 40),
                const SizedBox(width: 12),
                const Text(
                  'MELD 3.0 Calculator',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'This calculator is based on the following reference:',
              style: TextStyle(fontSize: 16, color: Colors.black87),
            ),
            const SizedBox(height: 12),
            Text(
              'Kim WR, Mannalithara A, Heimbach JK, Kamath PS, Asrani SK, Biggins SW, Wood NL, Gentry SE, Kwong AJ. MELD 3.0: The Model for End-stage Liver Disease Updated for the Modern Era. Gastroenterology. 2021 Sep 2:S0016-5085(21)03469-7. doi: 10.1053/j.gastro.2021.08.050. Epub ahead of print. PMID: 34481845.',
              style: TextStyle(fontSize: 14, color: Colors.black54, fontStyle: FontStyle.italic),
            ),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),
            const Text(
              'App built by Marc Melcher, MD, PhD.',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 40),
          ],
        ),
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
    path.quadraticBezierTo(size.width * 0.1, size.height * 0.2, size.width * 0.5, size.height * 0.2);
    path.quadraticBezierTo(size.width * 0.9, size.height * 0.2, size.width * 0.8, size.height * 0.5);
    path.quadraticBezierTo(size.width * 0.9, size.height * 0.8, size.width * 0.5, size.height * 0.8);
    path.quadraticBezierTo(size.width * 0.2, size.height * 0.8, size.width * 0.1, size.height * 0.5);
    path.close();

    // Add a modern "pulse" or cross detail
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
