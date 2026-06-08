// ignore_for_file: avoid_print

import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  final url = Uri.parse('http://192.168.0.171:8069/web/database/list');
  final body = {
    'jsonrpc': '2.0',
    'method': 'call',
    'params': <String, dynamic>{},
  };
  final response = await http.post(
    url,
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode(body),
  );
  print('Status: ${response.statusCode}');
  print('Body: ${response.body}');
}
