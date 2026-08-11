import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'src/api/odoo_face_attendance_client.dart';
import 'src/models/session.dart';
import 'src/screens/attendance_screen.dart';
import 'src/screens/local_log_screen.dart';
import 'src/screens/login_screen.dart';
import 'src/screens/settings_screen.dart';
import 'src/services/database_helper.dart';
import 'src/services/face_recognition_service.dart';
import 'src/services/local_log_service.dart';
import 'src/services/on_device_face_matcher.dart';
import 'src/services/secure_session_store.dart';
import 'src/theme/app_theme.dart';
import 'src/widgets/secret_token_dialog.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize SQLite Database and run migration from legacy files if needed
  try {
    await DatabaseHelper.instance.database;
    await DatabaseHelper.instance.migrateLegacyFilesIfNeeded();
  } catch (e) {
    debugPrint("SQLite initialization warning: $e");
  }

  // ================================
  // PRINT ALL FLUTTER SECURE STORAGE
  // ================================
  const storage = FlutterSecureStorage();

  try {
    final allData = await storage.readAll();

    debugPrint("");
    debugPrint("==========================================");
    debugPrint("      FLUTTER SECURE STORAGE DATA");
    debugPrint("==========================================");

    if (allData.isEmpty) {
      debugPrint("Secure Storage is EMPTY");
    } else {
      allData.forEach((key, value) {
        debugPrint("$key : $value");
      });
    }

    debugPrint("==========================================");
    debugPrint("");
  } catch (e) {
    debugPrint("Error reading secure storage: $e");
  }

  // ================================
  // PRINT PARSED SESSION
  // ================================
  try {
    final session = await SecureSessionStore().read();

    debugPrint("");
    debugPrint("==========================================");
    debugPrint("          RESTORED SESSION");
    debugPrint("==========================================");

    if (session == null) {
      debugPrint("No session found.");
    } else {
      debugPrint("Base URL: ${session.baseUrl}");
      debugPrint("Database: ${session.db}");
      debugPrint("Token: ${session.token}");
      debugPrint("Device ID: ${session.deviceId}");
      debugPrint("Device Name: ${session.deviceName}");
      debugPrint("Generated Device ID: ${session.generatedDeviceId}");
    }

    debugPrint("==========================================");
    debugPrint("");
  } catch (e) {
    debugPrint("Error reading session: $e");
  }

  runApp(const FaceAttendApp());
}

class FaceAttendApp extends StatefulWidget {
  const FaceAttendApp({super.key});

  @override
  State<FaceAttendApp> createState() => _FaceAttendAppState();
}

class _FaceAttendAppState extends State<FaceAttendApp> {
  final _sessionStore = SecureSessionStore();
  MobileSession? _session;
  bool _loading = true;
  bool _justLoggedIn = false;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final restored = await _sessionStore.read();
    if (!mounted) return;
    setState(() {
      _session = restored;
      _loading = false;
      _justLoggedIn = false;
    });
  }

  Future<void> _setSession(MobileSession session) async {
    await _sessionStore.write(session);
    if (!mounted) return;
    setState(() {
      _session = session;
      _justLoggedIn = true;
    });
  }

  Future<void> _logout() async {
    await _sessionStore.clear();
    if (!mounted) return;
    setState(() {
      _session = null;
      _justLoggedIn = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FaceAttend',
      debugShowCheckedModeBanner: false,
      theme: faceAttendTheme(),
      home: _loading
          ? const _LoadingScreen()
          : _session == null
          ? LoginScreen(onLoggedIn: _setSession)
          : HomeScreen(
              session: _session!,
              onLogout: _logout,
              justLoggedIn: _justLoggedIn,
            ),
    );
  }
}

class ScaleOnPress extends StatefulWidget {
  const ScaleOnPress({required this.child, required this.onTap, super.key});
  final Widget child;
  final VoidCallback onTap;

  @override
  State<ScaleOnPress> createState() => _ScaleOnPressState();
}

