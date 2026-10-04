import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:xpath_selector_html_parser/xpath_selector_html_parser.dart';
import 'package:kazumi/services/plugin/api_rule_strategy.dart';
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
你是 Kazumi 番剧规则编写专家。请严格按以下官方规范生成规则。

📖 官方文档（必读，优先于任何记忆）：
- 官网：https://kazumi.app/
- 下载页：https://kazumi.app/download.html
- GitHub：https://github.com/Predidit/Kazumi
- XPath 规则开发：https://kazumi.app/docs/rules/develop-rules
- 规则介绍（总览）：https://kazumi.app/docs/rules/introduce-rules
- XPath 规则示例：https://kazumi.app/docs/rules/develop-rules-example
- 社区教程：https://www.kshare.top
- API 规则开发：https://kazumi.app/docs/rules/develop-api-rules
- 官方规则仓库（含 API Level 说明）：https://github.com/Predidit/KazumiRules
- 视频嗅探原理：https://kazumi.app/docs/architecture/video-parser
- 技术博客：https://www.cnblogs.com/1288blog/p/19506033

⚠️ 关键提醒（我踩过的坑，务必避免）：
1. 规则字段是【扁平结构】，不是嵌套结构。禁止使用 search.mode / search.url / detail.titlePath 这类字段名。
2. 搜索占位符是 @keyword，不是 {keyword}。相关占位符还有 @source / @roadIndex / @episodeIndex（从0开始）/ @roadNumber / @episodeNumber（从1开始）。
3. searchList / searchName / searchResult / chapterRoads / chapterResult 一律用【绝对路径】，以 // 开头。
4. contains() 在官方规则里可以用（dalvdm、MXdm 都在用），不要禁止。
5. type 字段是站点类型（"anime"），不是 "xpath"。
6. api 是版本兼容级别（字符串），取值 "1"~"8"，对应不同 Kazumi 版本。
7. searchURL 末尾常有 &submit=（maccms 站点常见）。
8. 规则在 KazumiRules 仓库【根目录】，不在 rules/ 子目录下。

✅ 规则模板（以此为基准，字段名和结构照抄）：
{
  "api": "5",
  "type": "anime",
  "name": "站点名称",
  "version": "1.0",
  "muliSources": true,
  "useWebview": true,
  "useNativePlayer": true,
  "usePost": false,
  "useLegacyParser": false,
  "adBlocker": true,
  "userAgent": "",
  "baseURL": "https://example.com",
  "searchURL": "https://example.com/search/-------------.html?wd=@keyword&submit=",
  "searchList": "//ul[@class*='v_list']/li/div[@class='item']",
  "searchName": "//a[@class='title']",
  "searchResult": "//a[@class='title']",
  "chapterRoads": "//div[@id='play_list']//ul[@class='play_list']",
  "chapterResult": "//ul[@class='play_list']/li/a"
}

📋 输出要求：
- 先实际访问目标网站，分析搜索页/详情页/播放页的真实 HTML 结构，再写 XPath。
- 不要凭猜测写 XPath，必须基于真实 DOM。
- 输出完整 JSON，并在最后附上 yhdmgz:// base64 导入链接。
- 若道路与分集在 DOM 中不嵌套，用单一 road 处理。
- 若站点有验证码，加 antiCrawlerConfig。

✅ 客户端测试闭环（交付前必须）：
- 生成规则后，用应用内置的 test_rule 工具真实抓站验证：
  1. 搜索结果数 > 0；
  2. chapterRoads 匹配线路数 > 0；
  3. 每条线路 chapterResult 都有集数；
  4. 实际播放页能嗅探到播放地址。
- 全部通过才能交付给用户；不通过则回查对应 XPath / JSONPath 修正。

