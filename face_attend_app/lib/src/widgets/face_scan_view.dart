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
            Center(
              child: Text(message, style: const TextStyle(color: Colors.white)),
            ),
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

class _FaceGuide extends StatefulWidget {
  const _FaceGuide();

  @override
  State<_FaceGuide> createState() => _FaceGuideState();
}

class _FaceGuideState extends State<_FaceGuide>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _animation = Tween<double>(
      begin: 0.98,
      end: 1.04,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: AnimatedBuilder(
          animation: _animation,
          builder: (context, child) {
            return Transform.scale(
              scale: _animation.value,
              child: Container(
                width: 220,
                height: 290,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: const Color(0xFFFF6B35),
                    width: 3.5,
                  ),
                  borderRadius: BorderRadius.circular(145),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFF6B35).withValues(alpha: 0.25),
                      blurRadius: 15,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    // Corner targeting notches
                    Positioned(
                      top: 40,
                      left: 10,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    Positioned(
                      top: 40,
                      right: 10,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
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
                  color: const Color(0xFFFF6B35).withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.face,
                  color: Color(0xFFFF6B35),
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
                  Color(0xFFFF6B35),
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
                    color: Color(0xFFFFC107),
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
