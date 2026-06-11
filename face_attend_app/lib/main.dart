import 'package:flutter/material.dart';

import 'src/api/odoo_face_attendance_client.dart';
import 'src/models/session.dart';
import 'src/screens/attendance_screen.dart';
import 'src/screens/login_screen.dart';
import 'src/screens/settings_screen.dart';
import 'src/services/secure_session_store.dart';

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
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0066CC),
          primary: const Color(0xFF0066CC),
          secondary: const Color(0xFF0071E3),
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF5F5F7), // Parchment
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Color(0xFF1D1D1F), // Ink
          elevation: 0,
          centerTitle: true,
          shape: Border(
            bottom: BorderSide(color: Color(0xFFE0E0E0), width: 0.5),
          ),
          titleTextStyle: TextStyle(
            color: Color(0xFF1D1D1F), // Ink
            fontSize: 17,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.374,
          ),
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18), // rounded.lg (18px)
            side: const BorderSide(color: Color(0xFFE0E0E0), width: 1.0), // hairline
          ),
        ),
      ),
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
        scale: _pressed ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 80),
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

class _HomeScreenState extends State<HomeScreen> {
  late final OdooFaceAttendanceClient _client;
  late Future<AttendanceStatus> _statusFuture;

  @override
  void initState() {
    super.initState();
    _client = OdooFaceAttendanceClient(
      baseUrl: widget.session.baseUrl,
      db: widget.session.db,
      token: widget.session.token,
    );
    _statusFuture = _client.status();
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
              color: Color(0xFF0066CC),
              size: 20,
            ),
            const SizedBox(width: 8),
            const Text(
              'FaceAttend',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                letterSpacing: -0.374,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _refresh,
            tooltip: 'Refresh Status',
            icon: const Icon(Icons.sync, color: Color(0xFF1D1D1F)),
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
            icon: const Icon(Icons.settings, color: Color(0xFF1D1D1F)),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async => _refresh(),
          color: const Color(0xFF0066CC),
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            children: [
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFFF5F5F7),
                        ),
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.qr_code_scanner,
                          color: Color(0xFF0066CC),
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
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1D1D1F),
                                letterSpacing: -0.374,
                              ),
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              'Shared attendance scanner',
                              style: TextStyle(
                                fontSize: 14,
                                color: Color(0xFF7A7A7A),
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

              // Status panel builder
              FutureBuilder<AttendanceStatus>(
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
              const SizedBox(height: 24),

              const Text(
                'QUICK ACTIONS',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.0,
                  color: Color(0xFF7A7A7A),
                ),
              ),
              const SizedBox(height: 12),

              // Quick action buttons designed as modern dashboard cards
              ScaleOnPress(
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => AttendanceScreen(session: widget.session),
                    ),
                  );
                  _refresh();
                },
                child: const _QuickActionCard(
                  title: 'Scan Attendance',
                  subtitle: 'Identify employee and check in or out',
                  icon: Icons.qr_code_scanner,
                  iconColor: Color(0xFF0066CC),
                ),
              ),
              const SizedBox(height: 12),
              ScaleOnPress(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SettingsScreen(
                        session: widget.session,
                        onLogout: widget.onLogout,
                      ),
                    ),
                  );
                },
                child: const _QuickActionCard(
                  title: 'Configuration Settings',
                  subtitle: 'View active database and session details',
                  icon: Icons.tune,
                  iconColor: Color(0xFF7A7A7A),
                ),
              ),
            ],
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
    required this.iconColor,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(11), // rounded.md (11px)
              ),
              child: Icon(icon, color: iconColor, size: 28),
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
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1D1D1F),
                      letterSpacing: -0.374,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF7A7A7A),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Color(0xFF7A7A7A)),
          ],
        ),
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
        ? const Color(0xFF30D158) // Apple green
        : const Color(0xFF7A7A7A);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  loading
                      ? 'Checking scanner...'
                      : online
                      ? 'SCANNER READY'
                      : 'SCANNER OFFLINE',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                    color: statusColor,
                  ),
                ),
              ],
            ),
            const Divider(height: 24, thickness: 0.5, color: Color(0xFFE0E0E0)),
            Row(
              children: [
                const Icon(Icons.devices, color: Color(0xFF0066CC), size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Device ID: $scannerId',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: Color(0xFF1D1D1F),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

