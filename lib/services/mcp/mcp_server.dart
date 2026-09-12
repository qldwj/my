import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:kazumi/services/logging/logger.dart';

/// MCP 服务端 - AI规则生成器
class McpServer {
  static McpServer? _instance;
  static McpServer get instance => _instance ??= McpServer._();
  McpServer._();

  HttpServer? _server;
  int _port = 7676;
  bool _running = false;

  bool get isRunning => _running;
  int get port => _port;
  String get url => 'http://127.0.0.1:$_port/mcp';

  static const String _rulePrompt = '你是番剧网站规则编写专家。分析网站并编写樱花动漫兼容的解析规则。规则JSON包含name/baseUrl/search/detail/player字段。输出base64编码后加前缀yhdmgz://rule/import?data=';

  Future<void> start({int? port}) async {
    if (_running) return;
    if (port != null) _port = port;
    try {
      _server = await HttpServer.bind(Internet.loopbackIPv4, _port);
      _running = true;
      KazumiLogger().i('MCP Server: 启动于 $url');
      _server!.listen(_handleRequest);
    } catch (e) {
      KazumiLogger().e('MCP Server: 启动失败', error: e);
      rethrow;
    }
  }

  Future<void> stop() async {
    if (!_running) return;
    await _server?.close();
    _server = null;
    _running = false;
    KazumiLogger().i('MCP Server: 已停止');
  }

  void _handleRequest(HttpRequest request) {
    request.response.headers.add('Access-Control-Allow-Origin', '*');
    request.response.headers.add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    request.response.headers.add('Access-Control-Allow-Headers', 'Content-Type');
    request.response.headers.contentType = ContentType.json;

    if (request.method == 'OPTIONS') { request.response.close(); return; }

    final path = request.uri.path;
    if (path == '/mcp' || path == '/mcp/') {
      _handleMcp(request);
    } else if (path == '/mcp/health') {
      _respond(request, {'status': 'ok', 'port': _port});
    } else {
      request.response.statusCode = 404;
      _respond(request, {'error': 'Not found'});
    }
  }

  void _handleMcp(HttpRequest request) async {
    if (request.method == 'POST') {
      final body = await utf8.decoder.bind(request).join();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final method = data['method'] as String?;
      final id = data['id'];

      switch (method) {
        case 'initialize':
          _respond(request, {
            'jsonrpc': '2.0', 'id': id,
            'result': {
              'protocolVersion': '2024-11-05',
              'capabilities': {'tools': {}, 'prompts': {}},
              'serverInfo': {'name': 'Kazumi MCP', 'version': '1.0.0'},
            },
          });
          break;
        case 'tools/list':
          _respond(request, {
            'jsonrpc': '2.0', 'id': id,
            'result': {'tools': [
              {'name': 'generate_rule', 'description': '分析网站生成规则', 'inputSchema': {'type': 'object', 'properties': {'url': {'type': 'string'}}, 'required': ['url']}},
            ]},
          });
          break;
        case 'tools/call':
          final toolName = data['params']?['name'];
          final url = data['params']?['arguments']?['url'] ?? '';
          _respond(request, {
            'jsonrpc': '2.0', 'id': id,
            'result': {'content': [{'type': 'text', 'text': '分析 $url 并生成规则\n\n$_rulePrompt'}]},
          });
          break;
        case 'prompts/list':
          _respond(request, {
            'jsonrpc': '2.0', 'id': id,
            'result': {'prompts': [{'name': 'rule_guide', 'description': '规则编写指南'}]},
          });
          break;
        default:
          _respond(request, {'jsonrpc': '2.0', 'id': id, 'error': {'code': -32601, 'message': 'Method not found'}});
      }
    } else {
      _respond(request, {'name': 'Kazumi MCP', 'version': '1.0.0', 'port': _port});
    }
  }

  void _respond(HttpRequest request, dynamic data) {
    request.response.write(jsonEncode(data));
    request.response.close();
  }
}
