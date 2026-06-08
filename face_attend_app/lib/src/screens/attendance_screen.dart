import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../api/odoo_face_attendance_client.dart';
import '../models/session.dart';
import '../services/device_service.dart';
import '../services/face_recognition_service.dart';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({required this.session, super.key});

  final MobileSession session;

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  final _faceService = FaceRecognitionService();
  final _deviceService = DeviceService();
  late final OdooFaceAttendanceClient _client;
  CameraController? _camera;
  FaceTemplate? _template;
  String _message = 'Loading face template...';
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _client = OdooFaceAttendanceClient(baseUrl: widget.session.baseUrl, db: widget.session.db, token: widget.session.token);
    _init();
  }

  Future<void> _init() async {
    try {
      _template = await _client.template();
      if (_template == null) {
        setState(() {
          _message = 'Enroll your face before attendance scan.';
          _busy = false;
        });
        return;
      }
      final cameras = await availableCameras();
      final front = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      _camera = CameraController(front, ResolutionPreset.medium, enableAudio: false);
      await _camera!.initialize();
      if (!mounted) return;
      setState(() {
        _message = 'Position your face and scan.';
        _busy = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _message = error.toString();
        _busy = false;
      });
    }
  }

  @override
  void dispose() {
    _camera?.dispose();
    _faceService.close();
    super.dispose();
  }

  Future<void> _scan() async {
    final camera = _camera;
    final template = _template;
    if (camera == null || template == null || !camera.value.isInitialized) return;
    setState(() => _busy = true);
    try {
      final image = await camera.takePicture();
      final result = await _faceService.validateAndEmbed(image.path);
      if (!result.valid) {
        await _submitRejected(template.threshold, result.error ?? 'Face validation failed');
        return;
      }

      final score = _faceService.compare(result.embedding!, template.embeddings);
      final accepted = score >= template.threshold;
      final device = await _deviceService.identity();
      final appVersion = await _deviceService.appVersion();
      final punch = await _client.punch(
        accepted: accepted,
        matchScore: score,
        threshold: template.threshold,
        deviceId: device.id,
        appVersion: appVersion,
        failureReason: accepted ? null : 'Face match below threshold',
      );
      if (!mounted) return;
      final text = punch.accepted
          ? punch.punchType == 'check_out'
              ? 'Checked out successfully.'
              : 'Checked in successfully.'
          : 'Face match failed.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _message = error.toString();
        _busy = false;
      });
    }
  }

  Future<void> _submitRejected(double threshold, String reason) async {
    final device = await _deviceService.identity();
    final appVersion = await _deviceService.appVersion();
    await _client.punch(
      accepted: false,
      matchScore: 0,
      threshold: threshold,
      deviceId: device.id,
      appVersion: appVersion,
      failureReason: reason,
    );
    if (!mounted) return;
    setState(() {
      _message = reason;
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan Attendance')),
      body: Column(
        children: [
          Expanded(
            child: Container(
              width: double.infinity,
              color: Colors.black,
              child: _camera == null || !_camera!.value.isInitialized
                  ? Center(child: Text(_message, style: const TextStyle(color: Colors.white)))
                  : CameraPreview(_camera!),
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
                  onPressed: _busy || _template == null ? null : _scan,
                  icon: _busy
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.face),
                  label: const Text('Scan Now'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
