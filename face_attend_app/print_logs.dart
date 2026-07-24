import 'dart:convert';
import 'dart:io';

void main() async {
  final home = Platform.environment['HOME'];
  if (home == null) {
    print('Error: Could not find HOME environment variable.');
    exit(1);
  }

  final searchPaths = [
    '$home/Documents/face_attend_punch_logs.json',
    '$home/.local/share/com.example.face_attend_app/face_attend_punch_logs.json',
    '$home/.local/share/face_attend_app/face_attend_punch_logs.json',
  ];

  File? logFile;
  for (final path in searchPaths) {
    final file = File(path);
    if (await file.exists()) {
      logFile = file;
      break;
    }
  }

  // If not found in common locations, search recursively in .local/share and Documents
  if (logFile == null) {
    print('Searching for face_attend_punch_logs.json recursively in ~/.local/share and ~/Documents...');
    final dirsToSearch = [
      Directory('$home/.local/share'),
      Directory('$home/Documents'),
    ];

    for (final dir in dirsToSearch) {
      if (await dir.exists()) {
        try {
          await for (final entity in dir.list(recursive: true, followLinks: false)) {
            if (entity is File && entity.path.endsWith('face_attend_punch_logs.json')) {
              logFile = entity;
              break;
            }
          }
        } catch (_) {}
      }
      if (logFile != null) break;
    }
  }

  if (logFile == null) {
    print('Error: face_attend_punch_logs.json not found.');
    print('Make sure the app has run and saved logs at least once.');
    exit(1);
  }

  print('Found log file at: ${logFile.path}\n');
  print('=================== ALL PUNCH LOGS ===================');

  try {
    final contents = await logFile.readAsString();
    final decoded = jsonDecode(contents) as List<dynamic>;
    
    print('Total logs count: ${decoded.length}\n');
    
    for (int i = 0; i < decoded.length; i++) {
      final item = decoded[i] as Map<String, dynamic>;
      final timestamp = item['timestamp'] as String? ?? 'N/A';
      final employeeName = item['employeeName'] as String? ?? 'Unknown';
      final isSynced = item['isSynced'] as bool? ?? false;
      final syncError = item['syncError'] as String?;
      final payload = item['payload'] as Map<String, dynamic>? ?? {};

      print('[$i] Date: $timestamp | Employee: $employeeName');
      print('    Synced: $isSynced');
      if (syncError != null) {
        print('    Sync Error: $syncError');
      }
      print('    Payload Details:');
      payload.forEach((key, value) {
        print('      $key: $value');
      });
      print('----------------------------------------------------');
    }
  } catch (e) {
    print('Error reading/parsing log file: $e');
  }
  print('======================================================');
}
