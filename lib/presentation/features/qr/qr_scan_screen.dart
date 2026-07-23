import 'package:asset_recovery_app/core/di/injector.dart';
import 'package:asset_recovery_app/core/error/result.dart';
import 'package:asset_recovery_app/core/localization/app_localizations.dart';
import 'package:asset_recovery_app/core/theme/app_theme.dart';
import 'package:asset_recovery_app/domain/entities/battery.dart';
import 'package:asset_recovery_app/domain/usecases/validate_battery_scan_usecase.dart';
import 'package:asset_recovery_app/presentation/features/qr/qr_result_screen.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

/// QR scanner (Figma "Battery scanner"): a live `mobile_scanner` camera surface,
/// the target BP serial in yellow, a viewfinder that turns yellow on detect /
/// red on a wrong battery, and a manual-entry fallback.
///
/// The camera decodes BP serial QR codes; the first successful decode is
/// validated via [ValidateBatteryScanUseCase] and routed to [QrResultScreen].
/// Further decodes are ignored while a result is being handled. On platforms
/// without a usable camera (e.g. some emulators) the manual-entry path remains.
enum _ScanState { idle, detected, wrong }

class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key, required this.battery, required this.ticketId});

  final Battery battery;
  final String ticketId;

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode],
  );
  _ScanState _state = _ScanState.idle;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_busy) return;
    final raw = capture.barcodes
        .map((b) => b.rawValue)
        .firstWhere((v) => v != null && v.isNotEmpty, orElse: () => null);
    if (raw == null) return;
    _process(raw);
  }

  Future<void> _process(String scannedSerial) async {
    setState(() => _busy = true);
    final result = await sl<ValidateBatteryScanUseCase>()(ValidateScanParams(
      ticketId: widget.ticketId,
      bpId: widget.battery.bpId,
      scannedSerial: scannedSerial,
    ),);
    final ok = result.valueOrNull ?? false;
    if (!mounted) return;
    setState(() => _state = ok ? _ScanState.detected : _ScanState.wrong);
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => QrResultScreen(
          ticketId: widget.ticketId,
          expectedBpId: widget.battery.bpId,
          scannedBpId: scannedSerial,
          matched: ok,
        ),
      ),
    );
    if (!mounted) return;
    // Returned from the result screen — reset so the agent can scan again.
    setState(() {
      _state = _ScanState.idle;
      _busy = false;
    });
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
      // The manual-entry dialog floats above and handles the keyboard inset
      // itself, so the fixed-height scanner layout must not resize (it would
      // overflow at the bottom when the keyboard opens).
      resizeToAvoidBottomInset: false,
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
                  _torchButton(palette),
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
            // Live-camera viewfinder
            Container(
              width: 230,
              height: 230,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: frameColor, width: 3),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(25),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    MobileScanner(
                      controller: _controller,
                      onDetect: _onDetect,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, child) =>
                          _cameraUnavailable(palette),
                    ),
                    if (_state == _ScanState.wrong)
                      Container(
                        color: palette.danger.withValues(alpha: 0.25),
                        child: Icon(Icons.error_outline,
                            size: 56, color: palette.danger,),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 22),
            Text(l.t('qr.pointCamera'),
                textAlign: TextAlign.center,
                style: TextStyle(color: palette.mutedDark, fontSize: 13),),
            const Spacer(),
            // Bottom: manual entry OR wrong-battery banner
            if (_state == _ScanState.wrong)
              _bottomBanner(l.t('qr.wrongBattery'), palette.danger)
            else
              _manualEntryButton(l, palette),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _torchButton(AppPalette palette) {
    return ValueListenableBuilder<MobileScannerState>(
      valueListenable: _controller,
      builder: (context, state, _) => _circleBtn(
        state.torchState == TorchState.on ? Icons.flash_on : Icons.flash_off,
        () => _controller.toggleTorch(),
        palette,
      ),
    );
  }

  Widget _cameraUnavailable(AppPalette palette) {
    return Container(
      color: Colors.black26,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.no_photography_outlined,
              size: 48, color: Colors.white.withValues(alpha: 0.7),),
          const SizedBox(height: 8),
          Text(
            AppLocalizations.of(context).t('qr.cameraUnavailable'),
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12),
          ),
        ],
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
      child: InkWell(
        onTap: _busy ? null : _promptManualEntry,
        borderRadius: BorderRadius.circular(28),
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
      ),
    );
  }

  Future<void> _promptManualEntry() async {
    final l = AppLocalizations.of(context);
    final controller = TextEditingController();
    final serial = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.t('qr.enterManually')),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: InputDecoration(hintText: widget.battery.bpId),
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l.t('common.cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: Text(l.t('common.confirm')),
          ),
        ],
      ),
    );
    if (serial != null && serial.isNotEmpty) {
      await _process(serial);
    }
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
