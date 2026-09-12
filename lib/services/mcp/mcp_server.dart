import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:kazumi/services/logging/logger.dart';

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

  static const String _rulePrompt =
      '你是番剧网站规则编写专家。分析网站并编写樱花动漫兼容的解析规则。'
      '规则JSON包含name/baseUrl/search/detail/player字段。'
      '输出base64编码后加前缀yhdmgz://rule/import?data=';

  Future<void> start({int? port}) async {
    if (_running) return;
    if (port != null) _port = port;
    final addr = InternetAddress.loopbackIPv4;
    _server = await HttpServer.bind(addr, _port);
    _running = true;
    KazumiLogger().i('MCP Server: $url');
    _server!.listen(_handleRequest);
  }

  Future<void> stop() async {
    if (!_running) return;
    await _server?.close();
    _server = null;
    _running = false;
  }

  void _handleRequest(HttpRequest req) {
    req.response.headers.add('Access-Control-Allow-Origin', '*');
    req.response.headers.add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    req.response.headers.add('Access-Control-Allow-Headers', 'Content-Type');
    req.response.headers.contentType = ContentType.json;
    if (req.method == 'OPTIONS') {
      req.response.close();
      return;
    }
    final p = req.uri.path;
    if (p == '/mcp' || p == '/mcp/') {
      _handleMcp(req);
    } else if (p == '/mcp/health') {
      _ok(req, {'status': 'ok', 'port': _port});
    } else {
      req.response.statusCode = 404;
      _ok(req, {'error': 'Not found'});
    }
  }

  void _handleMcp(HttpRequest req) async {
    if (req.method == 'POST') {
      final body = await utf8.decoder.bind(req).join();
      final data = jsonDecode(body) as Map<String, dynamic>;
      final method = data['method'] as String?;
      final id = data['id'];
      switch (method) {
        case 'initialize':
          _ok(req, {
            'jsonrpc': '2.0',
            'id': id,
            'result': {
              'protocolVersion': '2024-11-05',
              'capabilities': {'tools': {}, 'prompts': {}},
              'serverInfo': {'name': 'Kazumi MCP', 'version': '1.0.0'},
            },
          });
          break;
        case 'tools/list':
          _ok(req, {
            'jsonrpc': '2.0',
            'id': id,
            'result': {
              'tools': [
                {
                  'name': 'generate_rule',
                  'description': '分析网站生成规则',
                  'inputSchema': {
                    'type': 'object',
                    'properties': {
                      'url': {'type': 'string'}
                    },
                    'required': ['url']
                  }
                }
              ]
            },
          });
          break;
        case 'tools/call':
          final url = data['params']?['arguments']?['url'] ?? '';
          _ok(req, {
            'jsonrpc': '2.0',
            'id': id,
            'result': {
              'content': [
                {'type': 'text', 'text': '分析 $url 并生成规则\n\n$_rulePrompt'}
              ]
            },
          });
          break;
        case 'prompts/list':
          _ok(req, {
            'jsonrpc': '2.0',
            'id': id,
            'result': {
              'prompts': [
                {'name': 'rule_guide', 'description': '规则编写指南'}
              ]
            },
          });
          break;
        default:
          _ok(req, {
            'jsonrpc': '2.0',
            'id': id,
            'error': {'code': -32601, 'message': 'Method not found'}
          });
      }
    } else {
      _ok(req, {'name': 'Kazumi MCP', 'version': '1.0.0', 'port': _port});
    }
  }

  void _ok(HttpRequest req, dynamic data) {
    req.response.write(jsonEncode(data));
    req.response.close();
  }
}
