import 'dart:math' as math;
import 'package:flutter/material.dart';

import 'src/api/odoo_face_attendance_client.dart';
import 'src/models/session.dart';
import 'src/screens/attendance_screen.dart';
import 'src/screens/login_screen.dart';
import 'src/screens/settings_screen.dart';
import 'src/services/secure_session_store.dart';
import 'src/theme/app_theme.dart';

void main() {
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

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    var restored = await _sessionStore.read();
    if (restored != null && _usesLoopbackHost(restored.middlewareUrl)) {
      await _sessionStore.clear();
      restored = null;
    }
    if (!mounted) return;
    setState(() {
      _session = restored;
      _loading = false;
    });
  }

  bool _usesLoopbackHost(String url) {
    final uri = Uri.tryParse(url);
    final host = uri?.host.toLowerCase();
    return host == '127.0.0.1' || host == 'localhost' || host == '::1';
  }

  Future<void> _setSession(MobileSession session) async {
    await _sessionStore.write(session);
    if (!mounted) return;
    setState(() => _session = session);
  }

  Future<void> _logout() async {
    await _sessionStore.clear();
    if (!mounted) return;
    setState(() => _session = null);
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
          : HomeScreen(session: _session!, onLogout: _logout),
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
  const HomeScreen({required this.session, required this.onLogout, super.key});

  final MobileSession session;
  final VoidCallback onLogout;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  late final OdooFaceAttendanceClient _client;
  late Future<AttendanceStatus> _statusFuture;
  late final AnimationController _bgController;

  @override
  void initState() {
    super.initState();
    _client = OdooFaceAttendanceClient(
      baseUrl: widget.session.baseUrl,
      db: widget.session.db,
      token: widget.session.token,
    );
    _statusFuture = _client.status();
    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 40),
    )..repeat();
  }

  @override
  void dispose() {
    _bgController.dispose();
    super.dispose();
  }

  void _refresh() {
    setState(() {
      _statusFuture = _client.status();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.face_retouching_natural,
              color: FaceAttendColors.accent,
              size: 22,
            ),
            const SizedBox(width: 8),
            const Text(
              'FaceAttend',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
          ],
        ),
        actions: [
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
                      colors: [Color(0xFF059669), Color(0xFF10B981)],
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
