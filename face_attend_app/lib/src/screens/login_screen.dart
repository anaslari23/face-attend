import 'package:flutter/material.dart';

import '../api/odoo_face_attendance_client.dart';
import '../models/session.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({required this.onLoggedIn, super.key});

  final ValueChanged<MobileSession> onLoggedIn;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _baseUrl = TextEditingController(text: 'http://192.168.1.61:8069');
  final _db = TextEditingController();
  final _setupCode = TextEditingController();
  bool _loading = false;
  bool _fetchingDb = false;
  List<String>? _availableDbs;

  @override
  void dispose() {
    _baseUrl.dispose();
    _db.dispose();
    _setupCode.dispose();
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
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to fetch DBs: $error')));
      }
    } finally {
      if (mounted) setState(() => _fetchingDb = false);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final client = OdooFaceAttendanceClient(baseUrl: _baseUrl.text.trim());
      final session = await client.setupScanner(
        db: _db.text.trim(),
        setupCode: _setupCode.text.trim(),
      );
      await OdooFaceAttendanceClient(
        baseUrl: session.baseUrl,
        db: session.db,
        token: session.token,
      ).status();
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
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
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
                      Icons.qr_code_scanner,
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
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Shared Scanner Setup',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 32),
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
                              'SCANNER CONFIGURATION',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.0,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            const SizedBox(height: 16),
                            _field(
                              _baseUrl,
                              'Odoo Server URL',
                              Icons.dns,
                              keyboardType: TextInputType.url,
                            ),
                            const SizedBox(height: 16),
                            if (_availableDbs != null &&
                                _availableDbs!.isNotEmpty)
                              DropdownButtonFormField<String>(
                                initialValue: _availableDbs!.contains(_db.text)
                                    ? _db.text
                                    : null,
                                decoration:
                                    _decoration(
                                      'Database',
                                      Icons.storage,
                                    ).copyWith(
                                      suffixIcon: IconButton(
                                        icon: const Icon(Icons.sync, size: 20),
                                        onPressed: _fetchingDb
                                            ? null
                                            : _fetchDbs,
                                        tooltip: 'Refresh Databases',
                                      ),
                                    ),
                                items: _availableDbs!
                                    .map(
                                      (db) => DropdownMenuItem(
                                        value: db,
                                        child: Text(db),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (val) {
                                  if (val != null) _db.text = val;
                                },
                                validator: _required,
                              )
                            else
                              TextFormField(
                                controller: _db,
                                decoration:
                                    _decoration(
                                      'Database Name',
                                      Icons.storage,
                                    ).copyWith(
                                      suffixIcon: _fetchingDb
                                          ? const Padding(
                                              padding: EdgeInsets.all(12),
                                              child: SizedBox(
                                                width: 16,
                                                height: 16,
                                                child:
                                                    CircularProgressIndicator(
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
                            _field(
                              _setupCode,
                              'Scanner Setup Code',
                              Icons.vpn_key,
                              obscureText: true,
                            ),
                            const SizedBox(height: 24),
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
                                    : const Text(
                                        'Save Scanner',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
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

  TextFormField _field(
    TextEditingController controller,
    String label,
    IconData icon, {
    bool obscureText = false,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      decoration: _decoration(label, icon),
      obscureText: obscureText,
      keyboardType: keyboardType,
      validator: validator ?? _required,
    );
  }

  InputDecoration _decoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 20),
      border: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
    );
  }

  String? _required(String? value) {
    return value == null || value.trim().isEmpty ? 'Required' : null;
  }
}
