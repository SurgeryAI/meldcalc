import 'dart:math';

/// Immutable model representing the results of MELD, MELD-Na, and MELD 3.0 calculations,
/// along with 30-, 60-, and 90-day predicted survival and mortality.
class MeldResult {
  final int meld;
  final int nameld;
  final int meld3;
  final double meldDouble;
  final double meld3Double;
  final double survival30;
  final double survival60;
  final double survival90;

  const MeldResult({
    required this.meld,
    required this.nameld,
    required this.meld3,
    required this.meldDouble,
    required this.meld3Double,
    required this.survival30,
    required this.survival60,
    required this.survival90,
  });

  /// Convenient aliases for raw scores (matching test expectations)
  double get meldD => meldDouble;
  double get meld3D => meld3Double;

  double get mortality30 => 100 - survival30;
  double get mortality60 => 100 - survival60;
  double get mortality90 => 100 - survival90;

  /// Clinical interpretation level according to UNOS risk thresholds.
  MeldRiskLevel get riskLevel {
    if (meld3 < 10) return MeldRiskLevel.low;
    if (meld3 < 20) return MeldRiskLevel.moderate;
    if (meld3 < 30) return MeldRiskLevel.high;
    return MeldRiskLevel.critical;
  }
}

enum MeldRiskLevel {
  low('Low'),
  moderate('Moderate'),
  high('High'),
  critical('Critical');

  final String label;
  const MeldRiskLevel(this.label);
}

/// Pure Dart calculator for MELD, MELD-Na, MELD 3.0, and predicted survival.
class MeldCalculator {
  const MeldCalculator._();

  /// Calculates Original MELD, MELD-Na, MELD 3.0, and predicted survival.
  ///
  /// [cr] Creatinine (mg/dL)
  /// [inr] International Normalized Ratio
  /// [tb] Total Bilirubin (mg/dL)
  /// [na] Serum Sodium (mEq/L)
  /// [alb] Serum Albumin (g/dL)
  /// [dialysis] Whether patient had 2+ dialysis sessions in past week or CRRT
  /// [female] Biological sex is female (adds +1.33 in MELD 3.0)
  static MeldResult calculate({
    required double cr,
    required double inr,
    required double tb,
    required double na,
    required double alb,
    bool dialysis = false,
    bool female = false,
  }) {
    // Sanitize non-finite or non-positive values to prevent math runtime errors
    double crAdjusted = (cr.isFinite && cr > 0) ? cr : 1.0;
    double cr3Adjusted = crAdjusted;
    double tbAdjusted = (tb.isFinite && tb > 0) ? tb : 1.0;
    double inrAdjusted = (inr.isFinite && inr > 0) ? inr : 1.0;
    double naAdjusted = na.isFinite ? na : 137.0;
    double albAdjusted = alb.isFinite ? alb : 3.5;

    // Apply clinical constraints
    if (dialysis) {
      crAdjusted = 4.0;
      cr3Adjusted = 3.0;
    }

    if (crAdjusted > 4.0) crAdjusted = 4.0;
    if (cr3Adjusted > 3.0) cr3Adjusted = 3.0;
    if (crAdjusted < 1.0) {
      crAdjusted = 1.0;
      cr3Adjusted = 1.0;
    }

    if (tbAdjusted < 1.0) tbAdjusted = 1.0;
    if (inrAdjusted < 1.0) inrAdjusted = 1.0;

    if (naAdjusted < 125) naAdjusted = 125;
    if (naAdjusted > 137) naAdjusted = 137;

    // In MELD 3.0 (Kim et al. 2021 & OPTN policy), serum albumin is bounded to [1.5, 3.5] g/dL.
    // Albumin > 3.5 is capped at 3.5 to prevent (3.5 - Alb) from becoming negative,
    // which would inappropriately lower the score for patients with normal/high albumin.
    if (albAdjusted < 1.5) albAdjusted = 1.5;
    if (albAdjusted > 3.5) albAdjusted = 3.5;

    // Original MELD (Kamath PS, et al. Hepatology 2001)
    final meldDouble = (3.78 * (log(tbAdjusted)) +
        11.20 * (log(inrAdjusted)) +
        9.57 * (log(crAdjusted)) +
        6.43);
    final meld = meldDouble.round();

    // Na-MELD (Kim WR, et al. N Engl J Med 2008)
    final nameld = (meldDouble +
            1.32 * (137 - naAdjusted) -
            (0.033 * meldDouble * (137 - naAdjusted)))
        .round();

    // MELD 3.0 (Kim WR, et al. Gastroenterology 2021)
    double meld3Double = (4.56 * log(tbAdjusted) +
        0.82 * (137 - naAdjusted) -
        0.24 * (137 - naAdjusted) * log(tbAdjusted) +
        9.09 * log(inrAdjusted) +
        11.14 * log(cr3Adjusted) +
        1.85 * (3.5 - albAdjusted) -
        1.83 * (3.5 - albAdjusted) * log(cr3Adjusted) +
        6);

    if (female) {
      meld3Double += 1.33;
    }

    // Enforce OPTN minimum score floor of 6
    if (meld3Double < 6) meld3Double = 6;

    final meld3 = meld3Double.round();

    // Survival predictions based on PMC8608337 (Kim et al. 2021, Table 4 & Supp Table 3b)
    // Model: Survival(t) = S0(t) ^ exp(0.18 * (MELD3.0 − 10))
    // S0(90d) = 0.99086 derived from 90-day waitlist mortality (5.4% at MELD 20 in Supp Table 3b).
    // S0(30d) = 0.99701 corresponds to ~1.8% mortality at MELD 20.
    // S0(60d) = 0.99390 interpolated proportionally by cumulative hazard (H0(60) = 2/3 * H0(90)).
    final riskFactor = exp(0.18 * (meld3Double - 10));
    final survival30 = pow(0.99701, riskFactor) * 100;
    final survival60 = pow(0.99390, riskFactor) * 100;
    final survival90 = pow(0.99086, riskFactor) * 100;

    return MeldResult(
      meld: meld,
      nameld: nameld,
      meld3: meld3,
      meldDouble: meldDouble,
      meld3Double: meld3Double,
      survival30: survival30.toDouble(),
      survival60: survival60.toDouble(),
      survival90: survival90.toDouble(),
    );
  }
}