class _ScaleOnPressState extends State<ScaleOnPress> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.98 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    required this.session,
    required this.onLogout,
    this.justLoggedIn = false,
    super.key,
  });

  final MobileSession session;
  final VoidCallback onLogout;
  final bool justLoggedIn;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  late final OdooFaceAttendanceClient _client;
  late Future<AttendanceStatus> _statusFuture;
  late final AnimationController _bgController;
  late final OnDeviceFaceMatcher _faceMatcher;
  Timer? _faceSyncTimer;

  @override
  void initState() {
    super.initState();
    _client = OdooFaceAttendanceClient(
      baseUrl: widget.session.baseUrl,
      db: widget.session.db,
      token: widget.session.token,
      deviceId: widget.session.deviceId,
    );
    _statusFuture = _client.status();
    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 40),
    )..repeat();

    // Auto-sync offline logs on launch, connectivity changes, and periodic retry.
    LocalLogService.instance.startAutoSync(_client);

    // Background face index delta sync (runs if > 10 minutes since last sync)
    _faceMatcher = OnDeviceFaceMatcher(
      client: _client,
      faceService: FaceRecognitionService(),
    );
    _faceMatcher.syncIfStale();

    // 10-minute periodic background face sync
    _faceSyncTimer = Timer.periodic(const Duration(minutes: 10), (_) {
      _faceMatcher.syncIfStale();
    });

    if (widget.justLoggedIn) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showSetupSuccessPopup();
      });
    }
  }

  @override
  void dispose() {
    _faceSyncTimer?.cancel();
    LocalLogService.instance.stopAutoSync();
    _bgController.dispose();
    super.dispose();
  }

  void _refresh() {
    LocalLogService.instance.syncNow(_client).then((syncedCount) {
      if (syncedCount > 0 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Synced $syncedCount offline attendance logs successfully',
            ),
            backgroundColor: FaceAttendColors.success,
          ),
        );
      }
    });
    setState(() {
      _statusFuture = _client.status();
    });
  }

  void _showSetupSuccessPopup() {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black.withOpacity(0.6),
      transitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (context, anim1, anim2) {
        return const SizedBox.shrink();
      },
      transitionBuilder: (context, anim1, anim2, child) {
        final scale = Tween<double>(
          begin: 0.85,
          end: 1.0,
        ).animate(CurvedAnimation(parent: anim1, curve: Curves.easeOutBack));
        final opacity = Tween<double>(
          begin: 0.0,
          end: 1.0,
        ).animate(CurvedAnimation(parent: anim1, curve: Curves.easeOut));

        return ScaleTransition(
          scale: scale,
          child: FadeTransition(
            opacity: opacity,
            child: AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              backgroundColor: FaceAttendColors.surface,
              contentPadding: EdgeInsets.zero,
              content: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: SizedBox(
                  width: 380,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xFF22C55E), Color(0xFF16A34A)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white24,
                              ),
                              child: const Icon(
                                Icons.check_circle_outline,
                                color: Colors.white,
                                size: 48,
                              ),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Scanner Connected!',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'The shared biometric scanner setup was successful. Please record the credentials below.',
                              style: TextStyle(
                                fontSize: 13,
                                color: FaceAttendColors.muted,
                                height: 1.4,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 20),
                            _buildPopupDetailTile(
                              icon: Icons.devices,
                              label: 'DEVICE NAME',
                              value: widget.session.deviceName,
                            ),
                            const SizedBox(height: 12),
                            _buildPopupDetailTile(
                              icon: Icons.fingerprint,
                              label: 'GENERATED DEVICE ID',
                              value: widget.session.generatedDeviceId ?? 'N/A',
                              isHighlight: true,
                            ),
                            const SizedBox(height: 24),
                            ElevatedButton(
                              onPressed: () => Navigator.of(context).pop(),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: FaceAttendColors.ink,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                elevation: 0,
                              ),
                              child: const Text(
                                'Done',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPopupDetailTile({
    required IconData icon,
    required String label,
    required String value,
    bool isHighlight = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isHighlight
            ? FaceAttendColors.successSoft.withOpacity(0.3)
            : FaceAttendColors.surfaceMuted,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isHighlight
              ? FaceAttendColors.success
              : FaceAttendColors.border,
          width: isHighlight ? 1.0 : 0.8,
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: isHighlight
                ? FaceAttendColors.success
                : FaceAttendColors.accent,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                    color: isHighlight
                        ? FaceAttendColors.success
                        : FaceAttendColors.muted,
                  ),
                ),
                const SizedBox(height: 2),
                SelectableText(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: FaceAttendColors.ink,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onLongPress: () => SecretTokenDialog.show(context),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.face_retouching_natural,
                color: FaceAttendColors.accent,
                size: 22,
              ),
              const SizedBox(width: 8),
              const Text(
                'PISmartPunch',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
        ),
        actions: [
          // IconButton(
          //   onPressed: () => SecretTokenDialog.show(context),
          //   tooltip: 'Database Inspector (Secret Token)',
          //   icon: const Icon(Icons.admin_panel_settings, color: Colors.amber),
          // ),
          IconButton(
            onPressed: _refresh,
            tooltip: 'Refresh Status',
            icon: const Icon(Icons.sync),
          ),
          IconButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => SettingsScreen(
                    session: widget.session,
                    onLogout: widget.onLogout,
                  ),
                ),
              );
            },
            tooltip: 'Settings',
            icon: const Icon(Icons.settings),
          ),
        ],
      ),
      body: SafeArea(
        child: AnimatedBuilder(
          animation: _bgController,
          builder: (context, child) {
            return CustomPaint(
              painter: _TechBackgroundPainter(
                animationValue: _bgController.value,
              ),
              child: child,
            );
          },
          child: RefreshIndicator(
            onRefresh: () async => _refresh(),
            color: FaceAttendColors.accent,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              children: [
                AnimatedEntrance(
                  delay: const Duration(milliseconds: 50),
                  child: Container(
                    decoration: premiumCardDecoration(
                      shadowColor: FaceAttendColors.accent,
                    ),
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: FaceAttendColors.accentSoft,
                          ),
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.face_retouching_natural,
                            color: FaceAttendColors.accent,
                            size: 26,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.session.deviceName,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: FaceAttendColors.ink,
                                ),
                              ),
                              const SizedBox(height: 2),
                              const Text(
                                'Shared attendance scanner',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: FaceAttendColors.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                AnimatedEntrance(
                  delay: const Duration(milliseconds: 150),
                  child: FutureBuilder<AttendanceStatus>(
                    future: _statusFuture,
                    builder: (context, snapshot) {
                      return _StatusPanel(
                        loading:
                            snapshot.connectionState == ConnectionState.waiting,
                        online: snapshot.hasData,
                        scannerId: widget.session.deviceId,
                      );
                    },
                  ),
                ),
                const SizedBox(height: 28),

                AnimatedEntrance(
                  delay: const Duration(milliseconds: 250),
                  child: const Text(
                    'QUICK ACTIONS',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      color: FaceAttendColors.muted,
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                AnimatedEntrance(
                  delay: const Duration(milliseconds: 300),
                  child: ScaleOnPress(
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              AttendanceScreen(session: widget.session),
                        ),
                      );
                      _refresh();
                    },
                    child: const _QuickActionCard(
                      title: 'Scan Attendance',
                      subtitle: 'Identify employee and check in or out',
                      icon: Icons.face_retouching_natural,
                      isPrimary: true,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                AnimatedEntrance(
                  delay: const Duration(milliseconds: 350),
                  child: ScaleOnPress(
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              LocalLogScreen(session: widget.session),
                        ),
                      );
                      _refresh();
                    },
                    child: const _QuickActionCard(
                      title: 'Device Activity Logs',
                      subtitle: 'View recent scans and sync queue',
                      icon: Icons.history,
                      isPrimary: false,
                    ),
                  ),
                ),
                // const SizedBox(height: 16),
                // AnimatedEntrance(
                //   delay: const Duration(milliseconds: 400),
                //   child: ScaleOnPress(
                //     onTap: () {
                //       Navigator.of(context).push(
                //         MaterialPageRoute(
                //           builder: (_) => SettingsScreen(
                //             session: widget.session,
                //             onLogout: widget.onLogout,
                //           ),
                //         ),
                //       );
                //     },
                //     child: const _QuickActionCard(
                //       title: 'Configuration Settings',
                //       subtitle: 'View active database and session details',
                //       icon: Icons.tune,
                //       isPrimary: false,
                //     ),
                //   ),
                // ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isPrimary,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    final shadowColor = isPrimary
        ? FaceAttendColors.success
        : FaceAttendColors.muted;
    return Container(
      decoration: premiumCardDecoration(shadowColor: shadowColor),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: isPrimary
                  ? const LinearGradient(
                      colors: [Color(0xFFEDA672), Color(0xFFE57C38)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : LinearGradient(
                      colors: [
                        FaceAttendColors.muted.withValues(alpha: 0.8),
                        FaceAttendColors.muted,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color:
                      (isPrimary
                              ? FaceAttendColors.success
                              : FaceAttendColors.muted)
                          .withValues(alpha: 0.25),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 26),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: FaceAttendColors.ink,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 13,
                    color: FaceAttendColors.muted,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: FaceAttendColors.muted),
        ],
      ),
    );
  }
}

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({
    required this.loading,
    required this.online,
    required this.scannerId,
  });

  final bool loading;
  final bool online;
  final String scannerId;

  @override
  Widget build(BuildContext context) {
    final statusColor = online
        ? FaceAttendColors.success
        : FaceAttendColors.muted;
    return Container(
      decoration: premiumCardDecoration(
        shadowColor: online ? FaceAttendColors.success : FaceAttendColors.muted,
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _PulsingDot(color: statusColor),
              const SizedBox(width: 12),
              Text(
                loading
                    ? 'CHECKING SECURE CONNECTIONS...'
                    : online
                    ? 'BIOMETRIC SCANNER READY'
                    : 'BIOMETRIC SCANNER OFFLINE',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                  color: statusColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _TechStatTile(
                  label: 'LATENCY',
                  value: loading ? '--' : (online ? '24 ms' : 'Offline'),
                  icon: Icons.speed,
                  color: online
                      ? const Color(0xFF06B6D4)
                      : FaceAttendColors.muted,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _TechStatTile(
                  label: 'DATABASE STATUS',
                  value: loading ? '--' : (online ? 'Synced' : 'Offline'),
                  icon: Icons.cloud_done,
                  color: online
                      ? FaceAttendColors.success
                      : FaceAttendColors.muted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _TechStatTile(
                  label: 'LIVENESS ENGINE',
                  value: loading ? '--' : (online ? 'Active' : 'Disabled'),
                  icon: Icons.psychology,
                  color: online
                      ? const Color(0xFF8B5CF6)
                      : FaceAttendColors.muted,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _TechStatTile(
                  label: 'CAMERA LINK',
                  value: loading ? '--' : (online ? 'Secure' : 'Offline'),
                  icon: Icons.videocam,
                  color: online
                      ? const Color(0xFFF59E0B)
                      : FaceAttendColors.muted,
                ),
              ),
            ],
          ),
          const Divider(
            height: 32,
            thickness: 0.8,
            color: FaceAttendColors.border,
          ),
          Row(
            children: [
              const Icon(
                Icons.fingerprint,
                color: FaceAttendColors.accent,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'SYSTEM ID: $scannerId',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: FaceAttendColors.ink,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TechStatTile extends StatelessWidget {
  const _TechStatTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: FaceAttendColors.surfaceMuted,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: FaceAttendColors.border, width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: FaceAttendColors.muted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: FaceAttendColors.ink,
              letterSpacing: -0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _TechBackgroundPainter extends CustomPainter {
  const _TechBackgroundPainter({required this.animationValue});

  final double animationValue;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = FaceAttendColors.accent.withValues(alpha: 0.035);

    final center1 = Offset(size.width * 0.9, size.height * 0.25);
    final center2 = Offset(size.width * 0.1, size.height * 0.75);

    // Draw grid of dots
    final dotPaint = Paint()
      ..color = FaceAttendColors.accent.withValues(alpha: 0.015)
      ..style = PaintingStyle.fill;

    const spacing = 32.0;
    for (double x = 0; x < size.width; x += spacing) {
      for (double y = 0; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), 1.2, dotPaint);
      }
    }

    // Tech circles
    canvas.drawCircle(center1, 120, paint);
    canvas.drawCircle(center1, 128, paint);
    canvas.drawCircle(center2, 160, paint);
    canvas.drawCircle(center2, 172, paint);

    // Dynamic rotating arcs
    final rect1 = Rect.fromCircle(center: center1, radius: 140);
    canvas.drawArc(
      rect1,
      animationValue * 2 * math.pi,
      math.pi * 0.5,
      false,
      paint,
    );
    canvas.drawArc(
      rect1,
      animationValue * 2 * math.pi + math.pi,
      math.pi * 0.3,
      false,
      paint,
    );

    final rect2 = Rect.fromCircle(center: center2, radius: 200);
    canvas.drawArc(
      rect2,
      -animationValue * 2 * math.pi,
      math.pi * 0.4,
      false,
      paint,
    );
    canvas.drawArc(
      rect2,
      -animationValue * 2 * math.pi + math.pi * 1.2,
      math.pi * 0.2,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _TechBackgroundPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue;
  }
}

class _PulsingDot extends StatefulWidget {
  const _PulsingDot({required this.color});
  final Color color;

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        ScaleTransition(
          scale: Tween<double>(begin: 1.0, end: 2.2).animate(
            CurvedAnimation(parent: _controller, curve: Curves.easeOut),
          ),
          child: FadeTransition(
            opacity: Tween<double>(begin: 0.6, end: 0.0).animate(
              CurvedAnimation(parent: _controller, curve: Curves.easeOut),
            ),
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: widget.color,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: widget.color,
            shape: BoxShape.circle,
          ),
        ),
      ],
    );
  }
}

class AnimatedEntrance extends StatefulWidget {
  const AnimatedEntrance({
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 600),
    super.key,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;

  @override
  State<AnimatedEntrance> createState() => _AnimatedEntranceState();
}

class _AnimatedEntranceState extends State<AnimatedEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _opacity = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _slide = Tween<Offset>(begin: const Offset(0.0, 0.2), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _controller,
            curve: const Interval(0.0, 1.0, curve: Curves.easeOutCubic),
          ),
        );
    if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}

class FloatingWidget extends StatefulWidget {
  const FloatingWidget({
    required this.child,
    this.duration = const Duration(seconds: 3),
    super.key,
  });
  final Widget child;
  final Duration duration;

  @override
  State<FloatingWidget> createState() => _FloatingWidgetState();
}

class _FloatingWidgetState extends State<FloatingWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _offset;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..repeat(reverse: true);
    _offset = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(0.0, 0.03),
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(position: _offset, child: widget.child);
  }
}

BoxDecoration premiumCardDecoration({
  Color shadowColor = const Color(0xFF10B981),
}) {
  return BoxDecoration(
    color: FaceAttendColors.surface,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: FaceAttendColors.border, width: 0.8),
    boxShadow: [
      BoxShadow(
        color: shadowColor.withValues(alpha: 0.05),
        blurRadius: 16,
        offset: const Offset(0, 6),
      ),
    ],
  );
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: AppLoader(size: 100)));
  }
}
