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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Found ${dbs.length} databases')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to fetch DBs: $e')));
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
      );
      widget.onLoggedIn(session);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: ListView(
              padding: const EdgeInsets.all(24),
              shrinkWrap: true,
              children: [
                const Icon(Icons.face_retouching_natural, size: 58),
                const SizedBox(height: 16),
                Text('FaceAttend', style: Theme.of(context).textTheme.headlineMedium, textAlign: TextAlign.center),
                const SizedBox(height: 28),
                Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _baseUrl,
                        decoration: const InputDecoration(labelText: 'Odoo URL', border: OutlineInputBorder()),
                        keyboardType: TextInputType.url,
                        validator: _required,
                      ),
                      const SizedBox(height: 12),
                      if (_availableDbs != null && _availableDbs!.isNotEmpty)
                        DropdownButtonFormField<String>(
                          value: _availableDbs!.contains(_db.text) ? _db.text : null,
                          decoration: InputDecoration(
                            labelText: 'Database',
                            border: const OutlineInputBorder(),
                            suffixIcon: _fetchingDb
                                ? const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                                  )
                                : IconButton(
                                    icon: const Icon(Icons.sync),
                                    onPressed: _fetchDbs,
                                    tooltip: 'Refresh Databases',
                                  ),
                          ),
                          items: _availableDbs!.map((db) {
                            return DropdownMenuItem(value: db, child: Text(db));
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
                            labelText: 'Database',
                            border: const OutlineInputBorder(),
                            suffixIcon: _fetchingDb
                                ? const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                                  )
                                : IconButton(
                                    icon: const Icon(Icons.search),
                                    onPressed: _fetchDbs,
                                    tooltip: 'Fetch Databases',
                                  ),
                          ),
                          validator: _required,
                        ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _login,
                        decoration: const InputDecoration(labelText: 'Email / Login', border: OutlineInputBorder()),
                        validator: _required,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _password,
                        decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder()),
                        obscureText: true,
                        validator: _required,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _loading ? null : _submit,
                  icon: _loading
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.login),
                  label: const Text('Login'),
                ),
              ],
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
