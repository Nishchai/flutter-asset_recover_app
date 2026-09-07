import 'dart:async';

import 'package:asset_recovery_app/core/di/app_services.dart';
import 'package:asset_recovery_app/core/di/injector.dart';
import 'package:asset_recovery_app/core/localization/app_localizations.dart';
import 'package:asset_recovery_app/core/services/connectivity_service.dart';
import 'package:asset_recovery_app/core/theme/app_theme.dart';
import 'package:asset_recovery_app/core/utils/validators.dart';
import 'package:asset_recovery_app/presentation/features/auth/widgets/otp_input.dart';
import 'package:asset_recovery_app/presentation/state/auth_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

/// Field-agent sign-in: mobile number (validated server-side) followed by OTP
/// verification. In demo/mock mode any 10-digit mobile + 6-digit OTP succeeds.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  /// How long "Resend OTP" stays locked after a code is sent.
  static const _resendCooldown = Duration(seconds: 60);

  final _mobile = TextEditingController(text: '');
  final _otp = TextEditingController();
  String? _mobileError;
  String? _otpError;

  /// Seconds left before "Resend OTP" becomes actionable again; 0 = unlocked.
  int _resendIn = 0;
  Timer? _resendTimer;
  bool _cooldownPrimed = false;

  @override
  void initState() {
    super.initState();
    // Rebuild as the user types so the Send OTP button can enable/recolour
    // the moment a valid 10-digit number is present.
    _mobile.addListener(_onMobileChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Normally the cooldown is started by whichever action sent the OTP, but
    // this screen can also be built already on the OTP step (e.g. rebuilt by
    // the root router while an OTP is outstanding) — start it once here so the
    // resend button is never live the instant the step appears.
    if (!_cooldownPrimed) {
      _cooldownPrimed = true;
      if (context.read<AuthProvider>().status == AuthStatus.otpSent) {
        // Pre-build: assign directly, setState() during build would assert.
        _startResendCooldown(notify: false);
      }
    }
  }

  void _startResendCooldown({bool notify = true}) {
    _resendTimer?.cancel();
    _resendIn = _resendCooldown.inSeconds;
    if (notify) setState(() {});
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _resendIn--);
      if (_resendIn <= 0) {
        timer.cancel();
        _resendTimer = null;
      }
    });
  }

  void _stopResendCooldown() {
    _resendTimer?.cancel();
    _resendTimer = null;
    if (_resendIn != 0) setState(() => _resendIn = 0);
  }

  void _onMobileChanged() {
    // Clear any stale error once the input becomes valid, and trigger a
    // rebuild to update the button's enabled/colour state.
    if (_mobileError != null && Validators.isValidMobile(_mobile.text.trim())) {
      _mobileError = null;
    }
    setState(() {});
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _mobile.removeListener(_onMobileChanged);
    _mobile.dispose();
    _otp.dispose();
    super.dispose();
  }

  Future<void> _submitMobile() async {
    final l = AppLocalizations.of(context);
    final auth = context.read<AuthProvider>();
    final value = _mobile.text.trim();
    if (!Validators.isValidMobile(value)) {
      setState(() => _mobileError = l.t('validation.invalidMobile'));
      return;
    }
    if (!await sl<ConnectivityService>().isOnline()) {
      if (!mounted) return;
      setState(() => _mobileError = l.t('login.noInternet'));
      return;
    }
    setState(() => _mobileError = null);
    // Step 1 = commonLogin (directory lookup) + OTP send. On success
    // AuthProvider moves to AuthStatus.otpSent and this screen rebuilds into
    // the OTP step below; on failure no OTP was sent, so show WHY the number
    // was rejected (the backend's `reason`) inline on the field.
    final ok = await auth.requestOtp(value);
    if (!mounted) return;
    if (ok) {
      // OTP is out — lock resend for the cooldown window.
      _startResendCooldown();
    } else {
      setState(() => _mobileError = auth.error ?? l.t('common.error'));
    }
  }

  /// Re-sends the OTP to the same number and restarts the cooldown. Only
  /// reachable once [_resendIn] has counted down to 0.
  Future<void> _resendOtp() async {
    final l = AppLocalizations.of(context);
    final auth = context.read<AuthProvider>();
    final mobile = auth.mobile;
    if (mobile == null) return;
    setState(() => _otpError = null);
    // Lock the button up front so it can't be double-tapped while the send is
    // in flight; a failed send unlocks it again below.
    _startResendCooldown();
    final ok = await auth.requestOtp(mobile);
    if (!ok && mounted) {
      _stopResendCooldown();
      setState(() => _mobileError = auth.error ?? l.t('common.error'));
    }
  }

  Future<void> _submitOtp() async {
    final l = AppLocalizations.of(context);
    final otpLength = context.read<AppServices>().config.env.gupshup.otpCodeLength;
    final value = _otp.text.trim();
    if (!Validators.isValidOtp(value, length: otpLength)) {
      setState(() => _otpError = l.t('validation.otpRequired'));
      return;
    }
    setState(() => _otpError = null);
    // On success the root router swaps in the home shell — no post-login
    // navigation needed here. On failure surface the error inline on the OTP
    // field (red outline + message) rather than as a generic banner.
    final ok = await context.read<AuthProvider>().verifyOtp(value);
    if (!ok && mounted) {
      setState(() => _otpError = l.t('validation.invalidOtp'));
    }
  }

  void _changeNumber() {
    _otp.clear();
    _stopResendCooldown();
    setState(() => _otpError = null);
    context.read<AuthProvider>().resetToMobileEntry();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = context.read<AppPalette>();
    final config = context.read<AppServices>().config;
    final auth = context.watch<AuthProvider>();
    final onOtpStep =
        auth.status == AuthStatus.otpSent || auth.status == AuthStatus.verifyingOtp;
    final busy =
        auth.status == AuthStatus.sendingOtp || auth.status == AuthStatus.verifyingOtp;
    final mobileValid = Validators.isValidMobile(_mobile.text.trim());
    // Resend is live only once the countdown has run out and no OTP call is
    // already in flight.
    final resendReady = _resendIn == 0 && !busy;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: palette.primary,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(Icons.bolt, color: Colors.white, size: 38),
                ),
                const SizedBox(height: 20),
                Text(
                  l.t('login.title'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: palette.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  onOtpStep
                      ? l.t('login.otpSubtitle', {'mobile': auth.mobile ?? ''})
                      : l.t('login.subtitle'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: palette.muted),
                ),
                const SizedBox(height: 28),
                if (!onOtpStep) ...[
                  TextField(
                    controller: _mobile,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    maxLength: 10,
                    decoration: InputDecoration(
                      labelText: l.t('login.mobile'),
                      counterText: '',
                      prefixText: '+91 ',
                      errorText: _mobileError,
                    ),
                  ),
                  const SizedBox(height: 22),
                  Semantics(
                    button: true,
                    enabled: mobileValid && !busy,
                    label: l.t('login.sendOtp'),
                    child: ElevatedButton(
                      // Disabled until a valid 10-digit number is entered, so
                      // the screen-reader also reports it as unavailable.
                      onPressed: (busy || !mobileValid) ? null : _submitMobile,
                      style: mobileValid
                          // Valid input: green, high-contrast filled CTA.
                          ? ElevatedButton.styleFrom(
                              backgroundColor: palette.success,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: palette.success,
                              disabledForegroundColor: Colors.white,
                            )
                          // Invalid input: greyed-out, non-actionable.
                          : ElevatedButton.styleFrom(
                              backgroundColor: palette.chipBg,
                              foregroundColor: palette.muted,
                              disabledBackgroundColor: palette.chipBg,
                              disabledForegroundColor: palette.muted,
                            ),
                      child: busy
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(l.t('login.sendOtp')),
                    ),
                  ),
                ] else ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        l.t('login.otp'),
                        style: TextStyle(
                          color: palette.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  OtpInput(
                    length: config.env.gupshup.otpCodeLength,
                    hasError: _otpError != null,
                    enabled: !busy,
                    onChanged: (value) {
                      _otp.text = value;
                      if (_otpError != null) {
                        setState(() => _otpError = null);
                      }
                    },
                    onCompleted: (_) {
                      if (!busy) _submitOtp();
                    },
                  ),
                  if (_otpError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _otpError!,
                      style: TextStyle(color: palette.danger, fontSize: 12),
                    ),
                  ],
                  Align(
                    alignment: Alignment.centerRight,
                    child: Semantics(
                      button: true,
                      enabled: resendReady,
                      child: TextButton(
                        // Greyed out and non-actionable until the 60s countdown
                        // reaches 0, so the agent can't spam the OTP endpoint.
                        onPressed: resendReady ? _resendOtp : null,
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          foregroundColor: palette.primary,
                          disabledForegroundColor: palette.muted,
                        ),
                        child: Text(
                          resendReady
                              ? l.t('login.resendOtp')
                              : l.t('login.resendOtpIn', {'seconds': '$_resendIn'}),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  ElevatedButton(
                    onPressed: busy ? null : _submitOtp,
                    child: busy
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(l.t('login.verifyOtp')),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: busy ? null : _changeNumber,
                    child: Text(l.t('login.changeNumber')),
                  ),
                ],
                if (config.env.useMockData) ...[
                  const SizedBox(height: 14),
                  Text(
                    l.t('login.demoHint'),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: palette.muted),
                  ),
                ],
                // Failures are shown inline on the field they belong to (mobile
                // or OTP); this banner is only a fallback for the rare error
                // that isn't attached to either.
                if (auth.error != null && !onOtpStep && _mobileError == null) ...[
                  const SizedBox(height: 12),
                  Text(
                    l.t('common.error'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: palette.danger),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
