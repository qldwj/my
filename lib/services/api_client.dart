// services/api_client.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiClient {
  static const String baseUrl = 'https://qlyyz.xyz/api';
  final http.Client httpClient;

  ApiClient({http.Client? client}) : httpClient = client ?? http.Client();

  Uri _buildUri(String path, [Map<String, String>? queryParameters]) {
    final p = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$baseUrl$p').replace(queryParameters: queryParameters);
  }

  Future<Map<String, dynamic>> get(String path, {Map<String, String>? queryParameters}) async {
    final uri = _buildUri(path, queryParameters);
    final resp = await httpClient.get(uri);
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      return json.decode(resp.body) as Map<String, dynamic>;
    } else {
      throw Exception('GET $path failed: ${resp.statusCode} ${resp.body}');
    }
  }

  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body) async {
    final uri = _buildUri(path);
    final resp = await httpClient.post(uri, body: json.encode(body), headers: {'Content-Type': 'application/json'});
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      return json.decode(resp.body) as Map<String, dynamic>;
    } else {
      throw Exception('POST $path failed: ${resp.statusCode} ${resp.body}');
    }
  }

  Future<void> delete(String path) async {
    final uri = _buildUri(path);
    final resp = await httpClient.delete(uri);
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('DELETE $path failed: ${resp.statusCode} ${resp.body}');
    }
  }
}
