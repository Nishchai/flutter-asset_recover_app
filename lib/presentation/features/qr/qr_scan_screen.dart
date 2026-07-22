import 'package:asset_recovery_app/core/di/injector.dart';
import 'package:asset_recovery_app/core/error/result.dart';
import 'package:asset_recovery_app/core/localization/app_localizations.dart';
import 'package:asset_recovery_app/core/theme/app_theme.dart';
import 'package:asset_recovery_app/domain/entities/battery.dart';
import 'package:asset_recovery_app/domain/usecases/validate_battery_scan_usecase.dart';
import 'package:asset_recovery_app/presentation/features/qr/qr_result_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// QR scanner (Figma "Battery scanner"): dark live-camera surface, the target
/// BP serial in yellow, a viewfinder that turns yellow on detect / red on a
/// wrong battery, and a manual-entry fallback.
///
/// The viewfinder is a stub stand-in for `mobile_scanner`; the validation +
/// result routing is production-ready. Demo buttons replace the live camera.
enum _ScanState { idle, detected, wrong }

class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key, required this.battery, required this.ticketId});

  final Battery battery;
  final String ticketId;

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  _ScanState _state = _ScanState.idle;
  bool _busy = false;

  Future<void> _simulate({required bool correct}) async {
    setState(() {
      _busy = true;
      _state = correct ? _ScanState.detected : _ScanState.wrong;
    });
    final serial = correct ? widget.battery.bpId : 'BP-IF-10097-P';
    final result = await sl<ValidateBatteryScanUseCase>()(ValidateScanParams(
      ticketId: widget.ticketId,
      bpId: widget.battery.bpId,
      scannedSerial: serial,
    ),);
    final ok = result.valueOrNull ?? false;
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (!mounted) return;
    setState(() => _busy = false);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => QrResultScreen(
          ticketId: widget.ticketId,
          expectedBpId: widget.battery.bpId,
          scannedBpId: serial,
          matched: ok,
        ),
      ),
    );
    if (mounted) setState(() => _state = _ScanState.idle);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = context.read<AppPalette>();

    final Color frameColor = switch (_state) {
      _ScanState.idle => Colors.white,
      _ScanState.detected => palette.primary,
      _ScanState.wrong => palette.danger,
    };

    return Scaffold(
      backgroundColor: palette.scannerBackground,
      body: SafeArea(
        child: Column(
          children: [
            // Top bar
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  _circleBtn(Icons.arrow_back,
                      () => Navigator.of(context).pop(), palette,),
                  const Spacer(),
                  Icon(Icons.more_vert, color: Colors.white.withValues(alpha: 0.8)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(l.t('qr.scanningFor'),
                style: TextStyle(color: palette.mutedDark, fontSize: 14),),
            const SizedBox(height: 4),
            Text(widget.battery.bpId,
                style: TextStyle(
                  color: palette.primary,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),),
            const SizedBox(height: 28),
            // Viewfinder
            Container(
              width: 230,
              height: 230,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: frameColor, width: 3),
              ),
              child: Icon(
                _state == _ScanState.wrong
                    ? Icons.error_outline
                    : Icons.qr_code_scanner,
                size: 56,
                color: frameColor,
              ),
            ),
            const SizedBox(height: 22),
            Text(l.t('qr.pointCamera'),
                textAlign: TextAlign.center,
                style: TextStyle(color: palette.mutedDark, fontSize: 13),),
            const Spacer(),
            // Bottom: manual entry OR wrong-battery banner + demo controls
            if (_state == _ScanState.wrong)
              _bottomBanner(l.t('qr.wrongBattery'), palette.danger)
            else
              _manualEntryButton(l, palette),
            const SizedBox(height: 14),
            // Demo scan controls (replace with live camera in production)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed:
                          _busy ? null : () => _simulate(correct: false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                      ),
                      child: const Text('Simulate wrong'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _busy ? null : () => _simulate(correct: true),
                      child: const Text('Simulate scan'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _circleBtn(IconData icon, VoidCallback onTap, AppPalette palette) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }

  Widget _manualEntryButton(AppLocalizations l, AppPalette palette) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: palette.primary),
        ),
        child: Text(l.t('qr.enterManually'),
            style: TextStyle(
                color: palette.primary, fontWeight: FontWeight.w600,),),
      ),
    );
  }

  Widget _bottomBanner(String text, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: color),
        ),
        child: Text(text,
            style: TextStyle(color: color, fontWeight: FontWeight.w600),),
      ),
    );
  }
}