📌 API 选集分隔符格式（maccms 常见，非嵌套 JSON）：
- 使用 chapterApiConfig.format = "delimited"；
- roadNamesPath 取线路名列表、roadEpisodesPath 取线路分集字符串列表；
- 配 roadSeparator（默认 $$$）、episodeSeparator（默认 #）、fieldSeparator（默认 $）。
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
            {'name': 'validate_rule', 'description': '校验并规范化Kazumi番剧规则(XPath/JSON API/混合)，生成 yhdmgz:// 导入链接。输入可为规则JSON、Base64或yhdmgz://链接。', 'inputSchema': {'type': 'object', 'properties': {'rule': {'type': 'string', 'description': '规则JSON / Base64 / yhdmgz://链接'}, 'format': {'type': 'string', 'enum': ['json', 'base64', 'link']}}, 'required': ['rule']}},
            {'name': 'test_rule', 'description': '真实抓站验证XPath规则是否可用：实际请求搜索页与详情页，统计搜索结果数、线路数、各线路集数。输入规则与测试关键词。', 'inputSchema': {'type': 'object', 'properties': {'rule': {'type': 'string', 'description': '规则JSON / Base64 / yhdmgz://链接'}, 'keyword': {'type': 'string', 'description': '测试关键词，如 仙逆'}}, 'required': ['rule', 'keyword']}}
          ]}});
          break;
        case 'tools/call':
          final name = data['params']?['name'] ?? 'yhdm';
          final args = data['params']?['arguments'] ?? <String, dynamic>{};
          if (name == 'validate_rule') {
            final result = _validateRule((args['rule'] ?? '').toString());
            _ok(req, {'jsonrpc': '2.0', 'id': id, 'result': {'content': [{'type': 'text', 'text': jsonEncode(result)}]}});
          } else if (name == 'test_rule') {
            final rule = (args['rule'] ?? '').toString();
            final keyword = (args['keyword'] ?? '').toString();
            _testRule(rule, keyword).then((result) {
              _ok(req, {'jsonrpc': '2.0', 'id': id, 'result': {'content': [{'type': 'text', 'text': jsonEncode(result)}]}});
            });
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
    final warnings = <String>[];

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
        _checkUnsupportedXpath(v, f, errors, warnings);
      }
    }

    // 字段白名单：未知顶级字段提示（可能是幻觉字段）。来源：KazumiRules 官方字段 + 本 App 扩展。
    const allowedFields = <String>{
      'api', 'type', 'name', 'version', 'muliSources', 'useWebview',
      'useNativePlayer', 'usePost', 'useLegacyParser', 'adBlocker',
      'userAgent', 'baseURL', 'referer', 'cookie', 'updateURL',
      'searchURL', 'searchList', 'searchName', 'searchResult',
      'chapterRoads', 'chapterResult', 'chapterResultURL', 'searchMode',
      'chapterMode', 'icon', 'antiCrawlerConfig', 'searchApiConfig',
      'chapterApiConfig', 'useProxy', 'variables',
    };
    for (final k in rule.keys) {
      if (!allowedFields.contains(k)) {
        warnings.add('未知/非官方顶级字段: "$k"（官方字段见模板：name/version/api/type/baseURL/searchURL/searchList/searchName/searchResult/chapterRoads/chapterResult 等）');
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
    final icon = rule['icon'];
    if (icon == null || icon.toString().trim().isEmpty) {
      warnings.add('icon 为【非官方字段】（官方规则无此字段，仅本 App 本地用于规则列表显示站点图标），可选；未提供时 App 规则列表将不显示图标');
    }

    // 往返校验（幂等）：base64 解码还原后应与原始规则一致
    try {
      final redecoded = jsonDecode(utf8.decode(base64Decode(base64Str)));
      if (jsonEncode(redecoded) != jsonEncode(rule)) {
        warnings.add('往返校验不一致：解码还原后的规则与原始输入有差异');
      }
    } catch (e) {
      warnings.add('往返解码失败: $e');
    }

    // API 模式 episodePage 模板变量校验（补 API 规则支持严谨性）
    for (final f in apiCfgFields) {
      final cfg = rule[f];
      if (cfg is Map) {
        final ep = cfg['episodePage'];
        if (ep is Map) {
          final epUrl = ep['url'];
          if (epUrl is String && epUrl.isNotEmpty) {
            final allowed = RegExp(r'@(source|episodeUrl|roadIndex|roadNumber|episodeIndex|episodeNumber|keyword)');
            final unknowns = RegExp(r'@[a-zA-Z]+').allMatches(epUrl)
                .map((m) => m.group(0))
                .where((v) => v != null && !allowed.hasMatch(v))
                .toList();
            if (unknowns.isNotEmpty) {
              warnings.add('$f.episodePage.url 含未知模板变量: ${unknowns.join(', ')}（仅支持 @source/@episodeUrl/@roadIndex/@roadNumber/@episodeIndex/@episodeNumber/@keyword）');
            }
          }
        }
      }
    }

    return {
      'ok': errors.isEmpty,
      'errors': errors,
      'warnings': warnings,
      'icon': icon == null || icon.toString().trim().isEmpty
          ? ''
          : icon.toString(),
      'name': rule['name'],
      'searchMode': searchMode,
      'chapterMode': chapterMode,
      'base64': base64Str,
      'importLink': 'yhdmgz://$base64Str',
    };
  }

  void _checkUnsupportedXpath(String s, String field, List<String> errors, List<String> warnings) {
    const pats = [
      // contains() 官方规则 dalvdm/MXdm 都在用，仅警告不阻断
      ['starts-with(', 'starts-with() 不兼容，用 [@attr^="value"]'],
      ['text()', 'text() 不支持'],
      ['normalize-space(', 'normalize-space() 不支持'],
      ['substring(', 'substring() 不支持'],
      ['::', 'XPath 轴 :: 不支持'],
    ];
    if (s.contains('contains(')) {
      warnings.add('$field: 使用了 contains()（官方 dalvdm/MXdm 也在用，兼容；如遇兼容问题可改用 [@attr*="value"]）');
    }
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

  // ============ test_rule：真实抓站验证 XPath 规则 ============
  Map<String, dynamic>? _decodeRule(String raw) {
    var source = raw.trim();
    try {
      if (source.startsWith('yhdmgz://') || source.startsWith('kazumi://')) {
        source = utf8.decode(base64Decode(base64.normalize(source.substring(9))));
      } else if (!source.startsWith('{')) {
        try {
          source = utf8.decode(base64Decode(base64.normalize(source)));
        } catch (_) {}
      }
      final decoded = jsonDecode(source);
      if (decoded is! Map) return null;
      return Map<String, dynamic>.from(decoded);
    } catch (e) {
      return null;
    }
  }

  List<dynamic> _xpathNodes(dynamic node, String? expr) {
    if (expr == null || expr.trim().isEmpty) return const [];
    try {
      return List<dynamic>.from(node.queryXPath(expr).nodes);
    } catch (_) {
      return const [];
    }
  }

  String _xpathText(dynamic node, String? expr) {
    if (expr == null || expr.trim().isEmpty) return '';
    try {
      return node.queryXPath(expr).node?.text?.trim() ?? '';
    } catch (_) {
      return '';
    }
  }

  String _xpathHref(dynamic node, String? expr) {
    if (expr == null || expr.trim().isEmpty) return '';
    try {
      return node.queryXPath(expr).node?.attributes['href']?.trim() ?? '';
    } catch (_) {
      return '';
    }
  }

  String _attr(dynamic node, String name) {
    try {
      return node.attributes[name]?.trim() ?? '';
    } catch (_) {
      return '';
    }
  }

  /// 生成脱敏 curl 命令：Cookie/Token/Authorization 等凭据替换为 <redacted>
  String _sanitizeCurl(String method, String url, Map<String, String> headers, Object? body) {
    final buf = StringBuffer('curl -X $method "$url"');
    headers.forEach((k, v) {
      final lower = k.toLowerCase();
      if (lower == 'cookie' ||
          lower == 'authorization' ||
          lower.contains('token') ||
          lower == 'x-api-key') {
        buf.write(" -H '$k: <redacted>'");
      } else {
        buf.write(" -H '$k: $v'");
      }
    });
    if (body is Map && body.isNotEmpty) {
      buf.write(" -d '${jsonEncode(body)}'");
    }
    return buf.toString();
  }

  String _replaceVars(String s, Map<String, String> vars) {
    vars.forEach((k, v) => s = s.replaceAll(k, v));
    return s;
  }

  Map<String, dynamic> _replaceVarsMap(Map m, Map<String, String> vars) {
    final out = <String, dynamic>{};
    m.forEach((k, v) {
      out[k.toString()] = v is String ? _replaceVars(v, vars) : v;
    });
    return out;
  }

  /// API 模式请求：构造并发送 searchApiConfig/chapterApiConfig 请求，
  /// 返回解码 JSON + 实际 URL + 脱敏 curl。
  Future<({dynamic json, String url, String curl})?> _apiFetch(
    Map<String, dynamic> request, {
    required String method,
    required Map<String, String> vars,
  }) async {
    var url = (request['url'] ?? '').toString();
    vars.forEach((k, v) => url = url.replaceAll(k, Uri.encodeQueryComponent(v)));
    final headers = <String, String>{
      'User-Agent': 'Mozilla/5.0 (Kazumi-MCP)',
      'Accept': 'application/json',
    };
    final reqHeaders = request['headers'];
    if (reqHeaders is Map) {
      reqHeaders.forEach((k, v) => headers[k.toString()] = v.toString());
    }
    var uri = Uri.parse(url);
    final query = request['query'];
    if (query is Map) {
      final q = <String, String>{};
      query.forEach((k, v) => q[k.toString()] = v.toString());
      final q2 = <String, String>{};
      q.forEach((k, v) => q2[k] = _replaceVars(v, vars));
      uri = uri.replace(queryParameters: q2);
    }
    final fullUrl = uri.toString();
    Object? curlBody;
    http.Response resp;
    if (method.toUpperCase() == 'POST') {
      final rawBody = request['body'];
      if (rawBody is Map) {
        final replaced = _replaceVarsMap(rawBody, vars);
        curlBody = replaced;
        headers['Content-Type'] = 'application/json';
        resp = await http.post(uri, headers: headers, body: jsonEncode(replaced))
            .timeout(const Duration(seconds: 20));
      } else {
        resp = await http.post(uri, headers: headers).timeout(const Duration(seconds: 20));
      }
    } else {
      resp = await http.get(uri, headers: headers).timeout(const Duration(seconds: 20));
    }
    final curl = _sanitizeCurl(method, fullUrl, headers, curlBody);
    try {
      return (json: jsonDecode(resp.body), url: fullUrl, curl: curl);
    } catch (e) {
      throw FormatException('API 响应非 JSON: $e');
    }
  }

  Future<Map<String, dynamic>> _testRule(String raw, String keyword) async {
    final r = _decodeRule(raw);
    if (r == null) {
      return {'ok': false, 'errors': ['无法解析规则：需为规则JSON、Base64 或 yhdmgz:// 链接']};
    }
    final searchMode = (r['searchMode'] ?? 'xpath').toString();
    final chapterMode = (r['chapterMode'] ?? 'xpath').toString();
    final warnings = <String>[];
    final base = (r['baseURL'] ?? '').toString().trim().replaceAll(RegExp(r'/$'), '');
    const ua = {'User-Agent': 'Mozilla/5.0 (Kazumi-MCP)'};

    // 1. 搜索（支持 XPath / API 双模式）
    final items = <Map<String, String>>[];
    String searchUrl = '';
    String searchCurl = '';
    try {
      if (searchMode == 'api') {
        final cfg = r['searchApiConfig'];
        if (cfg is! Map) {
          return {'ok': false, 'errors': ['searchMode=api 但缺少 searchApiConfig']};
        }
        final request = cfg['request'];
        if (request is! Map) {
          return {'ok': false, 'errors': ['searchApiConfig 缺少 request']};
        }
        final method = (request['method'] ?? 'GET').toString();
        final fetched = await _apiFetch(
          Map<String, dynamic>.from(request),
          method: method,
          vars: {'@keyword': keyword},
        );
        if (fetched == null) {
          return {'ok': false, 'errors': ['API 搜索请求失败'], 'warnings': warnings};
        }
        searchUrl = fetched.url;
        searchCurl = fetched.curl;
        final listPath = (cfg['listPath'] ?? '').toString();
        final namePath = (cfg['namePath'] ?? '').toString();
        final sourcePath = (cfg['sourcePath'] ?? '').toString();
        final list = listPath.isEmpty ? <Object?>[] : RestrictedJsonPath.read(fetched.json, listPath);
        if (list.isEmpty) {
          warnings.add('API searchApiConfig.listPath 未匹配到任何结果（请检查 JSONPath 与返回结构）');
        }
        for (final item in list) {
          if (item is! Map) continue;
          final name = namePath.isEmpty ? '' : (RestrictedJsonPath.readFirst(item, namePath)?.toString() ?? '');
          final source = sourcePath.isEmpty ? '' : (RestrictedJsonPath.readFirst(item, sourcePath)?.toString() ?? '');
          if (name.isEmpty && source.isEmpty) continue;
          items.add({'name': name, 'url': source.startsWith('http') ? source : base + source});
        }
      } else {
        final searchUrlTpl = (r['searchURL'] ?? '').toString();
        searchUrl = (searchUrlTpl.contains('@keyword')
                ? searchUrlTpl.replaceAll('@keyword', Uri.encodeQueryComponent(keyword))
                : searchUrlTpl + Uri(queryParameters: {'wd': keyword}))
            .replaceFirst(RegExp(r'^\.?/'), '');
        final finalSearchUrl = searchUrl.startsWith('http') ? searchUrl : base + searchUrl;
        searchUrl = finalSearchUrl;
        final resp = await http.get(Uri.parse(finalSearchUrl), headers: ua)
            .timeout(const Duration(seconds: 20));
        searchCurl = _sanitizeCurl('GET', finalSearchUrl, ua, null);
        final doc = html_parser.parse(resp.body);
        final listNodes = _xpathNodes(doc, r['searchList']?.toString());
        if (listNodes.isEmpty) {
          warnings.add('searchList 未匹配到任何节点，请检查 XPath（搜索可能无结果或选择器错误）');
        }
        for (final node in listNodes) {
          final name = _xpathText(node, r['searchName']?.toString());
          final href = _xpathHref(node, r['searchResult']?.toString());
          if (name.isEmpty && href.isEmpty) continue;
          items.add({'name': name, 'url': href.startsWith('http') ? href : base + href});
        }
      }
    } catch (e) {
      return {'ok': false, 'errors': ['搜索阶段失败: $e'], 'warnings': warnings};
    }

    // 2. 选集（支持 XPath / API 双模式）
    final chapter = <String, dynamic>{
      'detailUrl': '',
      'roads': 0,
      'episodes': <Map<String, dynamic>>[],
      'curl': '',
    };
    if (items.isNotEmpty) {
      final first = items.first;
      chapter['detailUrl'] = first['url'] ?? '';
      try {
        if (chapterMode == 'api') {
          final cfg = r['chapterApiConfig'];
          if (cfg is Map) {
            final request = cfg['request'];
            if (request is Map) {
              final method = (request['method'] ?? 'GET').toString();
              final fetched = await _apiFetch(
                Map<String, dynamic>.from(request),
                method: method,
                vars: {'@source': first['url'] ?? '', '@keyword': keyword},
              );
              if (fetched != null) {
                chapter['curl'] = fetched.curl;
                final fmt = (cfg['format'] ?? 'nested').toString();
                final epsList = <Map<String, dynamic>>[];
                if (fmt == 'delimited') {
                  final roadNames = (cfg['roadNamesPath'] ?? '').toString();
                  final roadEps = (cfg['roadEpisodesPath'] ?? '').toString();
                  final epSep = (cfg['episodeSeparator'] ?? '#').toString();
                  if (roadNames.isNotEmpty || roadEps.isNotEmpty) {
                    final names = roadNames.isEmpty ? <Object?>[] : RestrictedJsonPath.read(fetched.json, roadNames);
                    final epsAll = roadEps.isEmpty ? <Object?>[] : RestrictedJsonPath.read(fetched.json, roadEps);
                    for (var i = 0; i < names.length; i++) {
                      final raw = epsAll.length > i && epsAll[i] is String ? epsAll[i].toString() : '';
                      epsList.add({'road': names[i].toString(), 'episodes': raw.split(epSep).length});
                    }
                  }
                  if (epsList.isEmpty) warnings.add('API chapterApiConfig（delimited）未解析到线路');
                  chapter['roads'] = epsList.length;
                  chapter['episodes'] = epsList;
                } else {
                  final roads = (cfg['roadsPath'] ?? '').toString();
                  final epsPath = (cfg['episodesPath'] ?? '').toString();
                  final rnPath = (cfg['roadNamePath'] ?? '').toString();
                  final roadNodes = roads.isEmpty ? <Object?>[] : RestrictedJsonPath.read(fetched.json, roads);
                  if (roadNodes.isEmpty) {
                    warnings.add('API chapterApiConfig.roadsPath 未匹配到任何线路（请检查 JSONPath）');
                  }
                  for (var i = 0; i < roadNodes.length; i++) {
                    final road = roadNodes[i];
                    final cnt = (road is Map && epsPath.isNotEmpty)
                        ? RestrictedJsonPath.read(road, epsPath).length
                        : 0;
                    final roadName = (rnPath.isEmpty || road is! Map)
                        ? 'road${i + 1}'
                        : (RestrictedJsonPath.readFirst(road, rnPath)?.toString() ?? 'road${i + 1}');
                    epsList.add({'road': roadName, 'episodes': cnt});
                  }
                  chapter['roads'] = roadNodes.length;
                  chapter['episodes'] = epsList;
                }
              }
            }
          }
        } else {
          final resp = await http.get(Uri.parse(first['url'] ?? ''), headers: ua)
              .timeout(const Duration(seconds: 20));
          final doc = html_parser.parse(resp.body);
          final roads = _xpathNodes(doc, r['chapterRoads']?.toString());
          if (roads.isEmpty) {
            warnings.add('chapterRoads 未匹配到任何节点，请检查 XPath（或为单一 road，可直接用 chapterResult 统计集数）');
          }
          final epsList = <Map<String, dynamic>>[];
          for (var i = 0; i < roads.length; i++) {
            final eps = _xpathNodes(roads[i], r['chapterResult']?.toString());
            epsList.add({'road': 'road${i + 1}', 'episodes': eps.length});
          }
          chapter['roads'] = roads.length;
          chapter['episodes'] = epsList;
        }
      } catch (e) {
        warnings.add('详情/选集阶段失败: $e');
      }
    }

    // 3. iframe / video 播放页嗅探（基础版）
    final detailUrl = chapter['detailUrl'] as String;
    if (items.isNotEmpty && detailUrl.isNotEmpty) {
      try {
        final resp = await http.get(Uri.parse(detailUrl), headers: ua)
            .timeout(const Duration(seconds: 20));
        final doc = html_parser.parse(resp.body);
        final srcs = <String>[];
        for (final f in _xpathNodes(doc, '//iframe')) {
          final s = _attr(f, 'src');
          if (s.isNotEmpty) srcs.add(s);
        }
        for (final v in _xpathNodes(doc, '//video')) {
          final s = _attr(v, 'src');
          if (s.isNotEmpty) srcs.add(s);
        }
        if (srcs.isNotEmpty) chapter['iframe_src'] = srcs.take(3).toList();
      } catch (e) {
        warnings.add('iframe 嗅探失败: $e');
      }
    }

    return {
      'ok': items.isNotEmpty,
      'name': r['name'],
      'version': r['version'],
      'searchMode': searchMode,
      'chapterMode': chapterMode,
      'search': {
        'url': searchUrl,
        'curl': searchCurl,
        'count': items.length,
        'items': items.take(5).toList(),
      },
      'chapter': chapter,
      'warnings': warnings,
    };
  }
}
