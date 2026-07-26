import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../services/database_helper.dart';

class DatabaseInspectorScreen extends StatefulWidget {
  const DatabaseInspectorScreen({super.key});

  @override
  State<DatabaseInspectorScreen> createState() => _DatabaseInspectorScreenState();
}

class _DatabaseInspectorScreenState extends State<DatabaseInspectorScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  bool _loading = true;
  List<Map<String, dynamic>> _punchLogs = [];
  List<Map<String, dynamic>> _faceRecords = [];
  Map<String, dynamic>? _session;
  String _secretToken = 'ADMIN123';
  String _searchQuery = '';
  String _filter = 'ALL'; // ALL, UNSYNCED, SYNCED, FAILED

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadAllData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAllData() async {
    setState(() => _loading = true);
    final logs = await DatabaseHelper.instance.getAllPunchLogs();
    final faces = await DatabaseHelper.instance.getFaceRecords();
    final sess = await DatabaseHelper.instance.getSession();
    final token = await DatabaseHelper.instance.getSecretToken();

    if (!mounted) return;
    setState(() {
      _punchLogs = logs;
      _faceRecords = faces;
      _session = sess;
      _secretToken = token;
      _loading = false;
    });
  }

  List<Map<String, dynamic>> get _filteredLogs {
    return _punchLogs.where((log) {
      final name = (log['employeeName'] as String? ?? '').toLowerCase();
      final id = (log['id'] as String? ?? '').toLowerCase();
      final error = (log['syncError'] as String? ?? '').toLowerCase();
      final query = _searchQuery.toLowerCase();

      final matchesQuery = name.contains(query) || id.contains(query) || error.contains(query);
      if (!matchesQuery) return false;

      final isSynced = log['isSynced'] as bool? ?? false;
      final syncError = log['syncError'] as String?;

      if (_filter == 'UNSYNCED') return !isSynced;
      if (_filter == 'SYNCED') return isSynced;
      if (_filter == 'FAILED') return syncError != null && syncError.isNotEmpty;
      return true;
    }).toList();
  }

  Future<void> _exportAndCopyDump() async {
    final dump = await DatabaseHelper.instance.exportFullDatabaseToJson();
    final jsonStr = const JsonEncoder.withIndent('  ').convert(dump);
    await Clipboard.setData(ClipboardData(text: jsonStr));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Full Database JSON copied to Clipboard!'),
        backgroundColor: Colors.amber,
      ),
    );
  }

  Future<void> _shareDump() async {
    final dump = await DatabaseHelper.instance.exportFullDatabaseToJson();
    final jsonStr = const JsonEncoder.withIndent('  ').convert(dump);
    await Share.share(jsonStr, subject: 'FaceAttend SQLite Database Dump');
  }

  Future<void> _changeSecretTokenDialog() async {
    final controller = TextEditingController(text: _secretToken);
    final newKey = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E24),
        title: const Text('Update Secret Token', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: 'New Secret Token',
            labelStyle: TextStyle(color: Colors.amber),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.amber)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black),
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (newKey != null && newKey.isNotEmpty) {
      await DatabaseHelper.instance.setSecretToken(newKey);
      _loadAllData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F12),
      appBar: AppBar(
        backgroundColor: const Color(0xFF18181B),
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.storage, color: Colors.amber, size: 20),
            ),
            const SizedBox(width: 10),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SQLite Inspector',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                Text(
                  'Secret Token View Mode',
                  style: TextStyle(fontSize: 10, color: Colors.amber, letterSpacing: 0.8),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadAllData,
            tooltip: 'Reload Database',
          ),
          IconButton(
            icon: const Icon(Icons.copy_all, color: Colors.amber),
            onPressed: _exportAndCopyDump,
            tooltip: 'Copy JSON Dump',
          ),
          IconButton(
            icon: const Icon(Icons.share, color: Colors.lightBlueAccent),
            onPressed: _shareDump,
            tooltip: 'Share Database',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.amber,
          labelColor: Colors.amber,
          unselectedLabelColor: Colors.grey,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          tabs: const [
            Tab(text: 'Punch Logs', icon: Icon(Icons.list_alt, size: 18)),
            Tab(text: 'Face Index', icon: Icon(Icons.face, size: 18)),
            Tab(text: 'Session', icon: Icon(Icons.vpn_key, size: 18)),
            Tab(text: 'JSON Dump', icon: Icon(Icons.code, size: 18)),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.amber))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildPunchLogsTab(),
                _buildFaceIndexTab(),
                _buildSessionTab(),
                _buildJsonDumpTab(),
              ],
            ),
    );
  }

  // ===========================================================================
  // TAB 1: PUNCH LOGS TAB
  // ===========================================================================
  Widget _buildPunchLogsTab() {
    final filtered = _filteredLogs;
    final total = _punchLogs.length;
    final unsynced = _punchLogs.where((l) => l['isSynced'] == false).length;

    return Column(
      children: [
        // Summary & Search Header
        Container(
          padding: const EdgeInsets.all(16),
          color: const Color(0xFF141418),
          child: Column(
            children: [
              Row(
                children: [
                  _statBadge('TOTAL LOGS', '$total', Colors.blue),
                  const SizedBox(width: 8),
                  _statBadge('PENDING OFFLINE', '$unsynced', Colors.orange),
                  const SizedBox(width: 8),
                  _statBadge('SYNCED', '${total - unsynced}', Colors.green),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                onChanged: (val) => setState(() => _searchQuery = val),
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Search logs by employee name, ID or error...',
                  hintStyle: const TextStyle(color: Colors.grey, fontSize: 13),
                  prefixIcon: const Icon(Icons.search, color: Colors.grey, size: 18),
                  filled: true,
                  fillColor: const Color(0xFF22222A),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _filterChip('ALL', 'All Logs'),
                    _filterChip('UNSYNCED', 'Pending Sync'),
                    _filterChip('SYNCED', 'Synced'),
                    _filterChip('FAILED', 'Errors'),
                  ],
                ),
              ),
            ],
          ),
        ),

        Expanded(
          child: filtered.isEmpty
              ? const Center(
                  child: Text(
                    'No matching logs found in SQLite',
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final item = filtered[index];
                    return _PunchLogCard(log: item);
                  },
                ),
        ),
      ],
    );
  }

  Widget _filterChip(String filterKey, String label) {
    final selected = _filter == filterKey;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: FilterChip(
        selected: selected,
        label: Text(label, style: TextStyle(fontSize: 11, color: selected ? Colors.black : Colors.white)),
        selectedColor: Colors.amber,
        backgroundColor: const Color(0xFF272730),
        onSelected: (_) => setState(() => _filter = filterKey),
      ),
    );
  }

  Widget _statBadge(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Column(
          children: [
            Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 2),
            Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: color)),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // TAB 2: FACE INDEX TAB
  // ===========================================================================
  Widget _buildFaceIndexTab() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: const Color(0xFF141418),
          child: Row(
            children: [
              const Icon(Icons.face, color: Colors.amber, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Indexed Employees: ${_faceRecords.length}',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    const Text(
                      'Stored in SQLite table: face_embeddings (512-d ArcFace vectors)',
                      style: TextStyle(color: Colors.grey, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _faceRecords.isEmpty
              ? const Center(
                  child: Text('No cached face embeddings in SQLite yet', style: TextStyle(color: Colors.grey)),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _faceRecords.length,
                  itemBuilder: (context, index) {
                    final item = _faceRecords[index];
                    final primary = item['primary_embedding'] as List<dynamic>? ?? [];
                    final adaptive = item['adaptive_embeddings'] as List<dynamic>? ?? [];

                    return Card(
                      color: const Color(0xFF1C1C22),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.amber.shade900,
                          child: Text(
                            (item['employee_name'] as String? ?? 'U')[0].toUpperCase(),
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                        title: Text(
                          item['employee_name'] as String? ?? 'Unknown',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          'ID: ${item['employee_id']} | Dept: ${item['department'] ?? "N/A"}\n'
                          'Primary Embedding: ${primary.length}d | Adaptive Variants: ${adaptive.length}',
                          style: const TextStyle(color: Colors.grey, fontSize: 11),
                        ),
                        trailing: const Icon(Icons.check_circle, color: Colors.green, size: 20),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ===========================================================================
  // TAB 3: SESSION TAB
  // ===========================================================================
  Widget _buildSessionTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: const Color(0xFF1C1C22),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.security, color: Colors.amber),
                    const SizedBox(width: 10),
                    const Text(
                      'ACTIVE ODOO SESSION',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ],
                ),
                const Divider(color: Colors.white12, height: 24),
                _sessionTile('Base URL', _session?['baseUrl'] ?? 'Not set'),
                _sessionTile('Database', _session?['db'] ?? 'Not set'),
                _sessionTile('Device Name', _session?['deviceName'] ?? 'Not set'),
                _sessionTile('Device ID', _session?['deviceId'] ?? 'Not set'),
                _sessionTile('Generated UID', _session?['generatedDeviceId'] ?? 'Not set'),
                _sessionTile('Token', _session?['token'] ?? 'Not set', isSecret: true),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          color: const Color(0xFF1C1C22),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.key, color: Colors.amber),
                    const SizedBox(width: 10),
                    const Text(
                      'DEVELOPER SECRET TOKEN',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.edit, color: Colors.amber, size: 20),
                      onPressed: _changeSecretTokenDialog,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Current Token: $_secretToken',
                  style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Use this token to unlock the database inspector view anytime.',
                  style: TextStyle(color: Colors.grey, fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _sessionTile(String label, String value, {bool isSecret = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: SelectableText(
              isSecret ? '${value.take(12)}...' : value,
              style: TextStyle(color: isSecret ? Colors.amber : Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // TAB 4: JSON DUMP TAB
  // ===========================================================================
  Widget _buildJsonDumpTab() {
    return FutureBuilder<Map<String, dynamic>>(
      future: DatabaseHelper.instance.exportFullDatabaseToJson(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator(color: Colors.amber));
        }

        final dumpStr = const JsonEncoder.withIndent('  ').convert(snapshot.data);

        return Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              color: const Color(0xFF141418),
              child: Row(
                children: [
                  const Icon(Icons.terminal, color: Colors.amber, size: 20),
                  const SizedBox(width: 8),
                  const Text('Raw Database JSON Payload', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  ElevatedButton.icon(
                    onPressed: _exportAndCopyDump,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black),
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('Copy JSON', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: SelectableText(
                  dumpStr,
                  style: const TextStyle(color: Color(0xFF80FA68), fontFamily: 'monospace', fontSize: 11),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PunchLogCard extends StatefulWidget {
  const _PunchLogCard({required this.log});

  final Map<String, dynamic> log;

  @override
  State<_PunchLogCard> createState() => _PunchLogCardState();
}

class _PunchLogCardState extends State<_PunchLogCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.log;
    final id = item['id'] as String? ?? '';
    final name = item['employeeName'] as String? ?? 'Unknown';
    final timestamp = item['timestamp'] as String? ?? '';
    final isSynced = item['isSynced'] as bool? ?? false;
    final syncError = item['syncError'] as String?;
    final payload = item['payload'] as Map<String, dynamic>? ?? {};

    final statusColor = isSynced ? Colors.green : (syncError != null ? Colors.redAccent : Colors.orange);
    final statusText = isSynced ? 'Synced' : (syncError != null ? 'Sync Failed' : 'Pending Offline');

    return Card(
      color: const Color(0xFF1C1C22),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isSynced ? Icons.check_circle : Icons.offline_pin,
                    color: statusColor,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(height: 2),
                      Text('$timestamp | ID: $id', style: const TextStyle(color: Colors.grey, fontSize: 11)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            if (syncError != null && syncError.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning, color: Colors.redAccent, size: 14),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(syncError, style: const TextStyle(color: Colors.redAccent, fontSize: 11)),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Row(
                children: [
                  Text(_expanded ? 'Hide Payload' : 'View Payload', style: const TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.bold)),
                  Icon(_expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: Colors.amber, size: 16),
                ],
              ),
            ),
            if (_expanded) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black38,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  const JsonEncoder.withIndent('  ').convert(payload),
                  style: const TextStyle(color: Colors.lightGreenAccent, fontFamily: 'monospace', fontSize: 10),
                ),
              ),
            ]
          ],
        ),
      ),
    );
  }
}

extension StringUtils on String {
  String take(int n) => length <= n ? this : substring(0, n);
}
