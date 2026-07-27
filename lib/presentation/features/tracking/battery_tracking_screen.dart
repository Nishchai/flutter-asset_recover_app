import 'package:asset_recovery_app/core/config/config_service.dart';
import 'package:asset_recovery_app/core/di/injector.dart';
import 'package:asset_recovery_app/core/localization/app_localizations.dart';
import 'package:asset_recovery_app/core/services/api_client.dart';
import 'package:asset_recovery_app/core/theme/app_theme.dart';
import 'package:asset_recovery_app/domain/entities/battery.dart';
import 'package:asset_recovery_app/domain/entities/geo_point.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// In-app live battery-tracking map (Option A). Hosts the backend tracking web
/// page (`env.batteryTrackingUrl`) in a WebView, appending the BP id plus its
/// last-known lat/lng as query params and attaching the SAME Bearer access
/// token the rest of the app uses (minted by `generateAuthToken`, held in
/// [ApiClient.authToken]).
///
/// Opened from the BP detail map icon. Note the token is attached to the
/// INITIAL main-frame request only — WebView cannot inject it onto the
/// sub-requests the page makes itself (map tiles, live-position XHR). If the
/// backend page relies on those carrying auth, it must accept a cookie/session
/// established from the first request, or read the token some other way. This
/// is a platform limitation of header injection, not of this screen.
class BatteryTrackingScreen extends StatefulWidget {
  const BatteryTrackingScreen({
    super.key,
    required this.bp,
    required this.location,
  });

  final Battery bp;

  /// Coordinates to centre the tracking page on — the customer card's "Last
  /// Seen" position (see `resolveLastSeenPoint` in the BP detail screen), passed
  /// through as the `lat`/`lng` query params.
  final GeoPoint location;

  @override
  State<BatteryTrackingScreen> createState() => _BatteryTrackingScreenState();
}

class _BatteryTrackingScreenState extends State<BatteryTrackingScreen> {
  WebViewController? _controller;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  void _init() {
    final base = sl<ConfigService>().env.batteryTrackingUrl;
    if (base.isEmpty) {
      // Feature not configured for this environment; surface it rather than
      // opening a blank WebView.
      _error = 'unconfigured';
      _loading = false;
      return;
    }

    final loc = widget.location;
    final uri = Uri.parse(base).replace(queryParameters: {
      // Preserve any query params already baked into the configured base URL.
      ...Uri.parse(base).queryParameters,
      'batteryId': widget.bp.bpId,
      'lat': loc.lat.toStringAsFixed(8),
      'lng': loc.lng.toStringAsFixed(8),
    },);

    final token = sl<ApiClient>().authToken;
    final headers = <String, String>{
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (!mounted) return;
            setState(() {
              _loading = true;
              _error = null;
            });
          },
          onPageFinished: (_) {
            if (!mounted) return;
            setState(() => _loading = false);
          },
          onWebResourceError: (error) {
            // Only a main-frame failure should blank the page; sub-resource
            // errors (a missing tile, a blocked XHR) must not.
            if (!mounted || !(error.isForMainFrame ?? true)) return;
            setState(() {
              _loading = false;
              _error = error.description;
            });
          },
        ),
      )
      ..loadRequest(uri, headers: headers);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final palette = context.read<AppPalette>();
    final controller = _controller;

    return Scaffold(
      backgroundColor: palette.background,
      appBar: AppBar(
        backgroundColor: palette.primary,
        foregroundColor: palette.onDark,
        title: Text(widget.bp.bpId),
      ),
      body: Stack(
        children: [
          if (controller != null) WebViewWidget(controller: controller),
          if (_error != null)
            _ErrorView(
              message: _error == 'unconfigured'
                  ? l.t('common.error')
                  : _error!,
              palette: palette,
              onRetry: _error == 'unconfigured'
                  ? null
                  : () {
                      setState(() {
                        _error = null;
                        _loading = true;
                      });
                      controller?.reload();
                    },
            )
          else if (_loading)
            const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.message,
    required this.palette,
    required this.onRetry,
  });

  final String message;
  final AppPalette palette;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: palette.background,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.location_off_outlined, size: 48, color: palette.muted),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: palette.muted),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ],
      ),
    );
  }
}
