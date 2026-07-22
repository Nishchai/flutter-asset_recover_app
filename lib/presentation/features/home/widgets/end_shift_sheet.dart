import 'package:asset_recovery_app/core/localization/app_localizations.dart';
import 'package:asset_recovery_app/core/theme/app_theme.dart';
import 'package:asset_recovery_app/presentation/shared/widgets/pill_button.dart';
import 'package:asset_recovery_app/presentation/state/shift_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

/// End-of-shift OTP sheet (Figma "Daily logout flow"). The agent enters the OTP
/// sent to their registered mobile to end the shift. Demo accepts any 6 digits.
class EndShiftSheet extends StatefulWidget {
  const EndShiftSheet({super.key});

  @override
  State<EndShiftSheet> createState() => _EndShiftSheetState();
}

class _EndShiftSheetState extends State<EndShiftSheet> {
  final _otp = TextEditingController();
  bool _busy = false;
  bool _error = false;

  @override
  void dispose() {
    _otp.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = false;
    });
    final ok = await context.read<ShiftProvider>().verifyEndOtp(_otp.text.trim());
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _busy = false;
        _error = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = context.read<AppPalette>();
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: BoxDecoration(
          color: palette.background,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        padding: const EdgeInsets.fromLTRB(22, 12, 22, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color: palette.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(l.t('endShift.title'),
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold,),),
            const SizedBox(height: 4),
            Text(l.t('endShift.body'),
                style: TextStyle(color: palette.muted, height: 1.4),),
            const SizedBox(height: 18),
            TextField(
              controller: _otp,
              keyboardType: TextInputType.number,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                counterText: '',
                hintText: '••••••',
                errorText: _error ? l.t('validation.otpRequired') : null,
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => context.read<ShiftProvider>().requestEndOtp(),
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              child: Text(l.t('endShift.resend'),
                  style: TextStyle(color: palette.info),),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: _busy
                  ? const Center(child: CircularProgressIndicator())
                  : PillButton.dark(
                      l.t('endShift.submit'),
                      palette: palette,
                      trailingArrow: true,
                      onPressed: _submit,
                    ),
            ),
            const SizedBox(height: 14),
            Center(
              child: Text.rich(
                TextSpan(
                  text: '${l.t('endShift.trouble')} ',
                  style: TextStyle(color: palette.muted, fontSize: 13),
                  children: [
                    TextSpan(
                      text: l.t('endShift.contactSupport'),
                      style: TextStyle(
                          color: palette.info, fontWeight: FontWeight.w600,),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
