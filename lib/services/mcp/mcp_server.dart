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
            {'name': 'yhdm', 'description': '分析网站生成番剧解析规则', 'inputSchema': {'type': 'object', 'properties': {'url': {'type': 'string', 'description': '番剧网站URL'}}, 'required': ['url']}},
            {'name': 'validate_rule', 'description': '校验并规范化Kazumi番剧规则(XPath/JSON API/混合)，生成 yhdmgz:// 导入链接。输入可为规则JSON、Base64或yhdmgz://链接。', 'inputSchema': {'type': 'object', 'properties': {'rule': {'type': 'string', 'description': '规则JSON / Base64 / yhdmgz://链接'}, 'format': {'type': 'string', 'enum': ['json', 'base64', 'link']}}, 'required': ['rule']}}
          ]}});
          break;
        case 'tools/call':
          final name = data['params']?['name'] ?? 'yhdm';
          final args = data['params']?['arguments'] ?? <String, dynamic>{};
          if (name == 'validate_rule') {
            final result = _validateRule((args['rule'] ?? '').toString());
            _ok(req, {'jsonrpc': '2.0', 'id': id, 'result': {'content': [{'type': 'text', 'text': jsonEncode(result)}]}});
          } else {
            final url = args['url'] ?? '';
            _ok(req, {'jsonrpc': '2.0', 'id': id, 'result': {'content': [{'type': 'text', 'text': '请分析网站 $url 并生成Kazumi规则。\n\n$_rulePrompt'}]}});
          }
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

  // ============ validate_rule：校验规则并生成 yhdmgz:// 链接 ============
  Map<String, dynamic> _validateRule(String raw) {
    Map<String, dynamic> rule;
    var source = raw.trim();
    try {
      if (source.startsWith('yhdmgz://')) {
        source = utf8.decode(base64Decode(base64.normalize(source.substring(9))));
      } else if (source.startsWith('kazumi://')) {
        source = utf8.decode(base64Decode(base64.normalize(source.substring(9))));
      } else if (!source.startsWith('{')) {
        // 尝试 Base64 解码
        try {
          source = utf8.decode(base64Decode(base64.normalize(source)));
        } catch (_) {}
      }
      final decoded = jsonDecode(source);
      if (decoded is! Map) {
        return {'ok': false, 'errors': ['规则必须是单个 JSON 对象，不能是数组']};
      }
      rule = Map<String, dynamic>.from(decoded);
    } catch (e) {
      return {'ok': false, 'errors': ['无法解析输入: $e']};
    }

    final errors = <String>[];

    // 必填字段
    for (final f in ['api', 'type', 'name', 'version', 'baseURL']) {
      final v = rule[f];
      if (v == null || v.toString().trim().isEmpty) {
        errors.add('缺少必填字段: $f');
      }
    }

    final searchMode = (rule['searchMode'] ?? 'xpath').toString();
    final chapterMode = (rule['chapterMode'] ?? 'xpath').toString();

    // XPath 受限语法校验
    const xpathFields = [
      'searchURL', 'searchList', 'searchName', 'searchResult',
      'chapterRoads', 'chapterResult',
    ];
    for (final f in xpathFields) {
      final v = rule[f];
      if (v is String && v.isNotEmpty) {
        if (f != 'searchURL' && !v.trimLeft().startsWith('//')) {
          errors.add('$f 选择器必须以 // 开头');
        }
        _checkUnsupportedXpath(v, f, errors);
      }
    }

    // JSONPath 合规校验
    final apiCfgFields = ['searchApiConfig', 'chapterApiConfig'];
    for (final f in apiCfgFields) {
      final cfg = rule[f];
      if (cfg is Map) {
        final cfgMap = Map<String, dynamic>.from(cfg);
        final path = cfgMap['path'];
        if (path is String && path.isNotEmpty) _checkJsonPath(path, '$f.path', errors);
        for (final k in [
          'roadsPath', 'roadNamePath', 'episodesPath', 'episodeNamePath',
          'episodeUrlPath', 'roadNamesPath', 'roadEpisodesPath',
        ]) {
          final p = cfgMap[k];
          if (p is String && p.isNotEmpty) _checkJsonPath(p, '$f.$k', errors);
        }
      }
    }

    final base64Str = base64Encode(utf8.encode(jsonEncode(rule)));
    return {
      'ok': errors.isEmpty,
      'errors': errors,
      'name': rule['name'],
      'searchMode': searchMode,
      'chapterMode': chapterMode,
      'base64': base64Str,
      'importLink': 'yhdmgz://$base64Str',
    };
  }

  void _checkUnsupportedXpath(String s, String field, List<String> errors) {
    const pats = [
      ['contains(', 'contains() 不兼容，用 [@attr*="value"]'],
      ['starts-with(', 'starts-with() 不兼容，用 [@attr^="value"]'],
      ['text()', 'text() 不支持'],
      ['normalize-space(', 'normalize-space() 不支持'],
      ['substring(', 'substring() 不支持'],
      ['::', 'XPath 轴 :: 不支持'],
    ];
    for (final p in pats) {
      if (s.contains(p[0])) errors.add('$field: ${p[1]}');
    }
    if (s.contains('|')) errors.add('$field: XPath 并集 | 不支持');
    if (s.contains('/..') || s.contains('(')) {
      if (s.contains('/..')) errors.add('$field: 父级遍历 .. 不支持');
    }
    if (RegExp(r'\band\b|\bor\b', caseSensitive: false).hasMatch(s)) {
      errors.add('$field: XPath 布尔谓词 and/or 不支持');
    }
  }

  void _checkJsonPath(String p, String field, List<String> errors) {
    if (!p.startsWith('\$')) errors.add('$field: JSONPath 必须以 \$ 开头');
    if (p.contains('\$..')) errors.add('$field: 递归 \$.. 不支持');
    if (RegExp(r'\[\?').hasMatch(p)) errors.add('$field: 过滤 [?()] 不支持');
    if (RegExp(r'\[[^\]\[]*:').hasMatch(p)) errors.add('$field: 切片 [a:b] 不支持');
  }
}
