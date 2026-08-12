import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:helpbee/l10n/app_localizations.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/routing/route_paths.dart';
import '../../../core/text/korean_wrap.dart';
import '../../../core/theme/app_colors.dart';
import 'analysis_flow_args.dart';

/// 카메라 (Figma 49:538): full-screen preview with a honey corner-bracket guide,
/// a capture caption, and gallery / shutter / flash controls.
///
/// Camera state is one of: ready (preview), [_noCamera] (simulator / no device
/// camera — gallery only), or [_initFailed] (transient init error — tap caption
/// to retry). The controller is disposed/recreated across app-lifecycle changes
/// so we never render a disposed controller.
class CaptureScreen extends ConsumerStatefulWidget {
  const CaptureScreen({super.key, required this.args});

  final CaptureArgs args;

  @override
  ConsumerState<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends ConsumerState<CaptureScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  bool _noCamera = false; // device genuinely has no camera (e.g. simulator)
  bool _initFailed = false; // transient init failure — retryable
  bool _initializing = false;
  bool _busy = false;
  FlashMode _flash = FlashMode.off;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      // Release the camera AND drop the reference so build never paints a
      // disposed controller.
      final c = _controller;
      _controller = null;
      c?.dispose();
      if (mounted) setState(() {});
    } else if (state == AppLifecycleState.resumed) {
      // Re-acquire on return (also recovers the gallery-picker round trip).
      if (_controller == null && !_noCamera) _initCamera();
    }
  }

  Future<void> _initCamera() async {
    if (_initializing) return;
    _initializing = true;
    if (mounted && _initFailed) setState(() => _initFailed = false);
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) setState(() => _noCamera = true);
        return;
      }
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await controller.initialize();
      await controller.setFlashMode(_flash);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _noCamera = false;
        _initFailed = false;
      });
    } catch (_) {
      // Permission denied / camera busy / resource contention — recoverable.
      if (mounted) setState(() => _initFailed = true);
    } finally {
      _initializing = false;
    }
  }

  Future<void> _cycleFlash() async {
    final next = switch (_flash) {
      FlashMode.off => FlashMode.auto,
      FlashMode.auto => FlashMode.always,
      _ => FlashMode.off,
    };
    setState(() => _flash = next);
    try {
      await _controller?.setFlashMode(next);
    } catch (_) {
      /* unsupported on some devices */
    }
  }

  Future<void> _shoot() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || _busy) return;
    setState(() => _busy = true);
    try {
      final shot = await c.takePicture();
      _goReview(shot.path);
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickFromGallery() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (picked != null) {
        _goReview(picked.path);
        return;
      }
    } catch (_) {
      /* cancelled / denied */
    }
    if (mounted) setState(() => _busy = false);
  }

  void _goReview(String path) {
    if (!mounted) return;
    context.push(
      RoutePaths.review,
      extra: PhotoArgs(
        hiveId: widget.args.hiveId,
        hiveName: widget.args.hiveName,
        imagePath: path,
      ),
    );
    // Allow re-capture when the user pops back from review.
    setState(() => _busy = false);
  }

  String _captionText(AppLocalizations l10n) {
    if (_noCamera) return keepAll(l10n.captureNoCamera);
    if (_initFailed) return keepAll(l10n.captureCameraRetry);
    return keepAll(l10n.captureGuide);
  }

  String _flashLabel(AppLocalizations l10n) => switch (_flash) {
    FlashMode.off => l10n.captureFlashOff,
    FlashMode.auto => l10n.captureFlashAuto,
    _ => l10n.captureFlashOn,
  };

  IconData _flashIcon() => switch (_flash) {
    FlashMode.off => Icons.flash_off,
    FlashMode.auto => Icons.flash_auto,
    _ => Icons.flash_on,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final controller = _controller;
    final ready = controller != null && controller.value.isInitialized;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (ready)
            FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: controller.value.previewSize?.height ?? 1080,
                height: controller.value.previewSize?.width ?? 1920,
                child: CameraPreview(controller),
              ),
            )
          else
            const ColoredBox(color: Colors.black),

          // Centered honey corner-bracket guide + caption.
          Positioned.fill(
            child: IgnorePointer(child: CustomPaint(painter: _GuidePainter())),
          ),
          Align(
            alignment: const Alignment(0, 0.55),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: GestureDetector(
                onTap: _initFailed ? _initCamera : null,
                child: Text(
                  _captionText(l10n),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    height: 1.4,
                    shadows: [Shadow(blurRadius: 6, color: Colors.black54)],
                  ),
                ),
              ),
            ),
          ),

          // Close (X).
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: IconButton(
                iconSize: 28,
                color: Colors.white,
                tooltip: l10n.captureCloseA11y,
                icon: const Icon(Icons.close),
                onPressed: () => context.pop(),
              ),
            ),
          ),

          // Bottom controls.
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _SideButton(
                      icon: Icons.photo_library_outlined,
                      label: l10n.captureGallery,
                      onTap: _busy ? null : _pickFromGallery,
                    ),
                    _ShutterButton(
                      onTap: (ready && !_busy) ? _shoot : null,
                      busy: _busy,
                    ),
                    _SideButton(
                      icon: _flashIcon(),
                      label: l10n.captureFlash,
                      semanticLabel: _flashLabel(l10n),
                      onTap: ready ? _cycleFlash : null,
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

class _ShutterButton extends StatelessWidget {
  const _ShutterButton({required this.onTap, required this.busy});

  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: AppLocalizations.of(context).captureShutterA11y,
      child: Opacity(
        opacity: onTap == null ? 0.5 : 1,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 78,
            height: 78,
            decoration: const BoxDecoration(
              color: AppColors.honeyPrimary,
              shape: BoxShape.circle,
            ),
            child: busy
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.textPrimary,
                    ),
                  )
                : const Icon(
                    Icons.camera_alt,
                    color: AppColors.textPrimary,
                    size: 32,
                  ),
          ),
        ),
      ),
    );
  }
}

