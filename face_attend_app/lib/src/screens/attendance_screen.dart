import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../api/face_middleware_client.dart';
import '../api/odoo_face_attendance_client.dart';
import '../models/session.dart';
import '../screens/result_screen.dart';
import '../services/device_service.dart';
import '../services/face_recognition_service.dart';
import '../widgets/face_scan_view.dart';

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
  String _message = 'Loading scanner...';
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _client = OdooFaceAttendanceClient(baseUrl: widget.session.baseUrl, db: widget.session.db, token: widget.session.token);
    _init();
  }

  Future<void> _init() async {
    try {
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
    if (camera == null || !camera.value.isInitialized) return;
    setState(() => _busy = true);
    String? imagePath;
    try {
      final image = await camera.takePicture();
      imagePath = image.path;
      final result = await _faceService.validateImage(imagePath);
      if (!result.valid) {
        await deleteImageQuietly(imagePath);
        imagePath = null;
        await _submitRejected(0.45, result.error ?? 'Face validation failed');
        return;
      }

      final middleware = FaceMiddlewareClient(
        baseUrl: widget.session.middlewareUrl,
        apiKey: widget.session.middlewareApiKey,
      );
      final match = await middleware.match(imagePath: imagePath);
      await deleteImageQuietly(imagePath);
      imagePath = null;
      final accepted = match.matched && match.employeeId == widget.session.employee.id;
      final device = await _deviceService.identity();
      final appVersion = await _deviceService.appVersion();
      final punch = await _client.punch(
        accepted: accepted,
        matchScore: match.confidence,
        threshold: match.threshold,
        deviceId: device.id,
        appVersion: appVersion,
        failureReason: accepted
            ? null
            : match.matched
                ? 'Matched a different employee'
                : match.reason ?? 'Face match below threshold',
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => AttendanceResultScreen(
            success: punch.accepted,
            title: punch.accepted
                ? punch.punchType == 'check_out'
                    ? 'Checked out'
                    : 'Checked in'
                : 'Face match failed',
            message: punch.accepted
                ? 'Attendance was recorded successfully.'
                : accepted
                    ? 'Attendance was recorded successfully.'
                    : match.matched
                        ? 'The scan matched a different employee.'
                        : match.reason ?? 'Your face did not match the registered template.',
            time: DateTime.now(),
            confidence: match.confidence,
            showRetry: !punch.accepted,
          ),
        ),
      );
    } catch (error) {
      if (imagePath != null) {
        await deleteImageQuietly(imagePath);
      }
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
    setState(() => _busy = false);
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AttendanceResultScreen(
          success: false,
          title: 'Scan rejected',
          message: reason,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan Attendance')),
      body: Column(
        children: [
          Expanded(
            child: FaceScanView(
              camera: _camera,
              message: _message,
              prompt: 'Blink once, look straight, then scan.',
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
                  onPressed: _busy ? null : _scan,
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
