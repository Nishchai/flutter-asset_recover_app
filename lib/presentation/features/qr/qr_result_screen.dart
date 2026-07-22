import 'package:asset_recovery_app/core/localization/app_localizations.dart';
import 'package:asset_recovery_app/core/theme/app_theme.dart';
import 'package:asset_recovery_app/core/utils/formatters.dart';
import 'package:asset_recovery_app/presentation/shared/widgets/pill_button.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// QR verification result (Figma "Confirmation Screen" / "QR mismatch").
///
/// Matched → dark hero with yellow check, ticket/status/scanned-at facts, and a
/// "Proceed to collect Battery" CTA. Mismatch → red hero, scanned-vs-expected
/// facts, blocked submission, and Confirm / Raise-a-new-ticket actions.
class QrResultScreen extends StatelessWidget {
  const QrResultScreen({
    super.key,
    required this.ticketId,
    required this.expectedBpId,
    required this.scannedBpId,
    required this.matched,
  });

  final String ticketId;
  final String expectedBpId;
  final String scannedBpId;
  final bool matched;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = context.read<AppPalette>();
    final accent = matched ? palette.primary : palette.danger;
    final stamp = Formatters.scanStamp(DateTime.now());

    return Scaffold(
      backgroundColor: palette.background,
      body: Column(
        children: [
          // Dark hero
          Container(
            width: double.infinity,
            decoration: BoxDecoration(gradient: palette.heroGradient),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 36),
                child: Column(
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: IconButton(
                        icon: Icon(Icons.close, color: palette.onDark),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: accent, width: 2.5),
                      ),
                      child: Icon(Icons.check, color: accent, size: 30),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      matched ? l.t('qrResult.matched') : l.t('qrResult.mismatch'),
                      style: TextStyle(
                        color: accent,
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(matched ? expectedBpId : scannedBpId,
                        style: TextStyle(color: palette.onDark, fontSize: 16),),
                  ],
                ),
              ),
            ),
          ),
          // Light facts
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Column(
                children: [
                  _fact(l.t('qrResult.ticket'), ticketId, palette),
                  _fact(l.t('qrResult.status'),
                      matched ? l.t('qrResult.verified') : l.t('qrResult.notVerified'),
                      palette,),
                  if (!matched) ...[
                    _fact(l.t('qrResult.scanned'), scannedBpId, palette),
                    _fact(l.t('qrResult.expected'), expectedBpId, palette),
                  ],
                  _fact(l.t('qrResult.scannedAt'), stamp, palette, last: true),
                  const Spacer(),
                  Text(
                    matched ? l.t('qrResult.matchBody') : l.t('qrResult.mismatchBody'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: palette.muted, fontSize: 12.5),
                  ),
                  const SizedBox(height: 14),
                ],
              ),
            ),
          ),
          // Actions
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: matched
                  ? SizedBox(
                      width: double.infinity,
                      child: PillButton.dark(
                        l.t('qrResult.proceed'),
                        palette: palette,
                        trailingArrow: true,
                        onPressed: () => Navigator.of(context).pop(true),
                      ),
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: PillButton.outline(
                            l.t('common.confirm'),
                            palette: palette,
                            onPressed: () => Navigator.of(context).pop(false),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: PillButton.yellow(
                            l.t('qrResult.raiseTicket'),
                            palette: palette,
                            trailingArrow: true,
                            onPressed: () => Navigator.of(context).pop(false),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fact(String k, String v, AppPalette palette, {bool last = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: last
            ? null
            : Border(bottom: BorderSide(color: palette.border)),
      ),
      child: Row(
        children: [
          Text(k, style: TextStyle(color: palette.muted)),
          const Spacer(),
          Text(v, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
