import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class FaceScanView extends StatelessWidget {
  const FaceScanView({
    required this.message,
    this.camera,
    this.progress,
    this.target,
    this.faceBounds,
    this.faceImageSize,
    this.faceOverlays = const [],
    this.faceReady = false,
    this.prompt = 'Look straight and keep your face inside the frame.',
    super.key,
  });

  final CameraController? camera;
  final String message;
  final int? progress;
  final int? target;
  final Rect? faceBounds;
  final Size? faceImageSize;
  final List<FaceOverlay> faceOverlays;
  final bool faceReady;
  final String prompt;

  @override
  Widget build(BuildContext context) {
    final initialized = camera != null && camera!.value.isInitialized;
    return Container(
      width: double.infinity,
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (initialized)
            _CameraPreviewCover(camera: camera!)
          else
            Center(
              child: Text(message, style: const TextStyle(color: Colors.white)),
            ),
          _FaceGuide(
            faceBounds: faceBounds,
            faceOverlays: faceOverlays,
            imageSize: faceImageSize,
            isFrontCamera:
                camera?.description.lensDirection == CameraLensDirection.front,
            ready: faceReady,
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: _ScanPrompt(
              message: initialized ? prompt : message,
              progress: progress,
              target: target,
            ),
          ),
        ],
      ),
    );
  }
}

class _CameraPreviewCover extends StatelessWidget {
  const _CameraPreviewCover({required this.camera});

  final CameraController camera;

  @override
  Widget build(BuildContext context) {
    final previewSize = camera.value.previewSize;
    if (previewSize == null) {
      return CameraPreview(camera);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final portrait = constraints.maxHeight >= constraints.maxWidth;
        final previewWidth = portrait ? previewSize.height : previewSize.width;
        final previewHeight = portrait ? previewSize.width : previewSize.height;

        return ClipRect(
          child: OverflowBox(
            maxWidth: double.infinity,
            maxHeight: double.infinity,
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: previewWidth,
                height: previewHeight,
                child: CameraPreview(camera),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _FaceGuide extends StatelessWidget {
  const _FaceGuide({
    required this.faceBounds,
    required this.faceOverlays,
    required this.imageSize,
    required this.isFrontCamera,
    required this.ready,
  });

  final Rect? faceBounds;
  final List<FaceOverlay> faceOverlays;
  final Size? imageSize;
  final bool isFrontCamera;
  final bool ready;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _FaceGuidePainter(
          faceBounds: faceBounds,
          faceOverlays: faceOverlays,
          imageSize: imageSize,
          isFrontCamera: isFrontCamera,
          ready: ready,
        ),
      ),
    );
  }
}

class _FaceGuidePainter extends CustomPainter {
  const _FaceGuidePainter({
    required this.faceBounds,
    required this.faceOverlays,
    required this.imageSize,
    required this.isFrontCamera,
    required this.ready,
  });

  final Rect? faceBounds;
  final List<FaceOverlay> faceOverlays;
  final Size? imageSize;
  final bool isFrontCamera;
  final bool ready;

  @override
  void paint(Canvas canvas, Size size) {
    final sourceSize = imageSize;
    if (sourceSize == null) return;
    if (faceOverlays.isEmpty && faceBounds == null) return;
    final boxes = faceOverlays.isNotEmpty
        ? faceOverlays
        : [FaceOverlay(bounds: faceBounds!, label: null, ready: ready)];

    final scale = math.max(
      size.width / sourceSize.width,
      size.height / sourceSize.height,
    );
    final dx = (size.width - sourceSize.width * scale) / 2;
    final dy = (size.height - sourceSize.height * scale) / 2;

    for (final overlay in boxes) {
      final box = overlay.bounds;
      var left = box.left * scale + dx;
      final top = box.top * scale + dy;
      var right = box.right * scale + dx;
      final bottom = box.bottom * scale + dy;
      if (isFrontCamera) {
        final mirroredLeft = size.width - right;
        right = size.width - left;
        left = mirroredLeft;
      }

      final rect = Rect.fromLTRB(left, top, right, bottom).inflate(18);
      final color = overlay.ready
          ? FaceAttendColors.success
          : FaceAttendColors.warning;
      final boxPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..color = color;
      final glowPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..color = color.withValues(alpha: 0.18);

      canvas.drawOval(rect, glowPaint);
      canvas.drawOval(rect, boxPaint);
      if (overlay.label != null && overlay.label!.isNotEmpty) {
        _drawLabel(canvas, rect, overlay.label!, color);
      }
    }
  }

  void _drawLabel(Canvas canvas, Rect rect, String label, Color color) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '...',
    )..layout(maxWidth: 180);
    final labelRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        rect.left,
        math.max(8, rect.top - textPainter.height - 12),
        textPainter.width + 18,
        textPainter.height + 10,
      ),
      const Radius.circular(14),
    );
    final fill = Paint()..color = FaceAttendColors.overlay;
    canvas.drawRRect(labelRect, fill);
    textPainter.paint(canvas, Offset(labelRect.left + 9, labelRect.top + 5));
  }

  @override
  bool shouldRepaint(covariant _FaceGuidePainter oldDelegate) =>
      oldDelegate.faceBounds != faceBounds ||
      oldDelegate.faceOverlays != faceOverlays ||
      oldDelegate.imageSize != imageSize ||
      oldDelegate.isFrontCamera != isFrontCamera ||
      oldDelegate.ready != ready;
}

class FaceOverlay {
  const FaceOverlay({required this.bounds, required this.ready, this.label});

  final Rect bounds;
  final bool ready;
  final String? label;
}

class _ScanPrompt extends StatelessWidget {
  const _ScanPrompt({required this.message, this.progress, this.target});

  final String message;
  final int? progress;
  final int? target;

  @override
  Widget build(BuildContext context) {
    final hasProgress = progress != null && target != null && target! > 0;
    final value = hasProgress ? (progress! / target!).clamp(0.0, 1.0) : null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: FaceAttendColors.overlay,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: FaceAttendColors.accentSoft,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.face,
                  color: FaceAttendColors.accent,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (hasProgress) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: value,
                minHeight: 6,
                backgroundColor: Colors.white12,
                valueColor: const AlwaysStoppedAnimation<Color>(
                  FaceAttendColors.accent,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Biometric capture progress',
                  style: TextStyle(color: Colors.white38, fontSize: 11),
                ),
                Text(
                  '$progress/$target captured',
                  style: const TextStyle(
                    color: FaceAttendColors.warning,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
