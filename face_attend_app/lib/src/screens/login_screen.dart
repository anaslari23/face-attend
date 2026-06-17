import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:face_attend_app/main.dart';

import '../api/odoo_face_attendance_client.dart';
import '../models/session.dart';
import '../theme/app_theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({required this.onLoggedIn, super.key});

  final ValueChanged<MobileSession> onLoggedIn;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _baseUrl = TextEditingController(text: 'http://192.168.1.25:8069');
  final _db = TextEditingController();
  final _setupCode = TextEditingController();
  bool _loading = false;
  bool _fetchingDb = false;
  List<String>? _availableDbs;
  late final AnimationController _meshController;

  @override
  void initState() {
    super.initState();
    _meshController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();
  }

  @override
  void dispose() {
    _meshController.dispose();
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
                  AnimatedEntrance(
                    delay: const Duration(milliseconds: 50),
                    child: Center(
                      child: Container(
                        width: 140,
                        height: 140,
                        alignment: Alignment.center,
                        child: AnimatedBuilder(
                          animation: _meshController,
                          builder: (context, child) {
                            return CustomPaint(
                              size: const Size(140, 140),
                              painter: BiometricFaceGridPainter(
                                animationValue: _meshController.value,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const AnimatedEntrance(
                    delay: Duration(milliseconds: 100),
                    child: Text(
                      'FaceAttend',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1.0,
                        color: FaceAttendColors.ink,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const AnimatedEntrance(
                    delay: Duration(milliseconds: 150),
                    child: Text(
                      'Shared Scanner Setup',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: FaceAttendColors.muted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  AnimatedEntrance(
                    delay: const Duration(milliseconds: 200),
                    child: Container(
                      decoration: premiumCardDecoration(
                        shadowColor: FaceAttendColors.accent,
                      ),
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
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.2,
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
                                isExpanded: true,
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
                                        child: Text(
                                          db,
                                          overflow: TextOverflow.ellipsis,
                                        ),
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
                                              child: AppLoader(size: 16),
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
                            const SizedBox(height: 28),
                            ScaleOnPress(
                              onTap: _loading ? () {} : _submit,
                              child: Container(
                                height: 50,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFFEDA672),
                                      Color(0xFFE57C38),
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(
                                        0xFFEDA672,
                                      ).withValues(alpha: 0.3),
                                      blurRadius: 12,
                                      offset: const Offset(0, 6),
                                    ),
                                  ],
                                ),
                                alignment: Alignment.center,
                                child: _loading
                                    ? const AppLoader(size: 22)
                                    : const Text(
                                        'Save Scanner',
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  AnimatedEntrance(
                    delay: const Duration(milliseconds: 300),
                    child: FloatingWidget(
                      child: Container(
                        margin: const EdgeInsets.only(top: 24),
                        decoration: premiumCardDecoration(
                          shadowColor: FaceAttendColors.accent,
                        ),
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: FaceAttendColors.accentSoft,
                              ),
                              child: const Icon(
                                Icons.info_outline,
                                color: FaceAttendColors.accent,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Setup Instructions',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: FaceAttendColors.ink,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    'Point the app to your Odoo server and enter the scanner setup code from the backend. Face matching runs on this phone.',
                                    style: TextStyle(
                                      fontSize: 12,
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
      fillColor: FaceAttendColors.surfaceMuted,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: FaceAttendColors.border, width: 0.8),
      ),
      enabledBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: FaceAttendColors.border, width: 0.8),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: FaceAttendColors.accent, width: 1.6),
      ),
    );
  }

  String? _required(String? value) {
    return value == null || value.trim().isEmpty ? 'Required' : null;
  }
}

class BiometricFaceGridPainter extends CustomPainter {
  BiometricFaceGridPainter({required this.animationValue});
  final double animationValue;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = FaceAttendColors.accent.withValues(alpha: 0.15);

    final highlightPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = FaceAttendColors.accent.withValues(alpha: 0.45);

    final dotPaint = Paint()
      ..color = FaceAttendColors.accent
      ..style = PaintingStyle.fill;

    final cx = size.width / 2;
    final cy = size.height / 2;
    final rx = size.width * 0.35;
    final ry = size.height * 0.42;

    final List<Offset> outerOval = [];
    const count = 16;
    for (int i = 0; i < count; i++) {
      final angle = i * 2 * math.pi / count;
      final dx = math.sin(animationValue * 2 * math.pi + angle) * 6.0;
      outerOval.add(
        Offset(
          cx + rx * math.cos(angle) + dx * math.sin(angle),
          cy + ry * math.sin(angle),
        ),
      );
    }

    for (int i = 0; i < count; i++) {
      canvas.drawLine(outerOval[i], outerOval[(i + 1) % count], paint);
    }

    final leftEye = Offset(
      cx - rx * 0.35 + math.sin(animationValue * 2 * math.pi) * 3,
      cy - ry * 0.15,
    );
    final rightEye = Offset(
      cx + rx * 0.35 + math.sin(animationValue * 2 * math.pi) * 3,
      cy - ry * 0.15,
    );
    final noseTip = Offset(
      cx + math.sin(animationValue * 2 * math.pi + 1) * 4,
      cy + ry * 0.1,
    );
    final noseBridge = Offset(
      cx + math.sin(animationValue * 2 * math.pi + 0.5) * 2,
      cy - ry * 0.12,
    );
    final mouthLeft = Offset(cx - rx * 0.22, cy + ry * 0.4);
    final mouthRight = Offset(cx + rx * 0.22, cy + ry * 0.4);
    final mouthCenter = Offset(
      cx,
      cy + ry * 0.45 + math.cos(animationValue * 2 * math.pi) * 3,
    );

    canvas.drawCircle(leftEye, 2, dotPaint);
    canvas.drawCircle(rightEye, 2, dotPaint);
    final eyeBox1 = Rect.fromCircle(center: leftEye, radius: 10);
    final eyeBox2 = Rect.fromCircle(center: rightEye, radius: 10);
    canvas.drawOval(eyeBox1, paint);
    canvas.drawOval(eyeBox2, paint);

    canvas.drawLine(leftEye, noseBridge, paint);
    canvas.drawLine(rightEye, noseBridge, paint);
    canvas.drawLine(noseBridge, noseTip, paint);

    canvas.drawLine(noseTip, mouthLeft, paint);
    canvas.drawLine(noseTip, mouthRight, paint);
    canvas.drawLine(mouthLeft, mouthCenter, paint);
    canvas.drawLine(mouthRight, mouthCenter, paint);
    canvas.drawLine(mouthLeft, mouthRight, paint);

    for (int i = 0; i < count; i++) {
      final p = outerOval[i];
      if (p.dy < cy) {
        if (p.dx < cx) {
          canvas.drawLine(p, leftEye, paint);
        } else {
          canvas.drawLine(p, rightEye, paint);
        }
      } else {
        if (p.dx < cx) {
          canvas.drawLine(p, mouthLeft, paint);
        } else {
          canvas.drawLine(p, mouthRight, paint);
        }
        canvas.drawLine(p, mouthCenter, paint);
      }
    }

    final sweepY =
        (cy - ry) +
        (ry * 2 * ((math.sin(animationValue * 2 * math.pi) + 1) / 2));
    canvas.drawLine(
      Offset(cx - rx - 10, sweepY),
      Offset(cx + rx + 10, sweepY),
      highlightPaint,
    );
  }

  @override
  bool shouldRepaint(covariant BiometricFaceGridPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue;
  }
}
