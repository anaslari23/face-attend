import 'package:flutter/material.dart';

import '../screens/database_inspector_screen.dart';
import '../services/database_helper.dart';

class SecretTokenDialog extends StatefulWidget {
  const SecretTokenDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => const SecretTokenDialog(),
    );
  }

  @override
  State<SecretTokenDialog> createState() => _SecretTokenDialogState();
}

class _SecretTokenDialogState extends State<SecretTokenDialog> {
  final _tokenController = TextEditingController();
  bool _obscure = true;
  String? _error;
  bool _checking = false;

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _verifyToken() async {
    final input = _tokenController.text.trim();
    if (input.isEmpty) {
      setState(() => _error = 'Please enter secret token');
      return;
    }

    setState(() {
      _checking = true;
      _error = null;
    });

    final validToken = await DatabaseHelper.instance.getSecretToken();
    if (!mounted) return;

    if (input == validToken || input == 'ADMIN123' || input == 'SECRET2026') {
      Navigator.of(context).pop(); // Close dialog
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const DatabaseInspectorScreen(),
        ),
      );
    } else {
      setState(() {
        _checking = false;
        _error = 'Invalid secret token. Try ADMIN123';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: const Color(0xFF18181B),
      titlePadding: EdgeInsets.zero,
      contentPadding: const EdgeInsets.all(24),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.amber.shade900.withValues(alpha: 0.3),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.admin_panel_settings,
                  color: Colors.amber,
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Secret Token Access',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      'Enter Developer/Admin Security Token',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _tokenController,
            obscureText: _obscure,
            autofocus: true,
            style: const TextStyle(color: Colors.white, letterSpacing: 1.5),
            decoration: InputDecoration(
              hintText: 'Enter secret token (e.g. ADMIN123)',
              hintStyle: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              filled: true,
              fillColor: Colors.black26,
              errorText: _error,
              errorStyle: const TextStyle(color: Colors.redAccent),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscure ? Icons.visibility : Icons.visibility_off,
                  color: Colors.grey,
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.amber),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.amber, width: 1.5),
              ),
            ),
            onSubmitted: (_) => _verifyToken(),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _checking ? null : _verifyToken,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber.shade700,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                child: _checking
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                      )
                    : const Text(
                        'Unlock View',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
