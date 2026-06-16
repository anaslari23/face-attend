import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../api/odoo_face_attendance_client.dart';
import '../models/session.dart';
import '../screens/result_screen.dart';
import '../services/device_service.dart';
import '../services/face_recognition_service.dart';
import '../services/local_log_service.dart';
import '../services/on_device_face_matcher.dart';
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
  late final OnDeviceFaceMatcher _matcher;
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
    _matcher = OnDeviceFaceMatcher(client: _client, faceService: _faceService);
    _init();
  }

  Future<void> _init() async {
    try {
      final device = await _deviceService.identity();
      final deviceId = widget.session.deviceId.isNotEmpty
          ? widget.session.deviceId
          : device.id;
      debugPrint('\n=========================================');
      debugPrint('DEVICE_UID: $deviceId');
      debugPrint('=========================================\n');
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
      if (mounted) {
        setState(() {
          _message = 'Syncing employee faces';
          _scannerState = _ScannerState.loading;
        });
      }
      final sync = await _matcher.sync();
      if (sync.indexedEmployees == 0) {
        throw StateError(
          sync.failures.isEmpty
              ? 'No employee avatars found in Odoo'
              : 'No usable employee faces found. ${sync.failures.first}',
        );
      }
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
        await _deleteImageQuietly(imagePath);
      }
      if (!mounted) return;
      _pauseAfterScan(error.toString());
    }
  }

  Future<void> _submitCapturedImage(String imagePath) async {
    try {
      if (mounted) {
        setState(() {
          _message = 'Matching face on device';
          _scannerState = _ScannerState.submitting;
        });
      }
      final match = await _matcher.matchImagePath(imagePath);
      await _deleteImageQuietly(imagePath);
      final device = await _deviceService.identity();
      final appVersion = await _deviceService.appVersion();
      final deviceId = widget.session.deviceId.isNotEmpty
          ? widget.session.deviceId
          : device.id;
      final liveAccepted = match.livenessPassed;
      final accepted =
          match.matched && match.employeeId != null && liveAccepted;
      final inCooldown = accepted && _isEmployeeInCooldown(match.employeeId!);

      final Map<String, dynamic> payload = {
        'accepted': accepted && !inCooldown,
        'matched_employee_id': match.employeeId,
        'match_score': match.confidence,
        'threshold': match.threshold,
        'device_id': deviceId,
        'app_version': appVersion,
        'failure_reason': accepted
            ? inCooldown
                ? 'cooldown'
                : null
            : liveAccepted
            ? match.reason ?? 'below_threshold'
            : 'liveness_failed',
        'second_best_confidence': match.secondBestConfidence,
        'embedding_source': match.embeddingSource,
        'needs_review': match.needsReview,
        'liveness_passed': match.livenessPassed,
        'liveness_score': match.livenessScore,
        'spoof_score': match.livenessPassed ? 0.0 : 1.0,
      };

      final now = DateTime.now();
      final employeeName = match.employeeName ?? 'Unknown Employee';
      final logId = 'log_${now.millisecondsSinceEpoch}_${match.employeeId ?? 0}';

      // 1. Add log locally as unsynced
      await LocalLogService.instance.addLog(
        id: logId,
        timestamp: now,
        payload: payload,
        employeeName: employeeName,
        isSynced: false,
      );

      PunchResult punch;
      try {
        punch = await _client.punch(
          accepted: payload['accepted'] as bool,
          matchedEmployeeId: payload['matched_employee_id'] as int?,
          matchScore: (payload['match_score'] as num).toDouble(),
          threshold: (payload['threshold'] as num).toDouble(),
          deviceId: payload['device_id'] as String,
          appVersion: payload['app_version'] as String,
          failureReason: payload['failure_reason'] as String?,
          secondBestConfidence: payload['second_best_confidence'] != null 
              ? (payload['second_best_confidence'] as num).toDouble() 
              : null,
          embeddingSource: payload['embedding_source'] as String?,
          needsReview: payload['needs_review'] as bool,
          livenessPassed: payload['liveness_passed'] as bool,
          livenessScore: payload['liveness_score'] != null 
              ? (payload['liveness_score'] as num).toDouble() 
              : null,
          spoofScore: (payload['spoof_score'] as num).toDouble(),
        );
        // 2. Mark local log as synced
        await LocalLogService.instance.updateLogSyncStatus(logId, isSynced: true);
      } catch (error) {
        // If API fails (e.g. network/offline), log the error but treat the match as temporarily valid if accepted locally
        await LocalLogService.instance.updateLogSyncStatus(
          logId,
          isSynced: false,
          syncError: error.toString(),
        );

        if (accepted && !inCooldown) {
          punch = PunchResult(
            accepted: true,
            punchType: 'offline_log',
            employee: EmployeeProfile(
              id: match.employeeId!,
              name: employeeName,
              faceRegistered: true,
            ),
          );
        } else {
          punch = PunchResult(
            accepted: false,
            employee: match.employeeId != null
                ? EmployeeProfile(id: match.employeeId!, name: employeeName, faceRegistered: true)
                : null,
          );
        }
      }

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
            title: punch.accepted ? 'Thank you' : 'Face match failed',
            message: punch.accepted
                ? 'Your attendance has been recorded.'
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
      await _resetDetectionState(
        message: punch.accepted
            ? 'Scan complete'
            : _messageForRejectedMatch(
                match,
                inCooldown ? 'cooldown' : match.reason,
              ),
      );
    } catch (error) {
      await _deleteImageQuietly(imagePath);
      await _logRejectedScan(error.toString());
      if (!mounted) return;
      _pauseAfterScan(error.toString());
    }
  }

  Future<void> _logRejectedScan(String error) async {
    final device = await _deviceService.identity();
    final appVersion = await _deviceService.appVersion();
    final deviceId = widget.session.deviceId.isNotEmpty
        ? widget.session.deviceId
        : device.id;

    final Map<String, dynamic> payload = {
      'accepted': false,
      'matched_employee_id': null,
      'match_score': 0.0,
      'threshold': 0.70,
      'device_id': deviceId,
      'app_version': appVersion,
      'failure_reason': error,
      'liveness_passed': false,
      'spoof_score': 1.0,
    };

    final now = DateTime.now();
    final logId = 'log_${now.millisecondsSinceEpoch}_err';

    await LocalLogService.instance.addLog(
      id: logId,
      timestamp: now,
      payload: payload,
      employeeName: 'System Error',
      isSynced: false,
    );

    try {
      await _client.punch(
        accepted: false,
        matchScore: 0,
        threshold: 0.70,
        deviceId: deviceId,
        appVersion: appVersion,
        failureReason: error,
        livenessPassed: false,
        spoofScore: 1.0,
      );
      await LocalLogService.instance.updateLogSyncStatus(logId, isSynced: true);
    } catch (_) {
      // Keep as unsynced offline log
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

  void _showSingleFaceLabel(LocalFaceMatchResult match, PunchResult punch) {
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

  String _messageForRejectedMatch(LocalFaceMatchResult match, String? reason) {
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

  Future<void> _deleteImageQuietly(String path) async {
    try {
      await File(path).delete();
    } catch (_) {
      // Temporary camera image cleanup best effort.
    }
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
