import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

class FaceScanView extends StatefulWidget {
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
  State<FaceScanView> createState() => _FaceScanViewState();
}

class _FaceScanViewState extends State<FaceScanView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scanController;

  @override
  void initState() {
    super.initState();
    _scanController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _scanController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final initialized = widget.camera != null && widget.camera!.value.isInitialized;
    return Container(
      width: double.infinity,
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (initialized)
            _CameraPreviewCover(camera: widget.camera!)
          else
            Center(
              child: Text(widget.message, style: const TextStyle(color: Colors.white)),
            ),
          AnimatedBuilder(
            animation: _scanController,
            builder: (context, child) {
              return _FaceGuide(
                faceBounds: widget.faceBounds,
                faceOverlays: widget.faceOverlays,
                imageSize: widget.faceImageSize,
                isFrontCamera: widget.camera?.description.lensDirection ==
                    CameraLensDirection.front,
                ready: widget.faceReady,
                animationValue: _scanController.value,
              );
            },
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: _ScanPrompt(
              message: initialized ? widget.prompt : widget.message,
              progress: widget.progress,
              target: widget.target,
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
    required this.animationValue,
  });

  final Rect? faceBounds;
  final List<FaceOverlay> faceOverlays;
  final Size? imageSize;
  final bool isFrontCamera;
  final bool ready;
  final double animationValue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scanColor = theme.primaryColor;

    return IgnorePointer(
      child: CustomPaint(
        painter: _FaceGuidePainter(
          faceBounds: faceBounds,
          faceOverlays: faceOverlays,
          imageSize: imageSize,
          isFrontCamera: isFrontCamera,
          ready: ready,
          animationValue: animationValue,
          scanColor: scanColor,
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
    required this.animationValue,
    required this.scanColor,
  });

  final Rect? faceBounds;
  final List<FaceOverlay> faceOverlays;
  final Size? imageSize;
  final bool isFrontCamera;
  final bool ready;
  final double animationValue;
  final Color scanColor;

  @override
  void paint(Canvas canvas, Size size) {
    final bool isFaceDetected = faceBounds != null && imageSize != null;

    // Do not show the circular guide at the very first before a face is detected
    if (!isFaceDetected) {
      return;
    }

    // Scale factors to map camera image coordinates to preview size coordinates
    final double scale = math.max(size.width / imageSize!.width, size.height / imageSize!.height);
    final double offsetX = (size.width - imageSize!.width * scale) / 2;
    final double offsetY = (size.height - imageSize!.height * scale) / 2;

    double left = faceBounds!.left * scale + offsetX;
    double right = faceBounds!.right * scale + offsetX;
    
    if (isFrontCamera) {
      // Horizontally mirror the X coordinates for front camera
      final double mirroredLeft = size.width - right;
      final double mirroredRight = size.width - left;
      left = mirroredLeft;
      right = mirroredRight;
    }

    final double top = faceBounds!.top * scale + offsetY;
    final double bottom = faceBounds!.bottom * scale + offsetY;
    
    final Rect faceRect = Rect.fromLTRB(left, top, right, bottom);
    
    // Clamp values to ensure circle stays beautifully on screen
    final double calculatedRadius = math.max(faceRect.width, faceRect.height) * 0.65;
    final double radius = calculatedRadius.clamp(size.width * 0.20, size.width * 0.45);
    
    final Offset center = Offset(
      faceRect.center.dx.clamp(radius + 10, size.width - radius - 10),
      faceRect.center.dy.clamp(radius + 10, size.height - radius - 10),
    );

    final Color color = ready ? const Color(0xFF30D158) : scanColor;

    final cutoutPath = Path()..addOval(Rect.fromCircle(center: center, radius: radius));

    // Draw thin circular border
    final borderPaint = Paint()
      ..color = color.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;
    canvas.drawCircle(center, radius, borderPaint);



    // Draw label
    final String labelText = ready 
        ? "MATCHED" 
        : (isFaceDetected || faceOverlays.isNotEmpty ? "SCANNING..." : "ALIGN FACE");
    _drawLabel(canvas, center, radius, labelText, color);
  }

  void _drawLabel(Canvas canvas, Offset center, double radius, String label, Color color) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '...',
    )..layout(maxWidth: 180);
    
    final labelRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        center.dx - (textPainter.width + 18) / 2, // Centered label
        math.max(8, center.dy - radius - textPainter.height - 18),
        textPainter.width + 18,
        textPainter.height + 10,
      ),
      const Radius.circular(10),
    );
    final fill = Paint()..color = color.withValues(alpha: 0.9);
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
      oldDelegate.animationValue != animationValue ||
      oldDelegate.scanColor != scanColor;
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
        color: const Color(0xFF1E1E1E).withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF30D158).withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.face,
                  color: Color(0xFF30D158),
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
                    fontWeight: FontWeight.bold,
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
                  Color(0xFF30D158),
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
                    color: Color(0xFF30D158),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
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
