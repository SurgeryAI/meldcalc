import 'package:flutter_test/flutter_test.dart';
import 'package:meldcalc/models/meld_calculator.dart';

void main() {
  group('MELD Calculator Verification Tests', () {
    void verifyCase(
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
      test(name, () {
        final r = MeldCalculator.calculate(
          cr: cr,
          inr: inr,
          tb: tb,
          na: na,
          alb: alb,
          dialysis: dialysis,
          female: female,
        );

        expect(r.meld, expectedMeld, reason: 'MELD mismatch');
        expect(r.nameld, expectedNaMeld, reason: 'Na-MELD mismatch');
        expect(r.meld3, expectedMeld3, reason: 'MELD 3.0 mismatch');
      });
    }

    // ────────────────────────────────────────────────
    // Test 1: All defaults — everything at baseline
    // ────────────────────────────────────────────────
    verifyCase(
      'Test 1: Default values (all normal)',
      cr: 1.0, inr: 1.0, tb: 1.0, na: 140, alb: 3.5,
      expectedMeld: 6,
      expectedNaMeld: 6,
      expectedMeld3: 6,
    );

    // ────────────────────────────────────────────────
    // Test 2: Moderate disease, Male
    // Reference: UNOS MELD calculator / MDCalc
    // ────────────────────────────────────────────────
    verifyCase(
      'Test 2: Moderate disease, Male',
      cr: 1.5, inr: 1.5, tb: 3.0, na: 130, alb: 2.8,
      expectedMeld: 19,
      expectedNaMeld: 24,
      expectedMeld3: 24,
    );

    // ────────────────────────────────────────────────
    // Test 3: Severe disease, Female
    // ────────────────────────────────────────────────
    verifyCase(
      'Test 3: Severe disease, Female',
      cr: 3.0, inr: 3.0, tb: 10.0, na: 125, alb: 2.0,
      female: true,
      expectedMeld: 38,
      expectedNaMeld: 39,
      expectedMeld3: 43,
    );

    // ────────────────────────────────────────────────
    // Test 4: Dialysis case, Male
    // ────────────────────────────────────────────────
    verifyCase(
      'Test 4: Dialysis, Male',
      cr: 2.0, inr: 1.2, tb: 2.0, na: 135, alb: 3.0,
      dialysis: true,
      expectedMeld: 24,
      expectedNaMeld: 25,
      expectedMeld3: 24,
    );

    // ────────────────────────────────────────────────
    // Test 5: Very low values (floor clamping)
    // ────────────────────────────────────────────────
    verifyCase(
      'Test 5: Below-floor values (all clamped to 1.0)',
      cr: 0.5, inr: 0.8, tb: 0.3, na: 145, alb: 4.0,
      expectedMeld: 6,
      expectedNaMeld: 6,
      expectedMeld3: 6,
    );

    // ────────────────────────────────────────────────
    // Test 6: High Cr capping
    // ────────────────────────────────────────────────
    verifyCase(
      'Test 6: High Cr (capped), Male',
      cr: 8.0, inr: 2.0, tb: 5.0, na: 128, alb: 2.5,
      expectedMeld: 34,
      expectedNaMeld: 35,
      expectedMeld3: 36,
    );

    // ────────────────────────────────────────────────
    // Test 7: Female correction only (+1.33)
    // ────────────────────────────────────────────────
    verifyCase(
      'Test 7: Default values, Female (+1.33)',
      cr: 1.0, inr: 1.0, tb: 1.0, na: 140, alb: 3.5,
      female: true,
      expectedMeld: 6,
      expectedNaMeld: 6,
      expectedMeld3: 7,
    );

    // ────────────────────────────────────────────────
    // Test 8: Low albumin impact on MELD 3.0 (alb = 1.5 floor)
    // ────────────────────────────────────────────────
    verifyCase(
      'Test 8: Very low albumin, Male',
      cr: 1.0, inr: 1.0, tb: 1.0, na: 140, alb: 1.5,
      expectedMeld: 6,
      expectedNaMeld: 6,
      expectedMeld3: 10,
    );

    // ────────────────────────────────────────────────
    // Test 9: Kim et al. 2021 Table 4 Benchmark (Low-Risk Male, Albumin > 3.5 capped)
    // Cr=1.2, INR=1.0, TB=2.5, Na=131, Alb=3.8 -> MELD 3.0 = 16
    // ────────────────────────────────────────────────
    test('Test 9: Kim 2021 Table 4 Low-Risk Male (Albumin > 3.5 capped)', () {
      final r = MeldCalculator.calculate(
        cr: 1.2,
        inr: 1.0,
        tb: 2.5,
        na: 131,
        alb: 3.8,
      );
      expect(r.meld3, 16);
    });

    // ────────────────────────────────────────────────
    // Test 10: Non-finite inputs safety (NaN / Infinity)
    // ────────────────────────────────────────────────
    test('Test 10: Safe fallback on NaN and Infinity', () {
      final r = MeldCalculator.calculate(
        cr: double.nan,
        inr: double.infinity,
        tb: double.negativeInfinity,
        na: double.nan,
        alb: double.nan,
      );
      expect(r.meld, greaterThanOrEqualTo(6));
      expect(r.meld3, greaterThanOrEqualTo(6));
      expect(r.survival30.isFinite, isTrue);
      expect(r.survival60.isFinite, isTrue);
      expect(r.survival90.isFinite, isTrue);
    });
  });
}
