import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:face_attend_app/main.dart';

import '../api/odoo_face_attendance_client.dart';
import '../models/session.dart';
import '../services/local_log_service.dart';
import '../services/log_export_service.dart';
import '../theme/app_theme.dart';

class LocalLogScreen extends StatefulWidget {
  const LocalLogScreen({required this.session, super.key});

  final MobileSession session;

  @override
  State<LocalLogScreen> createState() => _LocalLogScreenState();
}

class _LocalLogScreenState extends State<LocalLogScreen> {
  late final OdooFaceAttendanceClient _client;
  List<LocalPunchLog> _logs = [];
  bool _loading = true;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _client = OdooFaceAttendanceClient(
      baseUrl: widget.session.baseUrl,
      db: widget.session.db,
      token: widget.session.token,
    );
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    setState(() => _loading = true);
    final logs = await LocalLogService.instance.getLogs();
    // Only show logs where attendance matched/accepted
    final matchedLogs = logs.where((log) {
      final payload = log.payload;
      return payload['accepted'] as bool? ?? false;
    }).toList();
    if (mounted) {
      setState(() {
        _logs = matchedLogs;
        _loading = false;
      });
    }
  }

  Future<void> _syncLogs() async {
    if (_syncing) return;
    setState(() => _syncing = true);

    try {
      final count = await LocalLogService.instance.syncPendingLogs(_client);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(count > 0 
              ? 'Successfully synced $count attendance logs to Odoo.' 
              : 'No pending logs to sync, or sync connection failed.'),
            backgroundColor: count > 0 ? FaceAttendColors.success : FaceAttendColors.ink,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sync failed: $e'),
            backgroundColor: FaceAttendColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _syncing = false);
        _loadLogs();
      }
    }
  }

  Future<void> _clearLogs() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All Logs?'),
        content: const Text(
          'This will delete all local biometric scan history from this device. '
          'Unsynced logs will be permanently lost.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: FaceAttendColors.danger),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await LocalLogService.instance.clearLogs();
      _loadLogs();
    }
  }

  String _formatDateTime(DateTime dt) {
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    final second = dt.second.toString().padLeft(2, '0');
    final day = dt.day.toString().padLeft(2, '0');
    final month = _monthName(dt.month);
    return '$day $month, $hour:$minute:$second';
  }

  String _monthName(int month) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    if (month >= 1 && month <= 12) return months[month - 1];
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final pendingCount = _logs.where((l) => !l.isSynced).length;

    return Scaffold(
      backgroundColor: FaceAttendColors.surfaceMuted,
      appBar: AppBar(
        title: const Text('Scanner Activity Logs'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: 'Clear History',
            onPressed: _logs.isEmpty ? null : _clearLogs,
          ),
          if (_logs.isNotEmpty)
            PopupMenuButton<String>(
              icon: const Icon(Icons.download_outlined),
              tooltip: 'Export Logs',
              onSelected: (value) async {
                try {
                  if (value == 'pdf') {
                    await LogExportService.exportToPdf(_logs);
                  } else if (value == 'excel') {
                    await LogExportService.exportToExcel(_logs);
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Failed to export logs: $e'),
                        backgroundColor: FaceAttendColors.danger,
                      ),
                    );
                  }
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'pdf',
                  child: Row(
                    children: [
                      Icon(Icons.picture_as_pdf_outlined, color: FaceAttendColors.danger),
                      SizedBox(width: 8),
                      Text('Export PDF'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'excel',
                  child: Row(
                    children: [
                      Icon(Icons.table_view_outlined, color: FaceAttendColors.success),
                      SizedBox(width: 8),
                      Text('Export Excel'),
                    ],
                  ),
                ),
              ],
            ),
          if (_syncing)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              icon: Icon(
                Icons.cloud_upload_outlined,
                color: pendingCount > 0 ? FaceAttendColors.warning : null,
              ),
              tooltip: 'Sync Offline Logs',
              onPressed: _logs.isEmpty ? null : _syncLogs,
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Status bar banner showing pending sync logs
            if (pendingCount > 0)
              Container(
                color: FaceAttendColors.warning.withValues(alpha: 0.15),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    const Icon(Icons.wifi_off_outlined, color: FaceAttendColors.warning, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '$pendingCount log${pendingCount > 1 ? 's are' : ' is'} pending synchronization.',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: FaceAttendColors.ink,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _syncing ? null : _syncLogs,
                      icon: const Icon(Icons.sync, size: 16),
                      label: const Text('Sync Now', style: TextStyle(fontSize: 12)),
                      style: TextButton.styleFrom(
                        foregroundColor: FaceAttendColors.warning,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        minimumSize: Size.zero,
                      ),
                    )
                  ],
                ),
              ),
            
            Expanded(
              child: _loading
                  ? const Center(child: AppLoader())
                  : _logs.isEmpty
                      ? _buildEmptyState()
                      : RefreshIndicator(
                          onRefresh: _loadLogs,
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                            itemCount: _logs.length,
                            itemBuilder: (context, index) {
                              final log = _logs[index];
                              return AnimatedEntrance(
                                delay: Duration(milliseconds: index * 30),
                                child: Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: _LogCard(
                                    log: log,
                                    formattedTime: _formatDateTime(log.timestamp),
                                    onTap: () => _showLogDetails(log),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.history,
              size: 64,
              color: FaceAttendColors.muted.withValues(alpha: 0.4),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'No Activity Logs Yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: FaceAttendColors.ink,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Local logs from biometric scans will appear here.',
            style: TextStyle(
              fontSize: 13,
              color: FaceAttendColors.muted,
            ),
          ),
        ],
      ),
    );
  }

  void _showLogDetails(LocalPunchLog log) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _LogDetailsSheet(
          log: log,
          formattedTime: _formatDateTime(log.timestamp),
        );
      },
    );
  }
}

