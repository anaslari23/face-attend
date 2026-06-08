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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Enroll Face')),
      body: Column(
        children: [
          Expanded(
            child: FaceScanView(
              camera: _camera,
              message: _message,
              progress: _embeddings.length,
              target: _targetSamples,
              prompt: 'Move slowly and keep your face inside the frame.',
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(_message, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _busy ? null : _capture,
                  icon: _busy
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.camera_alt),
                  label: Text(_embeddings.length >= _targetSamples - 1 ? 'Finish Registration' : 'Capture Sample'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
