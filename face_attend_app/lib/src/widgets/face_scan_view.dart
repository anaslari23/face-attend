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

class _FaceGuide extends StatefulWidget {
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
  State<_FaceGuide> createState() => _FaceGuideState();
}

class _FaceGuideState extends State<_FaceGuide> with SingleTickerProviderStateMixin {
  late final AnimationController _rotationController;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _rotationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _rotationController,
        builder: (context, child) {
          return CustomPaint(
            painter: _FaceGuidePainter(
              faceBounds: widget.faceBounds,
              faceOverlays: widget.faceOverlays,
              imageSize: widget.imageSize,
              isFrontCamera: widget.isFrontCamera,
              ready: widget.ready,
              animationValue: _rotationController.value,
            ),
          );
        },
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
    required this.animationValue,
  });

  final Rect? faceBounds;
  final List<FaceOverlay> faceOverlays;
  final Size? imageSize;
  final bool isFrontCamera;
  final bool ready;
  final double animationValue;

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

      final baseRect = Rect.fromLTRB(left, top, right, bottom);
      // Face detection bounding boxes usually crop tightly around the eyes, nose, and mouth.
      // To cover the full face (hairline to chin, ear to ear), we expand the width and height
      // and shift the center slightly upward.
      final double widthExpansion = baseRect.width * 0.22; // 22% wider on each side
      final double heightExpansion = baseRect.height * 0.38; // 38% taller
      final rect = Rect.fromLTRB(
        baseRect.left - widthExpansion,
        baseRect.top - heightExpansion * 1.35, // shift upwards more to cover forehead/hair
        baseRect.right + widthExpansion,
        baseRect.bottom + heightExpansion * 0.65, // downward to chin
      );

      final color = overlay.ready
          ? FaceAttendColors.success
          : Colors.white;

      _drawMeshTracker(canvas, rect, color, overlay.ready);

      if (overlay.label != null && overlay.label!.isNotEmpty) {
        _drawLabel(canvas, rect, overlay.label!, color);
      }
    }
  }

  void _drawMeshTracker(Canvas canvas, Rect rect, Color color, bool isReady) {
    final center = rect.center;
    final double radiusX = rect.width / 2;
    final double radiusY = rect.height / 2;

    // 1. Draw Bounding Box Corner Brackets (Blocks)
    // When ready, we can use a slightly thicker stroke to emphasize the lock
    final bracketPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = isReady ? 4.5 : 3.0
      ..strokeCap = StrokeCap.square
      ..color = color;

    final outerRect = rect.inflate(10);
    final double bracketLength = outerRect.width * 0.12;

    // Top-Left
    canvas.drawPath(
      Path()
        ..moveTo(outerRect.left, outerRect.top + bracketLength)
        ..lineTo(outerRect.left, outerRect.top)
        ..lineTo(outerRect.left + bracketLength, outerRect.top),
      bracketPaint,
    );
    // Top-Right
    canvas.drawPath(
      Path()
        ..moveTo(outerRect.right - bracketLength, outerRect.top)
        ..lineTo(outerRect.right, outerRect.top)
        ..lineTo(outerRect.right, outerRect.top + bracketLength),
      bracketPaint,
    );
    // Bottom-Left
    canvas.drawPath(
      Path()
        ..moveTo(outerRect.left, outerRect.bottom - bracketLength)
        ..lineTo(outerRect.left, outerRect.bottom)
        ..lineTo(outerRect.left + bracketLength, outerRect.bottom),
      bracketPaint,
    );
    // Bottom-Right
    canvas.drawPath(
      Path()
        ..moveTo(outerRect.right - bracketLength, outerRect.bottom)
        ..lineTo(outerRect.right, outerRect.bottom)
        ..lineTo(outerRect.right, outerRect.bottom - bracketLength),
      bracketPaint,
    );

    // 2. Define the Face Mesh coordinates
    // When not ready, add minor dynamic jitter to mimic OpenCV searching/detecting jitter.
    final double jitterAmount = isReady ? 0.2 : 1.3;

    Offset getPoint(double dx, double dy, {double phase = 0}) {
      final double jitterX = math.sin(animationValue * 2 * math.pi * 3 + phase) * jitterAmount;
      final double jitterY = math.cos(animationValue * 2 * math.pi * 2.5 + phase) * jitterAmount;
      return Offset(
        center.dx + (dx * radiusX) + jitterX,
        center.dy + (dy * radiusY) + jitterY,
      );
    }

    // Facial Contour Boundary (16 points)
    final contour = [
      getPoint(-0.40, -0.45, phase: 1.0),
      getPoint(-0.20, -0.52, phase: 1.1),
      getPoint(0.00, -0.55, phase: 1.2),
      getPoint(0.20, -0.52, phase: 1.3),
      getPoint(0.40, -0.45, phase: 1.4),
      getPoint(0.48, -0.20, phase: 1.5),
      getPoint(0.50, 0.00, phase: 1.6),
      getPoint(0.46, 0.22, phase: 1.7),
      getPoint(0.35, 0.38, phase: 1.8),
      getPoint(0.18, 0.48, phase: 1.9),
      getPoint(0.00, 0.52, phase: 2.0),
      getPoint(-0.18, 0.48, phase: 2.1),
      getPoint(-0.35, 0.38, phase: 2.2),
      getPoint(-0.46, 0.22, phase: 2.3),
      getPoint(-0.50, 0.00, phase: 2.4),
      getPoint(-0.48, -0.20, phase: 2.5),
    ];

    // Eyebrows
    final leftEyebrow = [
      getPoint(-0.35, -0.25, phase: 3.0),
      getPoint(-0.24, -0.28, phase: 3.1),
      getPoint(-0.10, -0.25, phase: 3.2),
    ];
    final rightEyebrow = [
      getPoint(0.10, -0.25, phase: 3.3),
      getPoint(0.24, -0.28, phase: 3.4),
      getPoint(0.35, -0.25, phase: 3.5),
    ];

    // Eyes
    final leftEye = [
      getPoint(-0.30, -0.12, phase: 4.0),
      getPoint(-0.21, -0.16, phase: 4.1),
      getPoint(-0.12, -0.12, phase: 4.2),
      getPoint(-0.21, -0.08, phase: 4.3),
    ];
    final rightEye = [
      getPoint(0.12, -0.12, phase: 4.4),
      getPoint(0.21, -0.16, phase: 4.5),
      getPoint(0.30, -0.12, phase: 4.6),
      getPoint(0.21, -0.08, phase: 4.7),
    ];

    // Nose
    final noseBridge = [
      getPoint(0.00, -0.25, phase: 5.0),
      getPoint(0.00, -0.05, phase: 5.1),
      getPoint(0.00, 0.10, phase: 5.2),
    ];
    final noseWings = [
      getPoint(-0.08, 0.08, phase: 5.3),
      getPoint(0.08, 0.08, phase: 5.4),
    ];

    // Mouth
    final mouth = [
      getPoint(-0.16, 0.25, phase: 6.0),
      getPoint(0.00, 0.20, phase: 6.1),
      getPoint(0.16, 0.25, phase: 6.2),
      getPoint(0.00, 0.29, phase: 6.3),
    ];

    // Cheeks & Forehead inner mesh anchors
    final foreheadMidL = getPoint(-0.15, -0.38, phase: 7.0);
    final foreheadMidR = getPoint(0.15, -0.38, phase: 7.1);
    final cheekInnerL = getPoint(-0.18, 0.05, phase: 7.2);
    final cheekInnerR = getPoint(0.18, 0.05, phase: 7.3);
    final cheekOuterL = getPoint(-0.33, 0.06, phase: 7.4);
    final cheekOuterR = getPoint(0.33, 0.06, phase: 7.5);

    // 3. Draw Facial Wireframe Connections (Lines)
    final double breathingValue = (math.sin(animationValue * 2 * math.pi) + 1.0) / 2.0;
    final double lineAlpha = isReady ? 0.55 : 0.25 + (breathingValue * 0.15);
    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = isReady ? 1.2 : 0.8
      ..color = color.withValues(alpha: lineAlpha);

    void drawLine(Offset p1, Offset p2) {
      canvas.drawLine(p1, p2, linePaint);
    }

    void drawPathLoop(List<Offset> points) {
      for (int i = 0; i < points.length; i++) {
        drawLine(points[i], points[(i + 1) % points.length]);
      }
    }

    void drawPathOpen(List<Offset> points) {
      for (int i = 0; i < points.length - 1; i++) {
        drawLine(points[i], points[i + 1]);
      }
    }

    // Outer boundaries and shapes
    drawPathLoop(contour);
    drawPathOpen(leftEyebrow);
    drawPathOpen(rightEyebrow);
    drawPathLoop(leftEye);
    drawPathLoop(rightEye);
    drawPathOpen(noseBridge);
    drawLine(noseBridge[2], noseWings[0]);
    drawLine(noseBridge[2], noseWings[1]);
    drawLine(noseBridge[1], noseWings[0]);
    drawLine(noseBridge[1], noseWings[1]);
    drawPathLoop(mouth);

    // Structural connecting lines
    drawLine(contour[2], foreheadMidL);
    drawLine(contour[2], foreheadMidR);
    drawLine(contour[1], foreheadMidL);
    drawLine(contour[3], foreheadMidR);
    drawLine(contour[0], foreheadMidL);
    drawLine(contour[4], foreheadMidR);
    drawLine(foreheadMidL, leftEyebrow[1]);
    drawLine(foreheadMidR, rightEyebrow[1]);
    drawLine(foreheadMidL, noseBridge[0]);
    drawLine(foreheadMidR, noseBridge[0]);

    drawLine(leftEyebrow[2], noseBridge[0]);
    drawLine(rightEyebrow[0], noseBridge[0]);

    drawLine(leftEyebrow[0], leftEye[1]);
    drawLine(leftEyebrow[1], leftEye[1]);
    drawLine(leftEyebrow[2], leftEye[1]);
    drawLine(rightEyebrow[0], rightEye[1]);
    drawLine(rightEyebrow[1], rightEye[1]);
    drawLine(rightEyebrow[2], rightEye[1]);

    drawLine(contour[15], leftEye[0]);
    drawLine(contour[5], rightEye[2]);
    drawLine(contour[14], cheekOuterL);
    drawLine(contour[6], cheekOuterR);
    drawLine(cheekOuterL, leftEye[0]);
    drawLine(cheekOuterR, rightEye[2]);

    drawLine(leftEye[3], cheekInnerL);
    drawLine(leftEye[3], cheekOuterL);
    drawLine(rightEye[3], cheekInnerR);
    drawLine(rightEye[3], cheekOuterR);
    drawLine(leftEye[2], noseBridge[1]);
    drawLine(rightEye[0], noseBridge[1]);

    drawLine(noseWings[0], cheekInnerL);
    drawLine(noseWings[1], cheekInnerR);

    drawLine(cheekInnerL, mouth[0]);
    drawLine(cheekInnerR, mouth[2]);
    drawLine(cheekOuterL, contour[13]);
    drawLine(cheekOuterR, contour[7]);
    drawLine(cheekOuterL, mouth[0]);
    drawLine(cheekOuterR, mouth[2]);
    drawLine(cheekInnerL, cheekOuterL);
    drawLine(cheekInnerR, cheekOuterR);

    drawLine(mouth[0], contour[12]);
    drawLine(mouth[2], contour[8]);
    drawLine(mouth[3], contour[10]);
    drawLine(mouth[0], contour[11]);
    drawLine(mouth[2], contour[9]);

    // 4. Draw Landmark Nodes (Dots)
    final double dotAlpha = isReady ? 0.9 : 0.65 + (breathingValue * 0.25);
    final dotPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = color.withValues(alpha: dotAlpha);

    final dotGlow = Paint()
      ..style = PaintingStyle.fill
      ..color = color.withValues(alpha: 0.3 * dotAlpha);

    void drawDot(Offset point) {
      canvas.drawCircle(point, isReady ? 4.5 : 3.5, dotGlow);
      canvas.drawCircle(point, isReady ? 2.2 : 1.8, dotPaint);
    }

    final allPoints = [
      ...contour,
      ...leftEyebrow,
      ...rightEyebrow,
      ...leftEye,
      ...rightEye,
      ...noseBridge,
      ...noseWings,
      ...mouth,
      foreheadMidL,
      foreheadMidR,
      cheekInnerL,
      cheekInnerR,
      cheekOuterL,
      cheekOuterR,
    ];

    for (final p in allPoints) {
      drawDot(p);
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
      oldDelegate.ready != ready ||
      oldDelegate.animationValue != animationValue;
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
