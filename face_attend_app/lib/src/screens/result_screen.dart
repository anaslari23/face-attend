import 'package:flutter/material.dart';

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
    final color = success ? const Color(0xFF2ECC71) : const Color(0xFFE74C3C);
    final icon = success ? Icons.check_circle_rounded : Icons.cancel_rounded;
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
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
                          child: Icon(icon, color: color, size: 48),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        message,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade600,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 24),
                      _ResultDetails(time: time, confidence: confidence),
                      const SizedBox(height: 24),

                      // Home Button
                      Container(
                        height: 48,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFF6B35), Color(0xFFFFC107)],
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
                          onPressed: () {
                            if (popToFirst) {
                              Navigator.of(
                                context,
                              ).popUntil((route) => route.isFirst);
                            } else {
                              Navigator.of(context).pop();
                            }
                          },
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(primaryIcon, color: Colors.white, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                primaryLabel,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (showRetry) ...[
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            side: BorderSide(color: Colors.grey.shade300),
                          ),
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.refresh, size: 20),
                          label: const Text(
                            'Try Again',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
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
        color: const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade100),
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
            const Divider(height: 20, thickness: 0.5),
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
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 10),
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const Spacer(),
        Flexible(
          flex: 2,
          child: Text(
            value,
            textAlign: TextAlign.end,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
