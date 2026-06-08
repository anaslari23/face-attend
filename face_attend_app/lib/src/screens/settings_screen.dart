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
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('Account', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            _SettingsPanel(
              children: [
                _SettingsTile(
                  icon: Icons.person,
                  label: 'Employee',
                  value: session.employee.name,
                ),
                _SettingsTile(
                  icon: Icons.badge,
                  label: 'Employee ID',
                  value: session.employee.id.toString(),
                ),
                _SettingsTile(
                  icon: session.employee.faceRegistered ? Icons.verified_user : Icons.warning_amber,
                  label: 'Face Registration',
                  value: session.employee.faceRegistered ? 'Registered' : 'Required',
                ),
              ],
            ),
            const SizedBox(height: 22),
            Text('Server', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            _SettingsPanel(
              children: [
                _SettingsTile(
                  icon: Icons.cloud,
                  label: 'Odoo URL',
                  value: session.baseUrl,
                ),
                _SettingsTile(
                  icon: Icons.storage,
                  label: 'Database',
                  value: session.db,
                ),
                _SettingsTile(
                  icon: Icons.hub,
                  label: 'Middleware URL',
                  value: session.middlewareUrl,
                ),
              ],
            ),
            const SizedBox(height: 24),
            FilledButton.tonalIcon(
              onPressed: () {
                onLogout();
                Navigator.of(context).popUntil((route) => route.isFirst);
              },
              icon: const Icon(Icons.logout),
              label: const Text('Logout'),
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
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(children: children),
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
      leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
      title: Text(label),
      subtitle: Text(value),
    );
  }
}
