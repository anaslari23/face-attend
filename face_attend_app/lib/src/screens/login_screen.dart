import 'package:flutter/material.dart';

import '../api/odoo_face_attendance_client.dart';
import '../models/session.dart';
import '../theme/app_theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({required this.onLoggedIn, super.key});

  final ValueChanged<MobileSession> onLoggedIn;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _baseUrl = TextEditingController(text: 'http://192.168.1.25:8069');
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
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: FaceAttendColors.accentSoft,
                        border: Border.all(color: FaceAttendColors.border),
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.qr_code_scanner,
                        size: 38,
                        color: FaceAttendColors.accent,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'FaceAttend',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 34, // display-md
                      fontWeight: FontWeight.w600,
                      color: FaceAttendColors.ink,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Shared Scanner Setup',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14, // caption
                      color: FaceAttendColors.muted,
                      fontWeight: FontWeight.w400,
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
                            const Text(
                              'SCANNER CONFIGURATION',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1.0,
                                color: FaceAttendColors.muted,
                              ),
                            ),
                            const SizedBox(height: 20),
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
                                        icon: const Icon(
                                          Icons.sync,
                                          size: 20,
                                          color: FaceAttendColors.muted,
                                        ),
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
                                                color: FaceAttendColors.muted,
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
                            _ScaleOnPress(
                              onTap: _loading ? () {} : _submit,
                              child: Container(
                                height: 44, // button height
                                decoration: BoxDecoration(
                                  color: FaceAttendColors.accent,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                alignment: Alignment.center,
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
                                          fontSize: 14,
                                          fontWeight: FontWeight.w400,
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
      labelStyle: const TextStyle(color: FaceAttendColors.muted, fontSize: 14),
      prefixIcon: Icon(icon, size: 20, color: FaceAttendColors.muted),
      filled: true,
      fillColor: FaceAttendColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
        borderSide: BorderSide(color: FaceAttendColors.border, width: 1.0),
      ),
      enabledBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
        borderSide: BorderSide(color: FaceAttendColors.border, width: 1.0),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
        borderSide: BorderSide(color: FaceAttendColors.accent, width: 1.5),
      ),
    );
  }

  String? _required(String? value) {
    return value == null || value.trim().isEmpty ? 'Required' : null;
  }
}

class _ScaleOnPress extends StatefulWidget {
  const _ScaleOnPress({required this.child, required this.onTap});
  final Widget child;
  final VoidCallback onTap;

  @override
  State<_ScaleOnPress> createState() => _ScaleOnPressState();
}

class _ScaleOnPressState extends State<_ScaleOnPress> {
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