class _LogCard extends StatelessWidget {
  const _LogCard({
    required this.log,
    required this.formattedTime,
    required this.onTap,
  });

  final LocalPunchLog log;
  final String formattedTime;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final payload = log.payload;
    final accepted = payload['accepted'] as bool? ?? false;
    final score = (payload['match_score'] as num? ?? 0.0).toDouble();
    final isSystemError = log.employeeName == 'System Error';

    // Status Styling
    Color statusColor;
    IconData statusIcon;
    String statusText;

    if (log.isSynced) {
      if (accepted) {
        statusColor = FaceAttendColors.success;
        statusIcon = Icons.check_circle_outline;
        statusText = 'Synced';
      } else {
        statusColor = FaceAttendColors.danger;
        statusIcon = Icons.cancel_outlined;
        statusText = isSystemError ? 'Error Logged' : 'Match Failed';
      }
    } else {
      if (log.syncError != null) {
        statusColor = FaceAttendColors.danger;
        statusIcon = Icons.sync_problem_outlined;
        statusText = 'Sync Error';
      } else {
        statusColor = FaceAttendColors.warning;
        statusIcon = Icons.wifi_off_outlined;
        statusText = 'Offline Queue';
      }
    }

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: FaceAttendColors.border, width: 0.8),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      log.employeeName,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: isSystemError ? FaceAttendColors.danger : FaceAttendColors.ink,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(statusIcon, color: statusColor, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          statusText,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: statusColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    formattedTime,
                    style: const TextStyle(
                      fontSize: 12,
                      color: FaceAttendColors.muted,
                    ),
                  ),
                  if (!isSystemError && !accepted && payload['failure_reason'] != null)
                    Text(
                      'Reason: ${payload['failure_reason']}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: FaceAttendColors.danger,
                      ),
                    )
                  else if (accepted)
                    Text(
                      'Score: ${(score * 100).toStringAsFixed(1)}%',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: FaceAttendColors.accent,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LogDetailsSheet extends StatelessWidget {
  const _LogDetailsSheet({
    required this.log,
    required this.formattedTime,
  });

  final LocalPunchLog log;
  final String formattedTime;

  @override
  Widget build(BuildContext context) {
    final payload = log.payload;
    final isErrorLog = log.employeeName == 'System Error';
    final accepted = payload['accepted'] as bool? ?? false;

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Sheet Handlebar
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: FaceAttendColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              
              // Appbar-like title
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isErrorLog ? 'System Discrepancy Log' : 'Scan Detail Log',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: FaceAttendColors.ink,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            formattedTime,
                            style: const TextStyle(
                              fontSize: 12,
                              color: FaceAttendColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              const Divider(color: FaceAttendColors.border, height: 24),
              
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(20),
                  children: [
                    // Sync Error alert if present
                    if (log.syncError != null) ...[
                      Container(
                        decoration: BoxDecoration(
                          color: FaceAttendColors.danger.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: FaceAttendColors.danger.withValues(alpha: 0.2)),
                        ),
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.warning_amber_rounded, color: FaceAttendColors.danger, size: 20),
                                SizedBox(width: 8),
                                Text(
                                  'Sync Connection Error',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: FaceAttendColors.danger,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              log.syncError!,
                              style: const TextStyle(
                                fontSize: 12,
                                color: FaceAttendColors.ink,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    _buildInfoSection('STATUS & METRICS', [
                      _buildDetailRow('Employee Target', log.employeeName),
                      _buildDetailRow('Match Validated', accepted ? 'YES' : 'NO'),
                      if (!isErrorLog) ...[
                        _buildDetailRow('Match Score', _percentString(payload['match_score'])),
                        _buildDetailRow('Odoo Threshold', _percentString(payload['threshold'])),
                        _buildDetailRow('Liveness Check', (payload['liveness_passed'] == true) ? 'Passed' : 'Failed'),
                        _buildDetailRow('Liveness Confidence', _percentString(payload['liveness_score'])),
                        _buildDetailRow('Anti-Spoofing Score', (payload['spoof_score'] != null) ? '${payload['spoof_score']}' : 'Not applicable'),
                      ],
                      if (!accepted && payload['failure_reason'] != null)
                        _buildDetailRow('Reason String', payload['failure_reason'].toString().toUpperCase()),
                    ]),
                    
                    const SizedBox(height: 20),
                    
                    _buildInfoSection('HARDWARE & ENGINE INFO', [
                      _buildDetailRow('Device Identity UID', payload['device_id']?.toString() ?? 'Unknown'),
                      _buildDetailRow('Client App Version', payload['app_version']?.toString() ?? '1.0.0'),
                      if (payload['embedding_source'] != null)
                        _buildDetailRow('Embedding Model Source', payload['embedding_source'].toString()),
                      _buildDetailRow('Scan UID Hash', log.id),
                    ]),

                    const SizedBox(height: 20),
                    
                    // Raw payload display
                    Theme(
                      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: const Text(
                          'VIEW RAW JSON PAYLOAD',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                            color: FaceAttendColors.muted,
                          ),
                        ),
                        children: [
                          Container(
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: FaceAttendColors.surfaceMuted,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: FaceAttendColors.border, width: 0.8),
                            ),
                            padding: const EdgeInsets.all(12),
                            child: Stack(
                              children: [
                                SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Text(
                                    const JsonEncoder.withIndent('  ').convert(payload),
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 11,
                                      color: FaceAttendColors.ink,
                                    ),
                                  ),
                                ),
                                Positioned(
                                  right: 0,
                                  top: 0,
                                  child: IconButton(
                                    icon: const Icon(Icons.copy, size: 18, color: FaceAttendColors.muted),
                                    onPressed: () {
                                      Clipboard.setData(ClipboardData(
                                        text: const JsonEncoder.withIndent('  ').convert(payload),
                                      ));
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Copied payload to clipboard')),
                                      );
                                    },
                                  ),
                                )
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _percentString(dynamic score) {
    if (score == null) return '--';
    final num val = score as num;
    return '${(val * 100).toStringAsFixed(1)}%';
  }

  Widget _buildInfoSection(String title, List<Widget> rows) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
            color: FaceAttendColors.muted,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: FaceAttendColors.surfaceMuted,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: FaceAttendColors.border, width: 0.8),
          ),
          child: Column(children: rows),
        ),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: FaceAttendColors.muted,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: FaceAttendColors.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
