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
    final color = success ? Colors.green.shade700 : Colors.red.shade700;
    final icon = success ? Icons.check_circle : Icons.error;
    return Scaffold(
      appBar: AppBar(title: const Text('Result')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(icon, color: color, size: 72),
                  const SizedBox(height: 18),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: color),
                  ),
                  const SizedBox(height: 8),
                  Text(message, textAlign: TextAlign.center),
                  const SizedBox(height: 22),
                  _ResultDetails(time: time, confidence: confidence),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
                    icon: const Icon(Icons.home),
                    label: Text(primaryLabel),
                  ),
                  if (showRetry) ...[
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Try Again'),
                    ),
                  ],
                ],
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
        color: Colors.white,
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          if (time != null)
            _DetailRow(
              icon: Icons.schedule,
              label: 'Time',
              value: time!.toLocal().toString(),
            ),
          if (time != null && confidence != null) const Divider(height: 22),
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
