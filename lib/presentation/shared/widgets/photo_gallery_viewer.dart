import 'package:flutter/material.dart';

/// Full-screen, gallery-style viewer for a set of network photos.
///
/// Behaves like the device gallery: tap a thumbnail to open it full-bleed on
/// black, pinch (or double-tap) to zoom and pan, and swipe left/right to move
/// between the other photos of the same set.
///
/// Page swiping is disabled while a photo is zoomed in so the pan gesture stays
/// with [InteractiveViewer] instead of flipping to the next photo mid-pan.
class PhotoGalleryViewer extends StatefulWidget {
  const PhotoGalleryViewer({
    super.key,
    required this.urls,
    this.initialIndex = 0,
    this.heroTagPrefix,
  });

  /// Every photo of the set, in display order.
  final List<String> urls;

  /// Index within [urls] of the photo that was tapped.
  final int initialIndex;

  /// When the thumbnails are wrapped in `Hero` widgets, the same prefix passed
  /// there — tags are built as `'<prefix>-<index>'` so the tapped thumbnail
  /// animates into the full-screen photo. Null disables the Hero animation.
  final String? heroTagPrefix;

  /// Hero tag for photo [index] of the set identified by [prefix]. Thumbnails
  /// and the viewer must agree on this, hence the shared helper.
  static Object heroTag(String prefix, int index) => 'photo-$prefix-$index';

  /// Pushes the viewer over the current route, fading in over the content
  /// below rather than sliding in like a normal page.
  static Future<void> open(
    BuildContext context, {
    required List<String> urls,
    int initialIndex = 0,
    String? heroTagPrefix,
  }) {
    if (urls.isEmpty) return Future<void>.value();
    return Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.black,
        transitionDuration: const Duration(milliseconds: 220),
        reverseTransitionDuration: const Duration(milliseconds: 180),
        pageBuilder: (_, __, ___) => PhotoGalleryViewer(
          urls: urls,
          initialIndex: initialIndex,
          heroTagPrefix: heroTagPrefix,
        ),
        transitionsBuilder: (_, animation, __, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  State<PhotoGalleryViewer> createState() => _PhotoGalleryViewerState();
}

class _PhotoGalleryViewerState extends State<PhotoGalleryViewer> {
  late final PageController _pages;

  /// Shared across pages: swiping is only possible while every page sits at
  /// identity (see [_zoomed]), so one controller cannot leak a transform onto
  /// a neighbouring photo.
  final TransformationController _zoom = TransformationController();

  late int _index;

  /// True while the current photo is scaled past 1× — suppresses page swiping.
  bool _zoomed = false;

  static const double _maxScale = 5;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.urls.length - 1);
    _pages = PageController(initialPage: _index);
    _zoom.addListener(_onZoomChanged);
  }

  @override
  void dispose() {
    _zoom
      ..removeListener(_onZoomChanged)
      ..dispose();
    _pages.dispose();
    super.dispose();
  }

  void _onZoomChanged() {
    final zoomed = _zoom.value.getMaxScaleOnAxis() > 1.01;
    if (zoomed != _zoomed) setState(() => _zoomed = zoomed);
  }

  /// Double-tap toggles between fit-to-screen and 2.5× centred on the tap.
  void _toggleZoom(TapDownDetails details) {
    if (_zoomed) {
      _zoom.value = Matrix4.identity();
      return;
    }
    const scale = 2.5;
    final p = details.localPosition;
    _zoom.value = Matrix4.identity()
      ..translateByDouble(-p.dx * (scale - 1), -p.dy * (scale - 1), 0, 1)
      ..scaleByDouble(scale, scale, scale, 1);
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.urls.length;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pages,
            itemCount: total,
            physics: _zoomed
                ? const NeverScrollableScrollPhysics()
                : const PageScrollPhysics(),
            onPageChanged: (i) {
              _zoom.value = Matrix4.identity();
              setState(() => _index = i);
            },
            itemBuilder: (context, i) {
              final image = _ViewerImage(url: widget.urls[i]);
              return GestureDetector(
                onDoubleTapDown: i == _index ? _toggleZoom : null,
                // Swallows the double-tap so it does not fall through to the
                // dismiss handler below.
                onDoubleTap: () {},
                child: InteractiveViewer(
                  transformationController: i == _index ? _zoom : null,
                  maxScale: _maxScale,
                  child: Center(
                    child: widget.heroTagPrefix == null
                        ? image
                        : Hero(
                            tag: PhotoGalleryViewer.heroTag(
                                widget.heroTagPrefix!, i,),
                            child: image,
                          ),
                  ),
                ),
              );
            },
          ),
          // Close button + "2 / 3" counter, over the photo.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    _CircleIconButton(
                      icon: Icons.close,
                      onPressed: () => Navigator.of(context).pop(),
                      tooltip: MaterialLocalizations.of(context)
                          .closeButtonTooltip,
                    ),
                    const Spacer(),
                    if (total > 1)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6,),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${_index + 1} / $total',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The photo itself: sized to fit the screen, with progress and error states
/// that stay legible on the black backdrop.
class _ViewerImage extends StatelessWidget {
  const _ViewerImage({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) => Image.network(
        url,
        // Both axes unbounded so the incoming (screen-sized) constraints win
        // and `contain` letterboxes tall photos instead of overflowing.
        fit: BoxFit.contain,
        width: double.infinity,
        height: double.infinity,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          final expected = progress.expectedTotalBytes;
          return Center(
            child: SizedBox(
              width: 34,
              height: 34,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Colors.white70,
                value: expected == null || expected == 0
                    ? null
                    : progress.cumulativeBytesLoaded / expected,
              ),
            ),
          );
        },
        errorBuilder: (context, error, stack) => const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.broken_image_outlined, color: Colors.white54, size: 44),
              SizedBox(height: 10),
              Text('Photo unavailable',
                  style: TextStyle(color: Colors.white54, fontSize: 13),),
            ],
          ),
        ),
      );
}

/// Translucent round button used for the viewer's close affordance.
class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({
    required this.icon,
    required this.onPressed,
    required this.tooltip,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.black.withValues(alpha: 0.55),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: IconButton(
          icon: Icon(icon, color: Colors.white, size: 22),
          tooltip: tooltip,
          onPressed: onPressed,
        ),
      );
}
