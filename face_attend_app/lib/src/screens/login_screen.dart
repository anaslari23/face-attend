import 'package:flutter/material.dart';

import '../api/odoo_face_attendance_client.dart';
import '../models/session.dart';
import '../services/device_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({required this.onLoggedIn, super.key});

  final ValueChanged<MobileSession> onLoggedIn;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _baseUrl = TextEditingController(text: 'https://your-odoo-domain.com');
  final _db = TextEditingController();
  final _login = TextEditingController();
  final _password = TextEditingController();
  final _middlewareUrl = TextEditingController(text: 'http://127.0.0.1:8019');
  final _middlewareApiKey = TextEditingController(text: 'change-me');
  final _deviceService = DeviceService();
  bool _loading = false;
  bool _fetchingDb = false;
  List<String>? _availableDbs;

  @override
  void dispose() {
    _baseUrl.dispose();
    _db.dispose();
    _login.dispose();
    _password.dispose();
    _middlewareUrl.dispose();
    _middlewareApiKey.dispose();
    super.dispose();
  }

  Future<void> _fetchDbs() async {
    if (_baseUrl.text.trim().isEmpty) return;
    setState(() => _fetchingDb = true);
    try {
      final client = OdooFaceAttendanceClient(baseUrl: _baseUrl.text.trim());
      final dbs = await client.listDatabases();
      setState(() {
        _availableDbs = dbs;
        if (dbs.isNotEmpty && !_availableDbs!.contains(_db.text)) {
          _db.text = dbs.first;
        }
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Found ${dbs.length} databases')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to fetch DBs: $e')));
      }
    } finally {
      if (mounted) setState(() => _fetchingDb = false);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final device = await _deviceService.identity();
      final client = OdooFaceAttendanceClient(baseUrl: _baseUrl.text.trim());
      final session = await client.login(
        db: _db.text.trim(),
        login: _login.text.trim(),
        password: _password.text,
        deviceId: device.id,
        deviceName: device.name,
        middlewareUrl: _middlewareUrl.text.trim(),
        middlewareApiKey: _middlewareApiKey.text.trim(),
      );
      widget.onLoggedIn(session);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Logo & Header
                  Container(
                    width: 72,
                    height: 72,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [Color(0xFFFF6B35), Color(0xFFFFC107)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.face_retouching_natural,
                      size: 38,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'FaceAttend',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF1E1E1E),
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Biometric Enterprise Portal',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Floating Login Card
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'SIGN IN',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.0,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _baseUrl,
                              decoration: const InputDecoration(
                                labelText: 'Odoo Server URL',
                                prefixIcon: Icon(Icons.dns, size: 20),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.all(
                                    Radius.circular(12),
                                  ),
                                ),
                              ),
                              keyboardType: TextInputType.url,
                              validator: _required,
                            ),
                            const SizedBox(height: 16),
                            if (_availableDbs != null &&
                                _availableDbs!.isNotEmpty)
                              DropdownButtonFormField<String>(
                                initialValue: _availableDbs!.contains(_db.text)
                                    ? _db.text
                                    : null,
                                decoration: InputDecoration(
                                  labelText: 'Database',
                                  prefixIcon: const Icon(
                                    Icons.storage,
                                    size: 20,
                                  ),
                                  border: const OutlineInputBorder(
                                    borderRadius: BorderRadius.all(
                                      Radius.circular(12),
                                    ),
                                  ),
                                  suffixIcon: _fetchingDb
                                      ? const Padding(
                                          padding: EdgeInsets.all(12),
                                          child: SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          ),
                                        )
                                      : IconButton(
                                          icon: const Icon(
                                            Icons.sync,
                                            size: 20,
                                          ),
                                          onPressed: _fetchDbs,
                                          tooltip: 'Refresh Databases',
                                        ),
                                ),
                                items: _availableDbs!.map((db) {
                                  return DropdownMenuItem(
                                    value: db,
                                    child: Text(db),
                                  );
                                }).toList(),
                                onChanged: (val) {
                                  if (val != null) {
                                    _db.text = val;
                                  }
                                },
                                validator: _required,
                              )
                            else
                              TextFormField(
                                controller: _db,
                                decoration: InputDecoration(
                                  labelText: 'Database Name',
                                  prefixIcon: const Icon(
                                    Icons.storage,
                                    size: 20,
                                  ),
                                  border: const OutlineInputBorder(
                                    borderRadius: BorderRadius.all(
                                      Radius.circular(12),
                                    ),
                                  ),
                                  suffixIcon: _fetchingDb
                                      ? const Padding(
                                          padding: EdgeInsets.all(12),
                                          child: SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          ),
                                        )
                                      : IconButton(
                                          icon: const Icon(
                                            Icons.search,
                                            size: 20,
                                          ),
                                          onPressed: _fetchDbs,
                                          tooltip: 'Fetch Databases',
                                        ),
                                ),
                                validator: _required,
                              ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _login,
                              decoration: const InputDecoration(
                                labelText: 'Email Address',
                                prefixIcon: Icon(Icons.email, size: 20),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.all(
                                    Radius.circular(12),
                                  ),
                                ),
                              ),
                              keyboardType: TextInputType.emailAddress,
                              validator: _required,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _password,
                              decoration: const InputDecoration(
                                labelText: 'Password',
                                prefixIcon: Icon(Icons.lock, size: 20),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.all(
                                    Radius.circular(12),
                                  ),
                                ),
                              ),
                              obscureText: true,
                              validator: _required,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _middlewareUrl,
                              decoration: const InputDecoration(
                                labelText: 'Middleware URL',
                                prefixIcon: Icon(Icons.hub, size: 20),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.all(
                                    Radius.circular(12),
                                  ),
                                ),
                              ),
                              keyboardType: TextInputType.url,
                              validator: _required,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _middlewareApiKey,
                              decoration: const InputDecoration(
                                labelText: 'Middleware API Key',
                                prefixIcon: Icon(Icons.key, size: 20),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.all(
                                    Radius.circular(12),
                                  ),
                                ),
                              ),
                              obscureText: true,
                              validator: _required,
                            ),
                            const SizedBox(height: 24),

                            // Gradient Sign-In Button
                            Container(
                              height: 52,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFFFF6B35),
                                    Color(0xFFFFC107),
                                  ],
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                ),
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(
                                      0xFFFF6B35,
                                    ).withValues(alpha: 0.3),
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
                                onPressed: _loading ? null : _submit,
                                child: _loading
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.login,
                                            color: Colors.white,
                                          ),
                                          SizedBox(width: 8),
                                          Text(
                                            'Sign In',
                                            style: TextStyle(
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
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String? _required(String? value) {
    return value == null || value.trim().isEmpty ? 'Required' : null;
  }
}
