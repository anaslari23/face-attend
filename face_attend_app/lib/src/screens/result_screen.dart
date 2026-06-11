import 'package:flutter/material.dart';

class AttendanceResultScreen extends StatelessWidget {
  const AttendanceResultScreen({
    required this.success,
    required this.title,
    required this.message,
    this.time,
    this.confidence,
    this.primaryLabel = 'Back Home',
    this.showRetry = true,
    super.key,
  });

  final bool success;
  final String title;
  final String message;
  final DateTime? time;
  final double? confidence;
  final String primaryLabel;
  final bool showRetry;

  @override
  Widget build(BuildContext context) {
    final color = success ? const Color(0xFF30D158) : const Color(0xFFFF3B30);
    final icon = success ? Icons.check : Icons.close;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7), // Parchment
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
                      // Status Badge
                      Center(
                        child: Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: Icon(icon, color: color, size: 44),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.374,
                          color: color,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        message,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF7A7A7A), // ink-muted-48
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 24),
                      _ResultDetails(time: time, confidence: confidence),
                      const SizedBox(height: 24),

                      // Home Button
                      _ScaleOnPress(
                        onTap: () => Navigator.of(
                          context,
                        ).popUntil((route) => route.isFirst),
                        child: Container(
                          height: 44, // button height
                          decoration: BoxDecoration(
                            color: const Color(0xFF0066CC), // Action Blue
                            borderRadius: BorderRadius.circular(9999), // pill
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.home,
                                color: Colors.white,
                                size: 18,
                              ),
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
                          onTap: () => Navigator.of(context).pop(),
                          child: Container(
                            height: 44, // button height
                            decoration: BoxDecoration(
                              border: Border.all(color: const Color(0xFF0066CC), width: 1.0),
                              borderRadius: BorderRadius.circular(9999), // pill
                            ),
                            alignment: Alignment.center,
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.refresh, size: 18, color: Color(0xFF0066CC)),
                                SizedBox(width: 8),
                                Text(
                                  'Try Again',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w400,
                                    color: Color(0xFF0066CC),
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
        color: const Color(0xFFF5F5F7), // Parchment
        borderRadius: BorderRadius.circular(11), // rounded.md (11px)
        border: Border.all(color: const Color(0xFFE0E0E0), width: 1.0), // hairline
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
            const Divider(height: 20, thickness: 0.5, color: Color(0xFFE0E0E0)),
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
        Icon(icon, size: 20, color: const Color(0xFF0066CC)),
        const SizedBox(width: 10),
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1D1D1F),
          ),
        ),
        const Spacer(),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF1D1D1F),
            ),
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
        scale: _pressed ? 0.95 : 1.0,
        duration: const Duration(milliseconds: 80),
        child: widget.child,
      ),
    );
  }
}
