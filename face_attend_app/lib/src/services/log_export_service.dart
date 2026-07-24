import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'local_log_service.dart';

class LogExportService {
  static Future<void> exportToPdf(List<LocalPunchLog> logs) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          pw.Header(
            level: 0,
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'PISmartPunch - Face Attendance Logs',
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text(
                  'Exported: ${DateTime.now().toString().split('.')[0]}',
                  style: const pw.TextStyle(fontSize: 9),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 15),
          pw.TableHelper.fromTextArray(
            headers: [
              'Timestamp',
              'Employee Name',
              'Status',
              'Match Score',
              'Reason',
            ],
            data: logs.map((log) {
              final payload = log.payload;
              final accepted = payload['accepted'] as bool? ?? false;
              final score = (payload['match_score'] as num? ?? 0.0).toDouble();

              String status = '';
              if (log.isSynced) {
                status = accepted ? 'Synced' : 'Match Failed';
              } else {
                //  status = log.syncError != null ? 'Sync Error' : 'Offline';
              }

              return [
                log.timestamp.toString().split('.')[0],
                log.employeeName,
                status,
                '${(score * 100).toStringAsFixed(1)}%',
                payload['failure_reason']?.toString() ?? '',
              ];
            }).toList(),
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
            headerStyle: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              fontSize: 9,
            ),
            cellStyle: const pw.TextStyle(fontSize: 8),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
            cellAlignment: pw.Alignment.centerLeft,
          ),
        ],
      ),
    );

    final output = await getTemporaryDirectory();
    final file = File(
      "${output.path}/face_attend_logs_${DateTime.now().millisecondsSinceEpoch}.pdf",
    );
    await file.writeAsBytes(await pdf.save());

    await Share.shareXFiles([
      XFile(file.path),
    ], text: 'Face Attendance Logs PDF');
  }

  static Future<void> exportToExcel(List<LocalPunchLog> logs) async {
    final excel = Excel.createExcel();
    final sheet = excel[excel.getDefaultSheet() ?? 'Sheet1'];

    sheet.appendRow([
      TextCellValue('Timestamp'),
      TextCellValue('Employee Name'),
      TextCellValue('Status'),
      TextCellValue('Match Score (%)'),
      TextCellValue('Failure Reason'),
      TextCellValue('Device ID'),
      TextCellValue('App Version'),
      TextCellValue('Liveness Passed'),
      TextCellValue('Liveness Score'),
      TextCellValue('Spoof Score'),
    ]);

    for (final log in logs) {
      final payload = log.payload;
      final accepted = payload['accepted'] as bool? ?? false;
      final score = (payload['match_score'] as num? ?? 0.0).toDouble();

      String status = '';
      if (log.isSynced) {
        status = accepted ? 'Synced' : 'Match Failed';
      } else {
        //  status = log.syncError != null ? 'Sync Error' : 'Offline';
      }

      sheet.appendRow([
        TextCellValue(log.timestamp.toString().split('.')[0]),
        TextCellValue(log.employeeName),
        TextCellValue(status),
        DoubleCellValue(score * 100),
        TextCellValue(payload['failure_reason']?.toString() ?? ''),
        TextCellValue(payload['device_id']?.toString() ?? ''),
        TextCellValue(payload['app_version']?.toString() ?? ''),
        TextCellValue(payload['liveness_passed'] == true ? 'Yes' : 'No'),
        DoubleCellValue((payload['liveness_score'] as num? ?? 0.0).toDouble()),
        DoubleCellValue((payload['spoof_score'] as num? ?? 0.0).toDouble()),
      ]);
    }

    final fileBytes = excel.save();
    if (fileBytes != null) {
      final output = await getTemporaryDirectory();
      final file = File(
        "${output.path}/face_attend_logs_${DateTime.now().millisecondsSinceEpoch}.xlsx",
      );
      await file.writeAsBytes(fileBytes);
      await Share.shareXFiles([
        XFile(file.path),
      ], text: 'Face Attendance Logs Excel');
    }
  }
}
