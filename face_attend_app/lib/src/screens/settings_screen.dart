import 'package:flutter/material.dart';

import '../models/session.dart';

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
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          children: [
            Text(
              'ACCOUNT DETAILS',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.0,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 10),
            _SettingsPanel(
              children: [
                _SettingsTile(
                  icon: Icons.person,
                  label: 'Employee Name',
                  value: session.employee.name,
                ),
                const Divider(height: 1, thickness: 0.5, indent: 56),
                _SettingsTile(
                  icon: Icons.badge,
                  label: 'Employee ID',
                  value: session.employee.id.toString(),
                ),
                const Divider(height: 1, thickness: 0.5, indent: 56),
                _SettingsTile(
                  icon: session.employee.faceRegistered ? Icons.verified_user : Icons.warning_amber_rounded,
                  iconColor: session.employee.faceRegistered ? const Color(0xFF2ECC71) : const Color(0xFFFF9800),
                  label: 'Biometric Status',
                  value: session.employee.faceRegistered ? 'Template Registered' : 'Enrollment Required',
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              'SERVER DETAILS',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.0,
                color: Colors.grey.shade600,
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
                const Divider(height: 1, thickness: 0.5, indent: 56),
                _SettingsTile(
                  icon: Icons.storage,
                  label: 'Database',
                  value: session.db,
                ),
              ],
            ),
            const SizedBox(height: 32),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFE74C3C),
                side: const BorderSide(color: Color(0xFFE74C3C), width: 1.2),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () {
                onLogout();
                Navigator.of(context).popUntil((route) => route.isFirst);
              },
              icon: const Icon(Icons.logout, size: 20),
              label: const Text(
                'Logout Session',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
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
    this.iconColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: (iconColor ?? const Color(0xFFFF6B35)).withValues(alpha: 0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: iconColor ?? const Color(0xFFFF6B35), size: 20),
      ),
      title: Text(
        label,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1E1E1E)),
      ),
      subtitle: Text(
        value,
        style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
      ),
    );
  }
}
