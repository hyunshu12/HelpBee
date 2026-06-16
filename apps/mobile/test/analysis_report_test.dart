// Tests for the diagnosis-report building blocks: tier-based recommendation
// fallback (backend doesn't return recommendations yet) and the RiskGauge.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:helpbee/core/risk/recommendations.dart';
import 'package:helpbee/core/risk/risk_tier.dart';
import 'package:helpbee/l10n/app_localizations.dart';
import 'package:helpbee/shared/widgets/risk_gauge.dart';

void main() {
  test('recommendationsFor returns tier-appropriate copy', () async {
    final l10n = await AppLocalizations.delegate.load(const Locale('ko'));

    expect(recommendationsFor(l10n, RiskTier.danger).length, 4);
    expect(recommendationsFor(l10n, RiskTier.watch).length, 3);
    expect(recommendationsFor(l10n, RiskTier.safe).length, 2);
    expect(recommendationsFor(l10n, RiskTier.unknown), isEmpty);

    // Danger copy mirrors the Figma report.
    expect(
      recommendationsFor(l10n, RiskTier.danger).first,
      '해당 벌통을 즉시 외부와 분리 격리하세요',
    );
  });

  test('gaugeCaption maps each tier', () async {
    final l10n = await AppLocalizations.delegate.load(const Locale('ko'));
    expect(gaugeCaption(l10n, RiskTier.danger), '심각 수준');
    expect(gaugeCaption(l10n, RiskTier.safe), '양호 수준');
    expect(gaugeCaption(l10n, RiskTier.unknown), '측정 불가');
  });

  testWidgets('RiskGauge shows the score; null score shows a dash', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RiskGauge(score: 84, tier: RiskTier.danger, caption: '심각 수준'),
        ),
      ),
    );
    expect(find.text('84'), findsOneWidget);
    expect(find.text('심각 수준'), findsOneWidget);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RiskGauge(
            score: null,
            tier: RiskTier.unknown,
            caption: '측정 불가',
          ),
        ),
      ),
    );
    expect(find.text('—'), findsOneWidget);
  });
}
