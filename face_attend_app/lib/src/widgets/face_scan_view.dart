import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

class FaceScanView extends StatelessWidget {
  const FaceScanView({
    required this.message,
    this.camera,
    this.progress,
    this.target,
    this.prompt = 'Look straight and keep your face inside the frame.',
    super.key,
  });

  final CameraController? camera;
  final String message;
  final int? progress;
  final int? target;
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
            CameraPreview(camera!)
          else
            Center(child: Text(message, style: const TextStyle(color: Colors.white))),
          const _FaceGuide(),
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

class _FaceGuide extends StatelessWidget {
  const _FaceGuide();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: Container(
          width: 230,
          height: 300,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white.withValues(alpha: 0.85), width: 3),
            borderRadius: BorderRadius.circular(140),
          ),
        ),
      ),
    );
  }
}

class _ScanPrompt extends StatelessWidget {
  const _ScanPrompt({
    required this.message,
    this.progress,
    this.target,
  });

  final String message;
  final int? progress;
  final int? target;

  @override
  Widget build(BuildContext context) {
    final hasProgress = progress != null && target != null && target! > 0;
    final value = hasProgress ? (progress! / target!).clamp(0.0, 1.0) : null;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.face, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
          if (hasProgress) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(value: value),
            const SizedBox(height: 6),
            Text(
              '$progress/$target samples',
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ],
      ),
    );
  }
}
