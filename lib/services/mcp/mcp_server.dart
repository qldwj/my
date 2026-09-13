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

  static const String _rulePrompt = '''
你是一个番剧网站规则编写专家。请根据用户提供的网站URL，编写一个Kazumi兼容的解析规则。

## 规则结构（JSON）
规则支持两种模式：xpath模式和api模式。

### xpath模式示例：
{
  "name": "规则名称",
  "version": "1.0",
  "search": {
    "mode": "xpath",
    "method": "GET",
    "url": "https://example.com/search?keyword={keyword}",
    "listPath": "//div[@class='item']",
    "namePath": ".//a/text()",
    "sourcePath": ".//a/@href"
  },
  "detail": {
    "titlePath": "//h1/text()",
    "coverPath": "//img/@src",
    "descPath": "//div[@class='desc']/text()",
    "episodePath": "//div[@class='episodes']/a"
  }
}

### API模式示例：
{
  "name": "规则名称",
  "version": "1.0",
  "mode": "api",
  "search": {
    "mode": "api",
    "request": {"method": "GET", "url": "https://api.example.com/search?keyword={keyword}"},
    "listPath": "\$.data[*]",
    "namePath": "\$.name",
    "sourcePath": "\$.url"
  },
  "chapter": {
    "request": {"method": "GET", "url": "https://api.example.com/episodes/{id}"},
    "format": "nested",
    "roadsPath": "\$.data.roads[*]",
    "roadNamePath": "\$.name",
    "episodesPath": "\$.episodes[*]",
    "episodeNamePath": "\$.name",
    "episodeUrlPath": "\$.url"
  }
}

## 分析步骤
1. 访问网站主页，分析页面结构和API
2. 找到搜索功能，分析搜索接口（URL/参数/返回格式）
3. 找到番剧详情页，分析HTML结构或API
4. 找到播放地址获取方式
5. 编写完整规则

## 输出格式
将规则JSON进行base64编码，在前面加上：
yhdmgz://

例如：yhdmgz://eyJuYW1lIjoiVGVzdCIs...

最终输出完整链接，用户可直接复制导入。
''';

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
    if (req.method == 'OPTIONS') { req.response.close(); return; }
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
          _ok(req, {'jsonrpc': '2.0', 'id': id, 'result': {'protocolVersion': '2024-11-05', 'capabilities': {'tools': {}, 'prompts': {}}, 'serverInfo': {'name': 'Kazumi MCP', 'version': '1.0.0'}}});
          break;
        case 'tools/list':
          _ok(req, {'jsonrpc': '2.0', 'id': id, 'result': {'tools': [
            {'name': 'yhdm', 'description': '分析网站生成番剧解析规则', 'inputSchema': {'type': 'object', 'properties': {'url': {'type': 'string', 'description': '番剧网站URL'}}, 'required': ['url']}}
          ]}});
          break;
        case 'tools/call':
          final url = data['params']?['arguments']?['url'] ?? '';
          _ok(req, {'jsonrpc': '2.0', 'id': id, 'result': {'content': [{'type': 'text', 'text': '请分析网站 $url 并生成Kazumi规则。\n\n$_rulePrompt'}]}});
          break;
        case 'prompts/list':
          _ok(req, {'jsonrpc': '2.0', 'id': id, 'result': {'prompts': [{'name': 'rule_guide', 'description': 'Kazumi规则编写完整指南'}]}});
          break;
        case 'prompts/get':
          _ok(req, {'jsonrpc': '2.0', 'id': id, 'result': {'description': '规则编写指南', 'messages': [{'role': 'user', 'content': {'type': 'text', 'text': _rulePrompt}}]}});
          break;
        default:
          _ok(req, {'jsonrpc': '2.0', 'id': id, 'error': {'code': -32601, 'message': 'Method not found'}});
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
