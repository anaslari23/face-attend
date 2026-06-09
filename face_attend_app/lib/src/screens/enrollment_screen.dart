import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../api/odoo_face_attendance_client.dart';
import '../models/session.dart';
import '../screens/result_screen.dart';
import '../services/device_service.dart';
import '../services/face_recognition_service.dart';
import '../widgets/face_scan_view.dart';

class EnrollmentScreen extends StatefulWidget {
  const EnrollmentScreen({required this.session, super.key});

  final MobileSession session;

  @override
  State<EnrollmentScreen> createState() => _EnrollmentScreenState();
}

class _EnrollmentScreenState extends State<EnrollmentScreen> {
  final _faceService = FaceRecognitionService();
  final _deviceService = DeviceService();
  final List<List<double>> _embeddings = [];
  static const _targetSamples = 3;
  CameraController? _camera;
  String _message = 'Scan your face to register.';
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      final front = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      _camera = CameraController(front, ResolutionPreset.medium, enableAudio: false);
      await _camera!.initialize();
      if (!mounted) return;
      setState(() => _busy = false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = error.toString();
      });
    }
  }

  @override
  void dispose() {
    _camera?.dispose();
    _faceService.close();
    super.dispose();
  }

  Future<void> _capture() async {
    final camera = _camera;
    if (camera == null || !camera.value.isInitialized) return;
    setState(() => _busy = true);
    try {
      final image = await camera.takePicture();
      final result = await _faceService.validateAndEmbed(image.path);
      if (!result.valid) {
        setState(() {
          _message = result.error ?? 'Face validation failed';
          _busy = false;
        });
        return;
      }
      _embeddings.add(result.embedding!);
      if (_embeddings.length < _targetSamples) {
        setState(() {
          _message = '${_embeddings.length}/$_targetSamples samples captured.';
          _busy = false;
        });
        return;
      }
      final device = await _deviceService.identity();
      final client = OdooFaceAttendanceClient(baseUrl: widget.session.baseUrl, db: widget.session.db, token: widget.session.token);
      await client.enroll(
        embeddings: _embeddings,
        modelVersion: FaceRecognitionService.modelVersion,
        deviceId: device.id,
        qualityScore: 1.0,
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const AttendanceResultScreen(
            success: true,
            title: 'Face registered',
            message: 'Your face registration was completed successfully.',
            showRetry: false,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _message = error.toString();
        _busy = false;
      });
    }
  }

  String get _currentPrompt {
    if (_busy) return 'Processing biometric data...';
    switch (_embeddings.length) {
      case 0:
        return 'Step 1: Look straight with a neutral expression.';
      case 1:
        return 'Step 2: Turn slightly or adjust lighting conditions.';
      case 2:
        return 'Step 3: Smile or blink to verify liveness.';
      default:
        return 'Registration complete!';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('Enroll Face Biometrics'),
      ),
      body: Column(
        children: [
          Expanded(
            child: FaceScanView(
              camera: _camera,
              message: _message,
              progress: _embeddings.length,
              target: _targetSamples,
              prompt: _currentPrompt,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Enrollment Checklist / Indicators
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(_targetSamples, (index) {
                    final isCaptured = index < _embeddings.length;
                    final isCurrent = index == _embeddings.length;
                    return Container(
                      width: 44,
                      height: 8,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: isCaptured
                            ? const Color(0xFF2ECC71)
                            : isCurrent
                                ? const Color(0xFFFF6B35)
                                : Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 18),
                Text(
                  _message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: _busy
                        ? null
                        : const LinearGradient(
                            colors: [Color(0xFFFF6B35), Color(0xFFFFC107)],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                    color: _busy ? Colors.grey.shade300 : null,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: _busy
                        ? null
                        : [
                            BoxShadow(
                              color: const Color(0xFFFF6B35).withValues(alpha: 0.25),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                  ),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _busy ? null : _capture,
                    child: _busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFFFF6B35),
                            ),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.camera_alt, color: Colors.white),
                              const SizedBox(width: 8),
                              Text(
                                _embeddings.length >= _targetSamples - 1 ? 'Finish Registration' : 'Capture Sample',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
