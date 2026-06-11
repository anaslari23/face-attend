import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class AttendanceResultScreen extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final color = success ? FaceAttendColors.success : FaceAttendColors.danger;
    final icon = success ? Icons.check : Icons.close;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Result'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0.92, end: 1),
                        duration: const Duration(milliseconds: 240),
                        curve: Curves.easeOutCubic,
                        builder: (context, scale, child) {
                          return Transform.scale(scale: scale, child: child);
                        },
                        child: Center(
                          child: Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: Icon(icon, color: color, size: 44),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          color: color,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        message,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 14,
                          color: FaceAttendColors.muted,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 24),
                      _ResultDetails(time: time, confidence: confidence),
                      const SizedBox(height: 24),
                      _ScaleOnPress(
                        onTap: () {
                          if (popToFirst) {
                            Navigator.of(
                              context,
                            ).popUntil((route) => route.isFirst);
                          } else {
                            Navigator.of(context).pop(true);
                          }
                        },
                        child: Container(
                          height: 44, // button height
                          decoration: BoxDecoration(
                            color: FaceAttendColors.accent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(primaryIcon, color: Colors.white, size: 18),
                              const SizedBox(width: 8),
                              Text(
                                primaryLabel,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w400,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (showRetry) ...[
                        const SizedBox(height: 12),
                        _ScaleOnPress(
                          onTap: () => Navigator.of(context).pop(true),
                          child: Container(
                            height: 44, // button height
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: FaceAttendColors.accent,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            alignment: Alignment.center,
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.refresh,
                                  size: 18,
                                  color: FaceAttendColors.accent,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'Try Again',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w400,
                                    color: FaceAttendColors.accent,
                                  ),
                                ),
                              ],
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
      ),
    );
  }
}

class _ResultDetails extends StatelessWidget {
  const _ResultDetails({this.time, this.confidence});

  final DateTime? time;
  final double? confidence;

  @override
  Widget build(BuildContext context) {
    if (time == null && confidence == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: FaceAttendColors.surfaceMuted,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FaceAttendColors.border),
      ),
      child: Column(
        children: [
          if (time != null)
            _DetailRow(
              icon: Icons.schedule,
              label: 'Time',
              value: time!.toLocal().toString().substring(11, 19),
            ),
          if (time != null && confidence != null)
            const Divider(
              height: 20,
              thickness: 0.6,
              color: FaceAttendColors.border,
            ),
          if (confidence != null)
            _DetailRow(
              icon: Icons.verified,
              label: 'Confidence',
              value: '${(confidence! * 100).clamp(0, 100).toStringAsFixed(1)}%',
            ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: FaceAttendColors.accent),
        const SizedBox(width: 10),
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: FaceAttendColors.ink,
          ),
        ),
        const Spacer(),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14, color: FaceAttendColors.ink),
          ),
        ),
      ],
    );
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
