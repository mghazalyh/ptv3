import 'package:flutter_test/flutter_test.dart';
import 'package:playtorrio/services/player/subtitle_rate_correction.dart';

void main() {
  SubtitleTimingAnchor anchor(double cue, double speech,
      {int supporting = 3, double spread = 0.4}) =>
      SubtitleTimingAnchor(
        cueSeconds: cue, spokenSeconds: speech,
        supportingCues: supporting, spreadSeconds: spread,
      );

  test('two independent dialogue samples correct cumulative subtitle drift', () {
    final correction = SubtitleRateCorrection.estimate(
      anchor(300, 322.5), anchor(900, 947.5),
    );
    expect(correction, isNotNull);
    expect(correction!.speed, closeTo(1.0416666667, 0.0001));
    expect(correction.delaySeconds, closeTo(10, 0.01));
    expect(900 * correction.speed + correction.delaySeconds,
        closeTo(947.5, 0.01));
  });

  test('subtitle clock that runs too fast can be slowed down', () {
    final correction = SubtitleRateCorrection.estimate(
      anchor(300, 295), anchor(900, 871),
    );
    expect(correction, isNotNull);
    expect(correction!.speed, closeTo(0.96, 0.0001));
    expect(correction.delaySeconds, closeTo(7, 0.01));
  });

  test('a constant offset is not mistaken for time-rate drift', () {
    expect(SubtitleRateCorrection.estimate(
      anchor(300, 317), anchor(900, 917),
    ), isNull);
  });

  test('close samples, noisy matches and unrelated releases are rejected', () {
    expect(SubtitleRateCorrection.estimate(
      anchor(300, 315), anchor(360, 378),
    ), isNull);
    expect(SubtitleRateCorrection.estimate(
      anchor(300, 315, supporting: 1), anchor(900, 930),
    ), isNull);
    expect(SubtitleRateCorrection.estimate(
      anchor(300, 315), anchor(900, 930, spread: 1.7),
    ), isNull);
    expect(SubtitleRateCorrection.estimate(
      anchor(300, 315), anchor(900, 1010),
    ), isNull);
    expect(SubtitleRateCorrection.estimate(
      anchor(900, 930), anchor(300, 315),
    ), isNull);
    expect(SubtitleRateCorrection.estimate(
      anchor(300, double.nan), anchor(900, 930),
    ), isNull);
  });

  test('a large false intercept is rejected even for small clock drift', () {
    expect(SubtitleRateCorrection.estimate(
      anchor(300, 550), anchor(900, 1175),
    ), isNull);
  });
}
