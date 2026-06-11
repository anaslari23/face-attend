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
  static const _analysisInterval = Duration(milliseconds: 250);
  static const _stableFrameTarget = 3;
  static const _defaultMatchThreshold = 0.70;
  static const _employeePunchCooldown = Duration(minutes: 2);

  final _faceService = FaceRecognitionService();
  final _deviceService = DeviceService();
  late final OdooFaceAttendanceClient _client;
  CameraController? _camera;
  String _message = 'Loading scanner...';
  _ScannerState _scannerState = _ScannerState.loading;
  Rect? _faceBounds;
  Size? _faceImageSize;
  List<FaceOverlay> _faceOverlays = const [];
  DateTime _lastAnalysisAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _processingFrame = false;
  bool _autoCaptureStarted = false;
  int _stableFrames = 0;
  final Map<int, DateTime> _lastPunchByEmployee = {};

  bool get _busy =>
      _scannerState == _ScannerState.loading ||
      _scannerState == _ScannerState.capturing ||
      _scannerState == _ScannerState.submitting;

  bool get _canScan =>
      _camera != null &&
      _camera!.value.isInitialized &&
      _scannerState != _ScannerState.loading &&
      _scannerState != _ScannerState.capturing &&
      _scannerState != _ScannerState.submitting;

  bool get _autoDetectionEnabled =>
      _scannerState == _ScannerState.detecting ||
      _scannerState == _ScannerState.ready;

  @override
  void initState() {
    super.initState();
    _client = OdooFaceAttendanceClient(
      baseUrl: widget.session.baseUrl,
      db: widget.session.db,
      token: widget.session.token,
    );
    _init();
  }

  Future<void> _init() async {
    try {
      final cameras = await availableCameras();
      final front = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      _camera = CameraController(
        front,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await _camera!.initialize();
      await _faceService.initialize();
      await _startFaceDetection();
      if (!mounted) return;
      setState(() {
        _message = 'Looking for a face';
        _scannerState = _ScannerState.detecting;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _message = error.toString();
        _scannerState = _ScannerState.failed;
      });
    }
  }

  @override
  void dispose() {
    if (_camera?.value.isStreamingImages == true) {
      _camera?.stopImageStream();
    }
    _camera?.dispose();
    _faceService.close();
    super.dispose();
  }

  Future<void> _startFaceDetection() async {
    final camera = _camera;
    if (camera == null ||
        !camera.value.isInitialized ||
        camera.value.isStreamingImages) {
      return;
    }
    await camera.startImageStream(_handleCameraFrame);
  }

  Future<void> _handleCameraFrame(CameraImage image) async {
    final camera = _camera;
    if (camera == null ||
        _processingFrame ||
        !_autoDetectionEnabled ||
        _scannerState == _ScannerState.capturing ||
        _scannerState == _ScannerState.submitting) {
      return;
    }

    final now = DateTime.now();
    if (now.difference(_lastAnalysisAt) < _analysisInterval) return;
    _lastAnalysisAt = now;
    _processingFrame = true;

    try {
      final result = await _faceService.detectCameraFaces(
        image: image,
        camera: camera.description,
        deviceOrientation: camera.value.deviceOrientation,
      );
      if (!mounted) return;

      final nextStableFrames = result.faces.isNotEmpty ? _stableFrames + 1 : 0;
      final ready = nextStableFrames >= _stableFrameTarget;
      setState(() {
        _stableFrames = nextStableFrames;
        _faceBounds = result.faces.isEmpty
            ? null
            : result.faces.first.boundingBox;
        _faceImageSize = result.imageSize;
        _faceOverlays = result.faces
            .map(
              (face) => FaceOverlay(
                bounds: face.boundingBox,
                ready: ready,
                label: ready ? 'Scanning' : null,
              ),
            )
            .toList();
        _message = _messageForMultiFaceResult(result, ready);
        _scannerState = ready ? _ScannerState.ready : _ScannerState.detecting;
      });

      if (ready && !_autoCaptureStarted) {
        _autoCaptureStarted = true;
        await _captureAndSubmit();
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _message = error.toString();
        _scannerState = _ScannerState.failed;
      });
    } finally {
      _processingFrame = false;
    }
  }

  String _messageForMultiFaceResult(
    MultiFaceValidationResult result,
    bool ready,
  ) {
    if (ready) {
      return result.faces.length == 1
          ? 'Scanning'
          : 'Scanning ${result.faces.length} faces';
    }
    if (result.faces.isNotEmpty) {
      return result.faces.length == 1
          ? 'Hold still'
          : '${result.faces.length} faces detected';
    }
    return result.message;
  }

  Future<void> _scan() => _captureAndSubmit();

  Future<void> _captureAndSubmit() async {
    final camera = _camera;
    if (camera == null || !camera.value.isInitialized) return;
    if (_scannerState == _ScannerState.capturing ||
        _scannerState == _ScannerState.submitting) {
      return;
    }
    setState(() {
      _message = 'Scanning';
      _scannerState = _ScannerState.capturing;
    });
    String? imagePath;
    try {
      if (camera.value.isStreamingImages) {
        await camera.stopImageStream();
      }
      final image = await camera.takePicture();
      imagePath = image.path;

      await _submitCapturedImage(imagePath);
      imagePath = null;
    } catch (error) {
      if (imagePath != null) {
        await deleteImageQuietly(imagePath);
      }
      if (!mounted) return;
      _pauseAfterScan(error.toString());
    }
  }

  Future<void> _submitCapturedImage(String imagePath) async {
    try {
      final middleware = FaceMiddlewareClient(
        baseUrl: widget.session.middlewareUrl,
        apiKey: widget.session.middlewareApiKey,
      );
      if (mounted) {
        setState(() {
          _message = 'Submitting face match';
          _scannerState = _ScannerState.submitting;
        });
      }
      final multiMatch = await middleware.matchFaces(imagePath: imagePath);
      await deleteImageQuietly(imagePath);
      final device = await _deviceService.identity();
      final appVersion = await _deviceService.appVersion();
      final deviceId = widget.session.deviceId.isNotEmpty
          ? widget.session.deviceId
          : device.id;
      final acceptedMatches = multiMatch.faces
          .where((match) => match.matched && match.employeeId != null)
          .toList();
      final punchedNames = <String>[];
      for (final match in acceptedMatches) {
        final employeeId = match.employeeId!;
        if (_isEmployeeInCooldown(employeeId)) continue;
        final punch = await _client.punch(
          accepted: true,
          matchedEmployeeId: employeeId,
          matchScore: match.confidence,
          threshold: match.threshold,
          deviceId: deviceId,
          appVersion: appVersion,
        );
        _lastPunchByEmployee[employeeId] = DateTime.now();
        if (punch.accepted) {
          punchedNames.add(
            punch.employee?.name ??
                match.employeeName ??
                'Employee $employeeId',
          );
        }
      }
      if (acceptedMatches.isEmpty) {
        await _client.punch(
          accepted: false,
          matchScore: 0,
          threshold: _defaultMatchThreshold,
          deviceId: deviceId,
          appVersion: appVersion,
          failureReason: multiMatch.faces.isEmpty
              ? 'no_face_detected'
              : multiMatch.faces
                    .map((face) => face.reason ?? 'unmatched')
                    .join(','),
        );
      }
      if (!mounted) return;
      _showServerFaceLabels(multiMatch);
      if (punchedNames.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${punchedNames.join(', ')} logged')),
        );
        await Future<void>.delayed(const Duration(milliseconds: 1500));
      } else if (acceptedMatches.isEmpty) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => AttendanceResultScreen(
              success: false,
              title: 'Face match failed',
              message: 'Could not identify employee',
              time: DateTime.now(),
              confidence: 0,
              showRetry: true,
            ),
          ),
        );
      } else {
        await Future<void>.delayed(const Duration(milliseconds: 1000));
      }
      if (!mounted) return;
      _pauseAfterScan(
        punchedNames.isNotEmpty
            ? '${punchedNames.join(', ')} logged'
            : 'Scan complete',
      );
    } catch (error) {
      await deleteImageQuietly(imagePath);
      if (!mounted) return;
      _pauseAfterScan(error.toString());
    }
  }

  void _pauseAfterScan(String message) {
    if (!mounted) return;
    setState(() {
      _message = message;
      _scannerState = _ScannerState.paused;
      _stableFrames = 0;
      _autoCaptureStarted = false;
    });
  }

  Future<void> _resetDetectionState({
    String message = 'Looking for a face',
  }) async {
    if (!mounted) return;
    setState(() {
      _message = message;
      _scannerState = _ScannerState.detecting;
      _faceBounds = null;
      _faceImageSize = null;
      _faceOverlays = const [];
      _stableFrames = 0;
      _autoCaptureStarted = false;
    });
    await _startFaceDetection();
  }

  bool _isEmployeeInCooldown(int employeeId) {
    final lastPunch = _lastPunchByEmployee[employeeId];
    if (lastPunch == null) return false;
    return DateTime.now().difference(lastPunch) < _employeePunchCooldown;
  }

  void _showServerFaceLabels(MultiFaceMatchResult result) {
    if (!mounted) return;
    setState(() {
      _faceImageSize = Size(
        result.imageWidth.toDouble(),
        result.imageHeight.toDouble(),
      );
      _faceBounds = null;
      _faceOverlays = result.faces
          .where((match) => match.boundingBox != null)
          .map((match) {
            final box = match.boundingBox!;
            return FaceOverlay(
              bounds: Rect.fromLTRB(box.left, box.top, box.right, box.bottom),
              ready: match.matched,
              label: match.matched
                  ? '${match.employeeName ?? 'Employee'} #${match.employeeId}'
                  : 'Unknown',
            );
          })
          .toList();
      _message = result.faces.isEmpty
          ? 'No face detected'
          : '${result.faces.length} face${result.faces.length == 1 ? '' : 's'} scanned';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7), // Parchment
      appBar: AppBar(title: const Text('Scan Attendance')),
      body: Column(
        children: [
          Expanded(
            child: FaceScanView(
              camera: _camera,
              message: _message,
              faceBounds: _faceBounds,
              faceImageSize: _faceImageSize,
              faceOverlays: _faceOverlays,
              faceReady: _scannerState == _ScannerState.ready,
              prompt: _busy ? 'Processing biometric scan...' : _message,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(18), // rounded.lg (18px)
              ),
              border: Border(
                top: BorderSide(color: Color(0xFFE0E0E0), width: 0.5), // hairline
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF7A7A7A), // ink-muted-48
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 18),
                _ScaleOnPress(
                  onTap: _canScan
                      ? _scannerState == _ScannerState.paused ||
                                _scannerState == _ScannerState.failed
                            ? () => _resetDetectionState()
                            : _scan
                      : () {},
                  child: Container(
                    height: 44, // button height
                    decoration: BoxDecoration(
                      color: _busy
                          ? const Color(0xFFF5F5F7)
                          : _canScan
                              ? const Color(0xFF0066CC) // Action Blue
                              : const Color(0xFFE0E0E0),
                      borderRadius: BorderRadius.circular(9999), // pill
                      border: _busy
                          ? Border.all(color: const Color(0xFFE0E0E0), width: 1.0)
                          : null,
                    ),
                    alignment: Alignment.center,
                    child: _busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFF0066CC),
                            ),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.face,
                                color: _canScan ? Colors.white : const Color(0xFF7A7A7A),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _scannerState == _ScannerState.paused ||
                                        _scannerState == _ScannerState.failed
                                    ? 'Scan Again'
                                    : 'Scan Now',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w400,
                                  color: _canScan ? Colors.white : const Color(0xFF7A7A7A),
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

class _ScaleOnPress extends StatefulWidget {
  const _ScaleOnPress({required this.child, required this.onTap});
  final Widget child;
  final VoidCallback onTap;

  @override
  State<_ScaleOnPress> createState() => _ScaleOnPressState();
}

class _ScaleOnPressState extends State<_ScaleOnPress> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 80),
        child: widget.child,
      ),
    );
  }
}

enum _ScannerState {
  loading,
  detecting,
  ready,
  capturing,
  submitting,
  paused,
  failed,
}
