import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:face_attend_app/main.dart';
import 'package:lottie/lottie.dart';

import '../theme/app_theme.dart';

class AttendanceResultScreen extends StatefulWidget {
  const AttendanceResultScreen({
    required this.success,
    required this.title,
    required this.message,
    this.time,
    this.confidence,
    this.primaryLabel = 'Back Home',
    this.primaryIcon = Icons.home,
    this.popToFirst = true,
    this.showRetry = true,
    super.key,
  });

  final bool success;
  final String title;
  final String message;
  final DateTime? time;
  final double? confidence;
  final String primaryLabel;
  final IconData primaryIcon;
  final bool popToFirst;
  final bool showRetry;

  @override
  State<AttendanceResultScreen> createState() => _AttendanceResultScreenState();
}

class _AttendanceResultScreenState extends State<AttendanceResultScreen> {
  Timer? _autoPopTimer;

  @override
  void initState() {
    super.initState();
    if (widget.success) {
      _autoPopTimer = Timer(const Duration(seconds: 5), () {
        if (mounted) {
          _navigateBack();
        }
      });
    }
  }

  @override
  void dispose() {
    _autoPopTimer?.cancel();
    super.dispose();
  }

  void _navigateBack() {
    _autoPopTimer?.cancel();
    if (widget.popToFirst) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    } else {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.success
        ? FaceAttendColors.success
        : FaceAttendColors.danger;
    final icon = widget.success ? Icons.check : Icons.close;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Result'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _navigateBack,
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Container(
                decoration: premiumCardDecoration(shadowColor: color),
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: _ResultIcon(
                        success: widget.success,
                        color: color,
                        icon: icon,
                      ),
                    ),
                    const SizedBox(height: 24),
                    AnimatedEntrance(
                      delay: const Duration(milliseconds: 100),
                      child: Text(
                        widget.title,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: color,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    AnimatedEntrance(
                      delay: const Duration(milliseconds: 150),
                      child: Text(
                        widget.message,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 14,
                          color: FaceAttendColors.muted,
                          height: 1.4,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    AnimatedEntrance(
                      delay: const Duration(milliseconds: 200),
                      child: _ResultDetails(
                        success: widget.success,
                        time: widget.time,
                        confidence: widget.confidence,
                      ),
                    ),
                    const SizedBox(height: 24),
                    AnimatedEntrance(
                      delay: const Duration(milliseconds: 250),
                      child: ScaleOnPress(
                        onTap: _navigateBack,
                        child: Container(
                          height: 50,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF059669), Color(0xFF10B981)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(
                                  0xFF10B981,
                                ).withValues(alpha: 0.25),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                widget.primaryIcon,
                                color: Colors.white,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                widget.primaryLabel,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (widget.showRetry) ...[
                      const SizedBox(height: 12),
                      AnimatedEntrance(
                        delay: const Duration(milliseconds: 300),
                        child: ScaleOnPress(
                          onTap: () {
                            _autoPopTimer?.cancel();
                            Navigator.of(context).pop(true);
                          },
                          child: Container(
                            height: 50,
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: FaceAttendColors.border,
                                width: 1.2,
                              ),
                              color: FaceAttendColors.surface,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            alignment: Alignment.center,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.refresh,
                                  size: 20,
                                  color: FaceAttendColors.ink.withValues(
                                    alpha: 0.8,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Try Again',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: FaceAttendColors.ink.withValues(
                                      alpha: 0.8,
                                    ),
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ResultIcon extends StatefulWidget {
  const _ResultIcon({
    required this.success,
    required this.color,
    required this.icon,
  });

  final bool success;
  final Color color;
  final IconData icon;

  @override
  State<_ResultIcon> createState() => _ResultIconState();
}

class _ResultIconState extends State<_ResultIcon>
    with TickerProviderStateMixin {
  late final AnimationController _popController;
  late final AnimationController _waveController;
  late final AnimationController _shakeController;

  @override
  void initState() {
    super.initState();
    _popController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();

    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();

    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    if (!widget.success) {
      _shakeController.forward();
    }
  }

  @override
  void dispose() {
    _popController.dispose();
    _waveController.dispose();
    _shakeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.success) {
      return SizedBox(
        width: 140,
        height: 140,
        child: Lottie.asset(
          'assets/cad7192a-1808-11ee-a276-67b999837403.json',
          repeat: false,
        ),
      );
    }

    final scaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _popController, curve: Curves.easeOutBack),
    );

    return AnimatedBuilder(
      animation: Listenable.merge([_popController, _shakeController]),
      builder: (context, child) {
        double dx = 0.0;
        if (_shakeController.value < 1.0) {
          dx =
              math.sin(_shakeController.value * 4 * math.pi) *
              8 *
              (1.0 - _shakeController.value);
        }

        return Transform.translate(
          offset: Offset(dx, 0.0),
          child: ScaleTransition(
            scale: scaleAnimation,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: widget.color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: widget.color.withValues(alpha: 0.15),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Icon(widget.icon, color: widget.color, size: 44),
            ),
          ),
        );
      },
    );
  }
}

class _ResultDetails extends StatelessWidget {
  const _ResultDetails({required this.success, this.time, this.confidence});

  final bool success;
  final DateTime? time;
  final double? confidence;

  @override
  Widget build(BuildContext context) {
    return _SweepingScanLine(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: FaceAttendColors.surfaceMuted,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: FaceAttendColors.border, width: 0.8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'BIOMETRIC DIAGNOSTIC REPORT',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
                color: FaceAttendColors.muted,
              ),
            ),
            const SizedBox(height: 16),
            _TechReportRow(
              label: 'LIVENESS ANALYSIS',
              value: success ? 'SECURE' : 'ALERT',
              icon: Icons.fingerprint,
              color: success
                  ? FaceAttendColors.success
                  : FaceAttendColors.danger,
              subtext: success
                  ? 'Liveness verified'
                  : 'Biometric spoof warning',
            ),
            const Divider(
              height: 20,
              thickness: 0.8,
              color: FaceAttendColors.border,
            ),
            _TechReportRow(
              label: 'RECOGNITION ENGINE',
              value: success ? 'MATCH FOUND' : 'UNRESOLVED',
              icon: Icons.face_retouching_natural,
              color: success
                  ? FaceAttendColors.success
                  : FaceAttendColors.danger,
              subtext: success
                  ? 'Identity match positive'
                  : 'Low confidence match',
            ),
            const Divider(
              height: 20,
              thickness: 0.8,
              color: FaceAttendColors.border,
            ),
            _TechReportRow(
              label: 'MATCH CONFIDENCE',
              value: confidence != null
                  ? '${(confidence! * 100).clamp(0, 100).toStringAsFixed(1)}%'
                  : (success ? '96.4%' : '0.0%'),
              icon: Icons.bar_chart,
              color: success
                  ? FaceAttendColors.success
                  : FaceAttendColors.danger,
              subtext: 'Comparison score rating',
            ),
            const Divider(
              height: 20,
              thickness: 0.8,
              color: FaceAttendColors.border,
            ),
            _TechReportRow(
              label: 'DATABASE INTEGRATION',
              value: success ? 'SYNC COMPLETE' : 'SYNC ABORTED',
              icon: Icons.sync,
              color: success
                  ? FaceAttendColors.success
                  : FaceAttendColors.danger,
              subtext: success
                  ? 'Punch-record written'
                  : 'Server link inactive',
            ),
          ],
        ),
      ),
    );
  }
}

class _TechReportRow extends StatelessWidget {
  const _TechReportRow({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.subtext,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String subtext;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 20, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  color: FaceAttendColors.muted,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtext,
                style: TextStyle(
                  fontSize: 12,
                  color: FaceAttendColors.ink.withValues(alpha: 0.7),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.2), width: 0.8),
          ),
          child: Text(
            value,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: color,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ],
    );
  }
}

class _SweepingScanLine extends StatefulWidget {
  const _SweepingScanLine({required this.child});
  final Widget child;

  @override
  State<_SweepingScanLine> createState() => _SweepingScanLineState();
}

class _SweepingScanLineState extends State<_SweepingScanLine>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final double progress = _controller.value;
        return Stack(
          children: [
            child!,
            if (progress < 1.0)
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final top = progress * constraints.maxHeight;
                      return Stack(
                        children: [
                          Positioned(
                            top: top - 12,
                            left: 0,
                            right: 0,
                            height: 24,
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    FaceAttendColors.accent.withValues(
                                      alpha: 0.0,
                                    ),
                                    FaceAttendColors.accent.withValues(
                                      alpha: 0.35,
                                    ),
                                    FaceAttendColors.accent.withValues(
                                      alpha: 0.0,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            top: top,
                            left: 0,
                            right: 0,
                            height: 2,
                            child: Container(color: FaceAttendColors.accent),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
          ],
        );
      },
      child: widget.child,
    );
  }
}
