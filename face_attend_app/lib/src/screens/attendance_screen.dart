import 'dart:async';

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
  static const _detectionWatchdogTimeout = Duration(seconds: 2);
  static const _stableFrameTarget = 5;
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
  DateTime _lastValidFrameAt = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _detectionWatchdog;
  bool _processingFrame = false;
  bool _autoCaptureStarted = false;
  int _stableFrames = 0;
  int _scanGeneration = 0;
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
        _lastValidFrameAt = DateTime.now();
      });
      _startDetectionWatchdog();
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
    _detectionWatchdog?.cancel();
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
    final scannerStateAtStart = _scannerState;
    final generationAtStart = _scanGeneration;
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
      if (generationAtStart != _scanGeneration ||
          scannerStateAtStart != _scannerState ||
          !_autoDetectionEnabled) {
        return;
      }

      final singleFace = result.faces.length == 1;
      final nextStableFrames = singleFace ? _stableFrames + 1 : 0;
      final ready = nextStableFrames >= _stableFrameTarget;
      setState(() {
        _stableFrames = nextStableFrames;
        _faceBounds = singleFace ? result.faces.first.boundingBox : null;
        _faceImageSize = result.imageSize;
        _faceOverlays = singleFace
            ? [
                FaceOverlay(
                  bounds: result.faces.first.boundingBox,
                  ready: ready,
                  label: ready ? 'Scanning' : null,
                ),
              ]
            : const [];
        _message = _messageForSingleFaceResult(result, ready);
        _scannerState = ready ? _ScannerState.ready : _ScannerState.detecting;
        _lastValidFrameAt = DateTime.now();
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
      _clearStaleDetectionIfNeeded();
    }
  }

  String _messageForSingleFaceResult(
    MultiFaceValidationResult result,
    bool ready,
  ) {
    if (result.faces.length > 1) return 'One person at a time';
    if (ready) return 'Scanning';
    if (result.faces.length == 1) return 'Hold still';
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
      _clearFaceState();
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
      final match = await middleware.match(imagePath: imagePath);
      await deleteImageQuietly(imagePath);
      final device = await _deviceService.identity();
      final appVersion = await _deviceService.appVersion();
      final deviceId = widget.session.deviceId.isNotEmpty
          ? widget.session.deviceId
          : device.id;
      final liveAccepted = match.livenessPassed == true;
      final accepted =
          match.matched && match.employeeId != null && liveAccepted;
      final inCooldown = accepted && _isEmployeeInCooldown(match.employeeId!);
      final punch = await _client.punch(
        accepted: accepted && !inCooldown,
        matchedEmployeeId: match.employeeId,
        matchScore: match.confidence,
        threshold: match.threshold,
        deviceId: deviceId,
        appVersion: appVersion,
        failureReason: accepted
            ? inCooldown
                  ? 'cooldown'
                  : null
            : liveAccepted
            ? match.reason ?? 'below_threshold'
            : 'liveness_failed',
        secondBestConfidence: match.secondBestConfidence,
        embeddingSource: match.embeddingSource,
        reviewEmbeddingId: match.reviewEmbeddingId,
        needsReview: match.needsReview,
        livenessPassed: match.livenessPassed == true,
        livenessScore: match.livenessScore,
        spoofScore: match.spoofScore,
      );
      if (accepted && !inCooldown) {
        _lastPunchByEmployee[match.employeeId!] = DateTime.now();
      }
      if (!mounted) return;
      _clearFaceStateForDisplay();
      _showSingleFaceLabel(match, punch);
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
                ? '${punch.employee?.name ?? match.employeeName ?? 'Employee'} #${punch.employee?.id ?? match.employeeId} was ${punch.punchType == 'check_out' ? 'checked out' : 'checked in'}.'
                : _messageForRejectedMatch(
                    match,
                    inCooldown ? 'cooldown' : match.reason,
                  ),
            time: DateTime.now(),
            confidence: match.confidence,
            primaryLabel: 'Scan Again',
            primaryIcon: Icons.refresh,
            popToFirst: false,
            showRetry: false,
          ),
        ),
      );
      if (!mounted) return;
      _pauseAfterScan(
        punch.accepted
            ? 'Scan complete'
            : _messageForRejectedMatch(
                match,
                inCooldown ? 'cooldown' : match.reason,
              ),
      );
    } catch (error) {
      await deleteImageQuietly(imagePath);
      if (error is FaceMiddlewareException) {
        await _logRejectedScan(error);
      }
      if (!mounted) return;
      _pauseAfterScan(error.toString());
    }
  }

  Future<void> _logRejectedScan(FaceMiddlewareException error) async {
    final device = await _deviceService.identity();
    final appVersion = await _deviceService.appVersion();
    final deviceId = widget.session.deviceId.isNotEmpty
        ? widget.session.deviceId
        : device.id;
    final failureReason = error.code ?? error.message;
    try {
      await _client.punch(
        accepted: false,
        matchScore: 0,
        threshold: 0.70,
        deviceId: deviceId,
        appVersion: appVersion,
        failureReason: failureReason,
        livenessPassed: false,
        spoofScore: failureReason == 'spoof_detected' ? 1.0 : null,
      );
    } catch (_) {
      // Preserve the original scanner error for the operator.
    }
  }

  void _pauseAfterScan(String message) {
    if (!mounted) return;
    _detectionWatchdog?.cancel();
    setState(() {
      _message = message;
      _scannerState = _ScannerState.paused;
      _clearFaceState();
    });
  }

  Future<void> _resetDetectionState({
    String message = 'Looking for a face',
  }) async {
    final camera = _camera;
    if (camera?.value.isStreamingImages == true) {
      await camera?.stopImageStream();
    }
    if (!mounted) return;
    setState(() {
      _message = message;
      _scannerState = _ScannerState.detecting;
      _clearFaceState();
      _processingFrame = false;
      _lastValidFrameAt = DateTime.now();
    });
    await _startFaceDetection();
    _startDetectionWatchdog();
  }

  bool _isEmployeeInCooldown(int employeeId) {
    final lastPunch = _lastPunchByEmployee[employeeId];
    if (lastPunch == null) return false;
    return DateTime.now().difference(lastPunch) < _employeePunchCooldown;
  }

  void _showSingleFaceLabel(FaceMatchResult match, PunchResult punch) {
    if (!mounted) return;
    setState(() {
      _faceOverlays = const [];
      _message = punch.accepted
          ? '${punch.employee?.name ?? match.employeeName ?? 'Employee'} logged'
          : _messageForMatchReason(match.reason);
    });
  }

  void _clearFaceState() {
    _scanGeneration++;
    _faceBounds = null;
    _faceImageSize = null;
    _faceOverlays = const [];
    _stableFrames = 0;
    _autoCaptureStarted = false;
  }

  void _clearFaceStateForDisplay() {
    if (!mounted) return;
    setState(_clearFaceState);
  }

  void _clearStaleDetectionIfNeeded() {
    if (!mounted || !_autoDetectionEnabled) return;
    if (DateTime.now().difference(_lastValidFrameAt) <
        _detectionWatchdogTimeout) {
      return;
    }
    setState(() {
      _message = 'Looking for a face';
      _scannerState = _ScannerState.detecting;
      _faceBounds = null;
      _faceImageSize = null;
      _faceOverlays = const [];
      _stableFrames = 0;
      _autoCaptureStarted = false;
      _lastValidFrameAt = DateTime.now();
    });
  }

  void _startDetectionWatchdog() {
    _detectionWatchdog?.cancel();
    _detectionWatchdog = Timer.periodic(const Duration(milliseconds: 750), (_) {
      _clearStaleDetectionIfNeeded();
    });
  }

  String _messageForMatchReason(String? reason) {
    switch (reason) {
      case 'cooldown':
        return 'Already scanned recently';
      case 'below_threshold':
        return 'Match confidence too low';
      case 'ambiguous_match':
        return 'Could not identify employee';
      case 'no_registered_embeddings':
        return 'No registered employees found';
      case 'no_face_detected':
        return 'No face detected';
      case 'multiple_faces_detected':
        return 'One person at a time';
      case 'face_not_clear':
      case 'low_detection_score':
        return 'Face not clear';
      case 'face_too_small':
        return 'Move closer to the camera';
      case 'face_too_large':
        return 'Move slightly back';
      default:
        return 'Could not identify employee';
    }
  }

  String _messageForRejectedMatch(FaceMatchResult match, String? reason) {
    if (match.needsReview && match.employeeName != null) {
      final confidence = (match.confidence * 100)
          .clamp(0, 100)
          .toStringAsFixed(1);
      return 'Could not verify. Closest: ${match.employeeName} ($confidence%). Try removing glare and look straight.';
    }
    final message = _messageForMatchReason(reason);
    if (match.employeeName == null || reason == 'cooldown') return message;
    final confidence = (match.confidence * 100)
        .clamp(0, 100)
        .toStringAsFixed(1);
    return '$message. Closest: ${match.employeeName} ($confidence%).';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
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
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
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
                              color: const Color(
                                0xFFFF6B35,
                              ).withValues(alpha: 0.25),
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
                    onPressed: _canScan
                        ? _scannerState == _ScannerState.paused ||
                                  _scannerState == _ScannerState.failed
                              ? () => _resetDetectionState()
                              : _scan
                        : null,
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
                              Icon(Icons.face, color: Colors.white),
                              SizedBox(width: 8),
                              Text(
                                _scannerState == _ScannerState.paused ||
                                        _scannerState == _ScannerState.failed
                                    ? 'Scan Again'
                                    : 'Scan Now',
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

enum _ScannerState {
  loading,
  detecting,
  ready,
  capturing,
  submitting,
  paused,
  failed,
}
