import 'package:flutter/material.dart';
import 'package:face_attend_app/main.dart';

import '../models/session.dart';
import '../services/device_service.dart';
import '../theme/app_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    required this.session,
    required this.onLogout,
    super.key,
  });

  final MobileSession session;
  final VoidCallback onLogout;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String? _mobileDeviceId;
  bool _showFullMobileDeviceId = false;

  @override
  void initState() {
    super.initState();
    _loadMobileDeviceId();
  }

  Future<void> _loadMobileDeviceId() async {
    try {
      final identity = await DeviceService().identity();
      if (mounted) {
        setState(() {
          _mobileDeviceId = identity.id;
        });
      }
    } catch (e) {
      debugPrint('Failed to fetch mobile device ID for settings: $e');
    }
  }

  String _formatMaskedDeviceId(String? id) {
    if (id == null || id.isEmpty) return 'Loading...';
    if (_showFullMobileDeviceId) return id;
    if (id.length <= 4) return '*' * id.length;
    final visiblePart = id.substring(id.length - 4);
    final maskedPart = '*' * (id.length - 4);
    return '$maskedPart$visiblePart';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          children: [
            AnimatedEntrance(
              delay: const Duration(milliseconds: 50),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'SCANNER DETAILS',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      color: FaceAttendColors.muted,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _SettingsPanel(
                    children: [
                      _SettingsTile(
                        icon: Icons.smartphone,
                        label: 'Mobile Device ID',
                        value: _formatMaskedDeviceId(_mobileDeviceId),
                        trailing: _mobileDeviceId != null && _mobileDeviceId!.isNotEmpty
                            ? IconButton(
                                icon: Icon(
                                  _showFullMobileDeviceId
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                  size: 20,
                                  color: FaceAttendColors.muted,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _showFullMobileDeviceId =
                                        !_showFullMobileDeviceId;
                                  });
                                },
                              )
                            : null,
                      ),
                      const Divider(
                        height: 1,
                        thickness: 0.8,
                        indent: 56,
                        color: FaceAttendColors.border,
                      ),
                      _SettingsTile(
                        icon: Icons.qr_code_scanner,
                        label: 'Scanner Name',
                        value: widget.session.deviceName,
                      ),
                      const Divider(
                        height: 1,
                        thickness: 0.8,
                        indent: 56,
                        color: FaceAttendColors.border,
                      ),
                      _SettingsTile(
                        icon: Icons.devices,
                        label: 'Scanner Device ID',
                        value: widget.session.deviceId,
                      ),
                      const Divider(
                        height: 1,
                        thickness: 0.8,
                        indent: 56,
                        color: FaceAttendColors.border,
                      ),
                      _SettingsTile(
                        icon: Icons.fingerprint,
                        label: 'Generated Device ID',
                        value: widget.session.generatedDeviceId ?? 'Not Generated',
                      ),
                      const Divider(
                        height: 1,
                        thickness: 0.8,
                        indent: 56,
                        color: FaceAttendColors.border,
                      ),
                      _SettingsTile(
                        icon: Icons.vpn_key,
                        label: 'Scanner Token',
                        value: widget.session.token.isEmpty
                            ? 'Not configured'
                            : 'Configured',
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            AnimatedEntrance(
              delay: const Duration(milliseconds: 150),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'SERVER DETAILS',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      color: FaceAttendColors.muted,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _SettingsPanel(
                    children: [
                      _SettingsTile(
                        icon: Icons.cloud,
                        label: 'Odoo URL',
                        value: widget.session.baseUrl,
                      ),
                      const Divider(
                        height: 1,
                        thickness: 0.8,
                        indent: 56,
                        color: FaceAttendColors.border,
                      ),
                      _SettingsTile(
                        icon: Icons.storage,
                        label: 'Database',
                        value: widget.session.db,
                      ),
                      const Divider(
                        height: 1,
                        thickness: 0.8,
                        indent: 56,
                        color: FaceAttendColors.border,
                      ),
                      _SettingsTile(
                        icon: Icons.memory,
                        label: 'Recognition Mode',
                        value: 'On-device phone ML',
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 36),
            AnimatedEntrance(
              delay: const Duration(milliseconds: 250),
              child: ScaleOnPress(
                onTap: () {
                  widget.onLogout();
                  Navigator.of(context).popUntil((route) => route.isFirst);
                },
                child: Container(
                  height: 50,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: FaceAttendColors.danger.withValues(alpha: 0.5),
                      width: 1.2,
                    ),
                    color: FaceAttendColors.surface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.logout,
                        size: 20,
                        color: FaceAttendColors.danger,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Logout Session',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: FaceAttendColors.danger,
                          letterSpacing: 0.5,
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
    );
  }
}

class _SettingsPanel extends StatelessWidget {
  const _SettingsPanel({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: premiumCardDecoration(shadowColor: FaceAttendColors.accent),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(children: children),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.label,
    required this.value,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: const BoxDecoration(
          color: FaceAttendColors.accentSoft,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: FaceAttendColors.accent, size: 20),
      ),
      title: Text(
        label,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: FaceAttendColors.ink,
        ),
      ),
      subtitle: SelectableText(
        value,
        style: const TextStyle(fontSize: 13, color: FaceAttendColors.muted),
      ),
      trailing: trailing,
    );
  }
}
