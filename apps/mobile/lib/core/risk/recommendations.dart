import 'package:helpbee/l10n/app_localizations.dart';

import 'risk_tier.dart';

/// Client-side recommended-actions copy, keyed by [RiskTier].
///
/// ⚠️ The backend stores `recommendations` but does NOT return them on any
/// analysis response (frontend-api-integration §4 GAP). Until that lands, the
/// report screen falls back to this generic, tier-based guidance — surfaced with
/// a disclaimer ([AppLocalizations.reportRecommendDisclaimer]) so it is never
/// mistaken for a model prescription. The danger copy mirrors the Figma report.
List<String> recommendationsFor(AppLocalizations l10n, RiskTier tier) =>
    switch (tier) {
      RiskTier.danger => [
        l10n.recDanger1,
        l10n.recDanger2,
        l10n.recDanger3,
        l10n.recDanger4,
      ],
      RiskTier.watch => [l10n.recWatch1, l10n.recWatch2, l10n.recWatch3],
      RiskTier.safe => [l10n.recSafe1, l10n.recSafe2],
      RiskTier.unknown => const <String>[],
    };

/// Severity caption shown inside the gauge (양호/주의/심각/측정 불가 수준).
String gaugeCaption(AppLocalizations l10n, RiskTier tier) => switch (tier) {
  RiskTier.safe => l10n.gaugeCaptionSafe,
  RiskTier.watch => l10n.gaugeCaptionWatch,
  RiskTier.danger => l10n.gaugeCaptionDanger,
  RiskTier.unknown => l10n.gaugeCaptionUnknown,
};
