import 'dart:math';

/// Replicates the exact calculation logic from main.dart for verification.
/// Run with: dart test/meld_calc_test.dart

({int meld, int nameld, int meld3, double meldD, double meld3D})
    calculateMELD({
  required double cr,
  required double inr,
  required double tb,
  required double na,
  required double alb,
  required bool dialysis,
  required bool female,
}) {
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

  if (alb < 1.0) alb = 1.0;
  if (alb > 6.0) alb = 6.0;

  // Original MELD
  double meldDouble =
      3.78 * log(tb) + 11.20 * log(inr) + 9.57 * log(cr) + 6.43;
  int meld = meldDouble.round();

  // Na-MELD
  int nameld =
      (meldDouble + 1.32 * (137 - na) - (0.033 * meldDouble * (137 - na)))
          .round();

  // MELD 3.0
  double meld3Double = (4.56 * log(tb) +
      0.82 * (137 - na) -
      0.24 * (137 - na) * log(tb) +
      9.09 * log(inr) +
      11.14 * log(cr3) +
      1.85 * (3.5 - alb) -
      1.83 * (3.5 - alb) * log(cr3) +
      6);

  if (female) {
    meld3Double += 1.33;
  }

  if (meld3Double < 6) meld3Double = 6;

  int meld3 = meld3Double.round();

  return (
    meld: meld,
    nameld: nameld,
    meld3: meld3,
    meldD: meldDouble,
    meld3D: meld3Double
  );
}

