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
          seedColor: const Color(0xFFFF6B35),
          primary: const Color(0xFFFF6B35),
          secondary: const Color(0xFFFFC107),
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF8F9FA),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Color(0xFF1E1E1E),
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(
            color: Color(0xFF1E1E1E),
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 2,
          shadowColor: Colors.black.withValues(alpha: 0.05),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
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
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFFFF6B35).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.face_retouching_natural,
                color: Color(0xFFFF6B35),
                size: 20,
              ),
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
            icon: const Icon(Icons.sync, color: Color(0xFF555555)),
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
            icon: const Icon(Icons.settings, color: Color(0xFF555555)),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async => _refresh(),
          color: const Color(0xFFFF6B35),
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            children: [
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        width: 54,
                        height: 54,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFFFF6B35), Color(0xFFFFC107)],
                          ),
                        ),
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.qr_code_scanner,
                          color: Colors.white,
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
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1E1E1E),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Shared attendance scanner',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade600,
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
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 12),

              // Quick action buttons designed as modern dashboard cards
              _QuickActionCard(
                title: 'Scan Attendance',
                subtitle: 'Identify employee and check in or out',
                icon: Icons.qr_code_scanner,
                iconColor: const Color(0xFFFF6B35),
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => AttendanceScreen(session: widget.session),
                    ),
                  );
                  _refresh();
                },
              ),
              const SizedBox(height: 12),
              _QuickActionCard(
                title: 'Configuration Settings',
                subtitle: 'View active database and session details',
                icon: Icons.tune,
                iconColor: Colors.blueGrey,
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
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color iconColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
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
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E1E1E),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey.shade400),
            ],
          ),
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
        ? const Color(0xFF2ECC71)
        : const Color(0xFF95A5A6);
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
                    boxShadow: [
                      BoxShadow(
                        color: statusColor.withValues(alpha: 0.4),
                        blurRadius: 6,
                        spreadRadius: 2,
                      ),
                    ],
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
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    color: statusColor,
                  ),
                ),
              ],
            ),
            const Divider(height: 24, thickness: 0.5),
            Row(
              children: [
                Icon(Icons.devices, color: const Color(0xFFFF6B35), size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Device ID: $scannerId',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey.shade800,
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