class _SideButton extends StatelessWidget {
  const _SideButton({
    required this.icon,
    required this.label,
    this.semanticLabel,
    this.onTap,
  });

  final IconData icon;
  final String label;

  /// Spoken label (defaults to [label]); use for stateful buttons like flash.
  final String? semanticLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: semanticLabel ?? label,
      child: Opacity(
        opacity: onTap == null ? 0.4 : 1,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: Colors.white, size: 24),
                ),
                const SizedBox(height: 6),
                ExcludeSemantics(
                  child: Text(
                    label,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Four honey L-brackets around a centered rounded frame (the capture guide).
class _GuidePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width * 0.78;
    final h = w * 1.28;
    final left = (size.width - w) / 2;
    final top = (size.height - h) / 2 - size.height * 0.04;
    final rect = Rect.fromLTWH(left, top, w, h);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(24));

    final frame = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRRect(rrect, frame);

    final corner = Paint()
      ..color = AppColors.honeyPrimary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    const len = 34.0;
    const inset = 18.0;
    _bracket(
      canvas,
      corner,
      Offset(rect.left + inset, rect.top + inset),
      dx: 1,
      dy: 1,
      len: len,
    );
    _bracket(
      canvas,
      corner,
      Offset(rect.right - inset, rect.top + inset),
      dx: -1,
      dy: 1,
      len: len,
    );
    _bracket(
      canvas,
      corner,
      Offset(rect.left + inset, rect.bottom - inset),
      dx: 1,
      dy: -1,
      len: len,
    );
    _bracket(
      canvas,
      corner,
      Offset(rect.right - inset, rect.bottom - inset),
      dx: -1,
      dy: -1,
      len: len,
    );
  }

  void _bracket(
    Canvas canvas,
    Paint p,
    Offset o, {
    required int dx,
    required int dy,
    required double len,
  }) {
    canvas.drawLine(o, o.translate(dx * len, 0), p);
    canvas.drawLine(o, o.translate(0, dy * len), p);
  }

  @override
  bool shouldRepaint(_GuidePainter oldDelegate) => false;
}
