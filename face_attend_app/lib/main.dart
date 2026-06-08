import 'package:flutter/material.dart';

import 'src/api/odoo_face_attendance_client.dart';
import 'src/models/session.dart';
import 'src/screens/attendance_screen.dart';
import 'src/screens/enrollment_screen.dart';
import 'src/screens/login_screen.dart';
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
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff176b5b)),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xfff7faf8),
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
    setState(() => _statusFuture = _client.status());
  }

  @override
  Widget build(BuildContext context) {
    final employee = widget.session.employee;
    return Scaffold(
      appBar: AppBar(
        title: const Text('FaceAttend'),
        actions: [
          IconButton(
            onPressed: _refresh,
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            onPressed: widget.onLogout,
            tooltip: 'Logout',
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(employee.name, style: Theme.of(context).textTheme.headlineSmall),
            if (employee.department != null)
              Text(employee.department!, style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 20),
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
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => AttendanceScreen(session: widget.session),
                  ),
                );
                _refresh();
              },
              icon: const Icon(Icons.face),
              label: const Text('Scan Attendance'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => EnrollmentScreen(session: widget.session),
                  ),
                );
                _refresh();
              },
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Enroll My Face'),
            ),
          ],
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
    final color = checkedIn ? Colors.green.shade700 : Colors.blueGrey.shade700;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(checkedIn ? Icons.login : Icons.logout, color: color),
              const SizedBox(width: 10),
              Text(
                loading ? 'Checking status...' : checkedIn ? 'Checked in' : 'Checked out',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(color: color),
              ),
            ],
          ),
          if (checkIn != null) ...[
            const SizedBox(height: 8),
            Text('Check-in: ${checkIn!.toLocal()}'),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                faceRegistered ? Icons.verified_user : Icons.warning_amber,
                color: faceRegistered ? Colors.green.shade700 : Colors.orange.shade800,
              ),
              const SizedBox(width: 8),
              Text(faceRegistered ? 'Face enrolled' : 'Face enrollment required'),
            ],
          ),
        ],
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
