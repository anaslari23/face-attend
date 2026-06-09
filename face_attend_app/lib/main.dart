import 'package:flutter/material.dart';

import 'src/api/odoo_face_attendance_client.dart';
import 'src/models/session.dart';
import 'src/screens/attendance_screen.dart';
import 'src/screens/enrollment_screen.dart';
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
    final restored = await _sessionStore.read();
    if (!mounted) return;
    setState(() {
      _session = restored;
      _loading = false;
    });
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
    final employee = widget.session.employee;
    final initials = employee.name.split(' ').map((e) => e.isNotEmpty ? e[0] : '').take(2).join().toUpperCase();

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
              style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.5),
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
              // Employee Profile Card
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
                        child: Text(
                          initials,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              employee.name,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1E1E1E),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              employee.department ?? 'No Department',
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
                  final status = snapshot.data;
                  return _StatusPanel(
                    loading: snapshot.connectionState == ConnectionState.waiting,
                    checkedIn: status?.checkedIn ?? false,
                    checkIn: status?.checkIn,
                    faceRegistered: employee.faceRegistered,
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
                subtitle: 'Verify your face to check in or out',
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
                title: 'Register Face Template',
                subtitle: 'Capture 3 samples for your biometric ID',
                icon: Icons.face,
                iconColor: const Color(0xFFFFC107),
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => EnrollmentScreen(session: widget.session),
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
    required this.checkedIn,
    required this.faceRegistered,
    this.checkIn,
  });

  final bool loading;
  final bool checkedIn;
  final bool faceRegistered;
  final DateTime? checkIn;

  @override
  Widget build(BuildContext context) {
    final statusColor = checkedIn ? const Color(0xFF2ECC71) : const Color(0xFF95A5A6);
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
                      ? 'Checking status...'
                      : checkedIn
                          ? 'CURRENTLY CHECKED IN'
                          : 'CURRENTLY CHECKED OUT',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    color: statusColor,
                  ),
                ),
              ],
            ),
            if (checkIn != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.access_time_filled, size: 16, color: Colors.grey.shade600),
                  const SizedBox(width: 8),
                  Text(
                    'Checked in at: ${checkIn!.toLocal().toString().substring(11, 16)}',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                  ),
                ],
              ),
            ],
            const Divider(height: 24, thickness: 0.5),
            Row(
              children: [
                Icon(
                  faceRegistered ? Icons.verified_user : Icons.warning_amber_rounded,
                  color: faceRegistered ? const Color(0xFF2ECC71) : const Color(0xFFFF9800),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  faceRegistered ? 'Biometric template registered' : 'Enrollment required',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: faceRegistered ? Colors.grey.shade800 : const Color(0xFFFF9800),
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
