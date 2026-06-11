import 'package:flutter/material.dart';

import '../models/session.dart';
import '../theme/app_theme.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    required this.session,
    required this.onLogout,
    super.key,
  });

  final MobileSession session;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          children: [
            const Text(
              'SCANNER DETAILS',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.0,
                color: FaceAttendColors.muted,
              ),
            ),
            const SizedBox(height: 10),
            _SettingsPanel(
              children: [
                _SettingsTile(
                  icon: Icons.qr_code_scanner,
                  label: 'Scanner Name',
                  value: session.deviceName,
                ),
                const Divider(
                  height: 1,
                  thickness: 0.6,
                  indent: 56,
                  color: FaceAttendColors.border,
                ),
                _SettingsTile(
                  icon: Icons.devices,
                  label: 'Scanner Device ID',
                  value: session.deviceId,
                ),
                const Divider(
                  height: 1,
                  thickness: 0.6,
                  indent: 56,
                  color: FaceAttendColors.border,
                ),
                _SettingsTile(
                  icon: Icons.vpn_key,
                  label: 'Scanner Token',
                  value: session.token.isEmpty
                      ? 'Not configured'
                      : 'Configured',
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Text(
              'SERVER DETAILS',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.0,
                color: FaceAttendColors.muted,
              ),
            ),
            const SizedBox(height: 10),
            _SettingsPanel(
              children: [
                _SettingsTile(
                  icon: Icons.cloud,
                  label: 'Odoo URL',
                  value: session.baseUrl,
                ),
                const Divider(
                  height: 1,
                  thickness: 0.6,
                  indent: 56,
                  color: FaceAttendColors.border,
                ),
                _SettingsTile(
                  icon: Icons.storage,
                  label: 'Database',
                  value: session.db,
                ),
                const Divider(
                  height: 1,
                  thickness: 0.6,
                  indent: 56,
                  color: FaceAttendColors.border,
                ),
                _SettingsTile(
                  icon: Icons.hub,
                  label: 'Middleware URL',
                  value: session.middlewareUrl,
                ),
              ],
            ),
            const SizedBox(height: 32),
            _ScaleOnPress(
              onTap: () {
                onLogout();
                Navigator.of(context).popUntil((route) => route.isFirst);
              },
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  border: Border.all(color: FaceAttendColors.danger),
                  borderRadius: BorderRadius.circular(8),
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
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        color: FaceAttendColors.danger,
                      ),
                    ),
                  ],
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
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(children: children),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: const BoxDecoration(
          color: FaceAttendColors.surfaceMuted,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: FaceAttendColors.ink, size: 20),
      ),
      title: Text(
        label,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: FaceAttendColors.ink,
        ),
      ),
      subtitle: Text(
        value,
        style: const TextStyle(fontSize: 13, color: FaceAttendColors.muted),
      ),
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
