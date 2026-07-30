import 'package:asset_recovery_app/core/localization/app_localizations.dart';
import 'package:asset_recovery_app/core/theme/app_theme.dart';
import 'package:asset_recovery_app/presentation/shared/widgets/pill_button.dart';
import 'package:asset_recovery_app/presentation/state/auth_provider.dart';
import 'package:asset_recovery_app/presentation/state/shift_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

/// End-of-shift OTP sheet (Figma "Daily logout flow"). Owns the whole OTP
/// exchange: opening the sheet is what requests the code — the home toggle only
/// shows it — and the code goes to the agent's registered mobile, the
/// `usermobileNumber` of their `commonLogin` record.
///
/// [ShiftProvider.otpLength] digits, verified against the SMS gateway when
/// "Confirm & End Shift" is pressed. Sends are debounced by
/// [ShiftProvider.otpResendCooldown], so reopening the sheet or hammering
/// "Resend" never spends a second SMS.
class EndShiftSheet extends StatefulWidget {
  const EndShiftSheet({super.key});

  @override
  State<EndShiftSheet> createState() => _EndShiftSheetState();
}

class _EndShiftSheetState extends State<EndShiftSheet> {
  final _otp = TextEditingController();
  bool _busy = false;

  /// Problem line under the input: a wrong code, a failed send, or the "wait N
  /// seconds" message when a send was debounced away.
  String? _fieldError;

  /// Positive confirmation that a code was just (re)sent.
  String? _sentNotice;

  @override
  void initState() {
    super.initState();
    // The request happens HERE, not on the home toggle: a flip the agent backs
    // straight out of must not cost an SMS. Post-frame so the first build (and
    // the localizations/provider lookups it needs) has completed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _send(announce: false);
    });
  }

  @override
  void dispose() {
    _otp.dispose();
    super.dispose();
  }

  /// Requests the OTP. [announce] is true for the agent-initiated "Resend" —
  /// only then is the outcome reported, since the automatic send on open has
  /// nothing useful to say when it is debounced away (the code from the last
  /// send, moments ago, is still valid).
  Future<void> _send({required bool announce}) async {
    final shift = context.read<ShiftProvider>();
    final l = AppLocalizations.of(context);
    setState(() {
      _fieldError = null;
      _sentNotice = null;
    });
    final result = await shift.requestEndOtp();
    if (!mounted) return;
    setState(() {
      switch (result) {
        case EndOtpSendResult.sent:
          // Anything already typed can only be a superseded code.
          _otp.clear();
          if (announce) _sentNotice = l.t('endShift.otpSent');
        case EndOtpSendResult.throttled:
          if (announce) {
            _fieldError = l.t('endShift.otpWait',
                {'seconds': shift.otpCooldownRemaining},);
          }
        case EndOtpSendResult.failed:
          // Always surfaced, even for the automatic send: no code is coming, so
          // the agent has to know before they sit waiting for one.
          final error = shift.otpError;
          _fieldError =
              error == null || error.isEmpty ? l.t('common.error') : error;
      }
    });
  }

  /// Verifies the code and, only on a match, closes the sheet and signs the
  /// agent out. The shift is ended by [ShiftProvider.verifyEndOtp] and the
  /// session by [AuthProvider.logout] — never by dismissing this sheet.
  Future<void> _submit() async {
    final l = AppLocalizations.of(context);
    setState(() {
      _busy = true;
      _fieldError = null;
      _sentNotice = null;
    });
    // Read before the pop below: afterwards this element is defunct and
    // `context.read` on it throws.
    final auth = context.read<AuthProvider>();
    final shift = context.read<ShiftProvider>();
    final ok = await shift.verifyEndOtp(_otp.text.trim());
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _busy = false;
        // A gateway failure keeps its own message; anything else reaching here
        // is a wrong or too-short code.
        _fieldError = shift.otpError ?? l.t('validation.invalidOtp');
      });
      return;
    }
    // Ending the shift is a full sign-out (daily logout flow): close the sheet
    // FIRST so no route is left sitting over the login screen, then erase the
    // session — access token, agent and the commonLogin profile — from
    // encrypted storage. The next launch starts at mobile + OTP again.
    Navigator.of(context).pop();
    await auth.logout();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = context.read<AppPalette>();
    final shift = context.watch<ShiftProvider>();
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
              // Same length the gateway was asked to generate, so the field can
              // never demand more (or fewer) digits than the SMS carries.
              maxLength: ShiftProvider.otpLength,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                counterText: '',
                hintText: '•' * ShiftProvider.otpLength,
                errorText: _fieldError,
              ),
            ),
            if (_sentNotice != null) ...[
              const SizedBox(height: 6),
              Text(_sentNotice!,
                  style: TextStyle(color: palette.info, fontSize: 12.5),),
            ],
            const SizedBox(height: 8),
            TextButton(
              // Disabled only while a send is actually in flight. A press inside
              // the cooldown is allowed through and answered with the "wait N
              // seconds" message — the provider blocks the gateway call, so the
              // agent gets told why instead of tapping a dead button.
              onPressed: shift.sendingOtp ? null : () => _send(announce: true),
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