void main() {
  int passed = 0;
  int failed = 0;

  void testCase(
    String name, {
    required double cr,
    required double inr,
    required double tb,
    required double na,
    required double alb,
    bool dialysis = false,
    bool female = false,
    required int expectedMeld,
    required int expectedNaMeld,
    required int expectedMeld3,
  }) {
    final r = calculateMELD(
      cr: cr, inr: inr, tb: tb, na: na, alb: alb,
      dialysis: dialysis, female: female,
    );

    final meldOk = r.meld == expectedMeld;
    final naOk = r.nameld == expectedNaMeld;
    final m3Ok = r.meld3 == expectedMeld3;
    final allOk = meldOk && naOk && m3Ok;

    if (allOk) {
      passed++;
      print('✅ $name');
      print('   MELD=${r.meld}  Na-MELD=${r.nameld}  MELD3.0=${r.meld3}');
      print('   (raw MELD=${r.meldD.toStringAsFixed(2)}, '
          'raw MELD3.0=${r.meld3D.toStringAsFixed(2)})');
    } else {
      failed++;
      print('❌ $name');
      print('   Got:      MELD=${r.meld}  Na-MELD=${r.nameld}  MELD3.0=${r.meld3}');
      print('   Expected: MELD=$expectedMeld  Na-MELD=$expectedNaMeld  MELD3.0=$expectedMeld3');
      print('   (raw MELD=${r.meldD.toStringAsFixed(4)}, '
          'raw MELD3.0=${r.meld3D.toStringAsFixed(4)})');
      if (!meldOk) print('   ⚠️  MELD mismatch');
      if (!naOk) print('   ⚠️  Na-MELD mismatch');
      if (!m3Ok) print('   ⚠️  MELD 3.0 mismatch');
    }
    print('');
  }

  print('═══════════════════════════════════════════════════');
  print('  MELD Calculator Verification Tests');
  print('═══════════════════════════════════════════════════\n');

  // ────────────────────────────────────────────────
  // Test 1: All defaults — everything at baseline
  // All ln() terms = 0, so MELD = 6.43 → 6
  // Na clamped to 137 → Na-MELD = MELD (no Na correction)
  // MELD 3.0: all zero terms + 6 = 6
  // ────────────────────────────────────────────────
  testCase(
    'Test 1: Default values (all normal)',
    cr: 1.0, inr: 1.0, tb: 1.0, na: 140, alb: 3.5,
    expectedMeld: 6,
    expectedNaMeld: 6,
    expectedMeld3: 6,
  );

  // ────────────────────────────────────────────────
  // Test 2: Moderate disease, Male
  // Reference: UNOS MELD calculator / MDCalc
  // Cr=1.5, INR=1.5, TB=3.0, Na=130, Alb=2.8
  // ────────────────────────────────────────────────
  // Manual MELD: 3.78*ln(3)+11.20*ln(1.5)+9.57*ln(1.5)+6.43
  //            = 3.78*1.0986 + 11.20*0.4055 + 9.57*0.4055 + 6.43
  //            = 4.153 + 4.542 + 3.881 + 6.43 = 19.006 → 19
  // Na-MELD: 19.006 + 1.32*(137-130) - 0.033*19.006*(137-130)
  //        = 19.006 + 9.24 - 4.39 = 23.856 → 24
  // MELD 3.0: 4.56*ln(3) + 0.82*(7) - 0.24*(7)*ln(3) + 9.09*ln(1.5)
  //         + 11.14*ln(1.5) + 1.85*(0.7) - 1.83*(0.7)*ln(1.5) + 6
  //        = 5.010 + 5.74 - 1.846 + 3.686 + 4.517 + 1.295 - 0.520 + 6
  //        = 23.882 → 24
  testCase(
    'Test 2: Moderate disease, Male',
    cr: 1.5, inr: 1.5, tb: 3.0, na: 130, alb: 2.8,
    expectedMeld: 19,
    expectedNaMeld: 24,
    expectedMeld3: 24,
  );

  // ────────────────────────────────────────────────
  // Test 3: Severe disease, Female
  // Cr=3.0 (capped at 3.0 for MELD3), INR=3.0, TB=10.0, Na=125, Alb=2.0
  // ────────────────────────────────────────────────
  // Manual MELD: 3.78*ln(10)+11.20*ln(3)+9.57*ln(3)+6.43
  //            = 3.78*2.3026 + 11.20*1.0986 + 9.57*1.0986 + 6.43
  //            = 8.704 + 12.304 + 10.514 + 6.43 = 37.952 → 38
  // Na-MELD: 37.952 + 1.32*12 - 0.033*37.952*12
  //        = 37.952 + 15.84 - 15.029 = 38.763 → 39
  // MELD 3.0 (Cr3=3.0): 4.56*ln(10) + 0.82*12 - 0.24*12*ln(10)
  //         + 9.09*ln(3) + 11.14*ln(3) + 1.85*1.5 - 1.83*1.5*ln(3) + 6 + 1.33
  //        = 10.504 + 9.84 - 6.633 + 9.987 + 12.242 + 2.775 - 3.014 + 6 + 1.33
  //        = 43.031 → 43
  testCase(
    'Test 3: Severe disease, Female',
    cr: 3.0, inr: 3.0, tb: 10.0, na: 125, alb: 2.0,
    female: true,
    expectedMeld: 38,
    expectedNaMeld: 39,
    expectedMeld3: 43,
  );

  // ────────────────────────────────────────────────
  // Test 4: Dialysis case, Male
  // Cr input=2.0, but dialysis overrides Cr→4.0 (MELD), Cr3→3.0 (MELD3)
  // INR=1.2, TB=2.0, Na=135, Alb=3.0
  // ────────────────────────────────────────────────
  // MELD: 3.78*ln(2)+11.20*ln(1.2)+9.57*ln(4)+6.43
  //     = 3.78*0.6931 + 11.20*0.1823 + 9.57*1.3863 + 6.43
  //     = 2.620 + 2.042 + 13.267 + 6.43 = 24.359 → 24
  // Na-MELD: 24.359 + 1.32*2 - 0.033*24.359*2
  //        = 24.359 + 2.64 - 1.608 = 25.391 → 25
  // MELD 3.0 (Cr3=3.0): 4.56*ln(2) + 0.82*2 - 0.24*2*ln(2)
  //         + 9.09*ln(1.2) + 11.14*ln(3) + 1.85*0.5 - 1.83*0.5*ln(3) + 6
  //        = 3.161 + 1.64 - 0.333 + 1.658 + 12.242 + 0.925 - 1.006 + 6
  //        = 24.287 → 24
  testCase(
    'Test 4: Dialysis, Male',
    cr: 2.0, inr: 1.2, tb: 2.0, na: 135, alb: 3.0,
    dialysis: true,
    expectedMeld: 24,
    expectedNaMeld: 25,
    expectedMeld3: 24,
  );

  // ────────────────────────────────────────────────
  // Test 5: Very low values (floor clamping)
  // Cr=0.5→1.0, INR=0.8→1.0, TB=0.3→1.0 → all ln()=0
  // Na=145→137, Alb=4.0
  // Should give minimum scores
  // ────────────────────────────────────────────────
  testCase(
    'Test 5: Below-floor values (all clamped to 1.0)',
    cr: 0.5, inr: 0.8, tb: 0.3, na: 145, alb: 4.0,
    expectedMeld: 6,
    expectedNaMeld: 6,
    expectedMeld3: 6,
  );

  // ────────────────────────────────────────────────
  // Test 6: High Cr capping
  // Cr=8.0 → capped to 4.0 (MELD), 3.0 (MELD3)
  // INR=2.0, TB=5.0, Na=128, Alb=2.5, Male
  // ────────────────────────────────────────────────
  // MELD: 3.78*ln(5)+11.20*ln(2)+9.57*ln(4)+6.43
  //     = 3.78*1.6094 + 11.20*0.6931 + 9.57*1.3863 + 6.43
  //     = 6.084 + 7.763 + 13.267 + 6.43 = 33.544 → 34
  // Na-MELD: 33.544 + 1.32*9 - 0.033*33.544*9
  //        = 33.544 + 11.88 - 9.963 = 35.461 → 35
  // MELD 3.0 (Cr3=3.0): 4.56*ln(5) + 0.82*9 - 0.24*9*ln(5)
  //         + 9.09*ln(2) + 11.14*ln(3) + 1.85*1.0 - 1.83*1.0*ln(3) + 6
  //        = 7.339 + 7.38 - 3.476 + 6.302 + 12.242 + 1.85 - 2.012 + 6
  //        = 35.625 → 36
  testCase(
    'Test 6: High Cr (capped), Male',
    cr: 8.0, inr: 2.0, tb: 5.0, na: 128, alb: 2.5,
    expectedMeld: 34,
    expectedNaMeld: 35,
    expectedMeld3: 36,
  );

  // ────────────────────────────────────────────────
  // Test 7: Female correction only
  // Same as defaults but female — MELD3.0 should be 6 + 1.33 = 7.33 → 7
  // ────────────────────────────────────────────────
  testCase(
    'Test 7: Default values, Female (+1.33)',
    cr: 1.0, inr: 1.0, tb: 1.0, na: 140, alb: 3.5,
    female: true,
    expectedMeld: 6,
    expectedNaMeld: 6,
    expectedMeld3: 7,
  );

  // ────────────────────────────────────────────────
  // Test 8: Low albumin impact on MELD 3.0
  // Alb=1.5 (very low), otherwise normal
  // MELD and Na-MELD unaffected by albumin
  // MELD 3.0: 1.85*(3.5-1.5) = 1.85*2 = 3.7 → 6 + 3.7 = 9.7 → 10
  // ────────────────────────────────────────────────
  testCase(
    'Test 8: Very low albumin, Male',
    cr: 1.0, inr: 1.0, tb: 1.0, na: 140, alb: 1.5,
    expectedMeld: 6,
    expectedNaMeld: 6,
    expectedMeld3: 10,
  );

  print('═══════════════════════════════════════════════════');
  print('  Results: $passed passed, $failed failed');
  print('═══════════════════════════════════════════════════');
}
