import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:xpath_selector_html_parser/xpath_selector_html_parser.dart';
import 'package:yhdm/services/plugin/api_rule_strategy.dart';
import 'package:yhdm/services/logging/logger.dart';

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
你是樱花动漫（完全兼容 Kazumi）番剧规则编写专家。

🔧 工具使用规范（重要）：
- 有很多的工具可用，用来调用，仅在要使用的时候进行调用，一定要看它的介绍。
- 例如：抓站测试用 test_rule，扫描/搜索图标用 scan_rule_icons / fetch_site_icon，批量巡检用 batch_test，规则对比用 diff_rules，找同类模板用 suggest_rules，失败自动修复用 fix_rule。

✅ 第一步（永远先做，写任何规则之前）：先阅读，再动手。
- 必须先实际访问目标网站，阅读它的搜索页/详情页/播放页真实结构（服务端 HTML 还是 JSON 接口、有没有登录或人机验证），再决定怎么写。
- 必须先把上方参考文档（qlyyz.xyz/docs 与规则仓库 https://github.com/qldwj/Kazuminb6Rules）读完，一切以本站文档和规范为准。
- 禁止凭记忆、凭模板、凭猜测写 XPath/JSONPath；永远先看网站长什么样、先读文档。
- 【强制必执行】生成任何规则前，必须判断目标站：① 是否需要登录才能搜索/观看？② 有没有人机验证？两者至少先实测确认一种，禁止跳过。
   · 需要登录 → 必须先读《需要登录后才能观看》https://qlyyz.xyz/docs/rules/login-required.html，完整实现 needLogin=true + loginURL（该站登录页地址），并在规则说明中提示用户需在 App 内登录该站。遗漏 needLogin/loginURL 视为不合格规则。
   · 有人机验证 → 必须先读《人机验证应对》https://qlyyz.xyz/docs/rules/human-verification.html，按其分档（图片验证码/点击滑块/CF·Akamai）完整实现 antiCrawlerConfig 全套字段（enabled 等），不能只给数字。遗漏或给占位视为不合格规则。
   · 这两个文档是必读必执行，不只是参考资料；命中却不实现对应字段，禁止交付。

⚠️ 权威优先级（最重要）：
- 一切以【樱花动漫】为主：最终生成的规则必须适配樱花动漫应用（导入链接前缀 yhdmgz://）。
- Kazumi 官方文档与本站(qlyyz.xyz/docs)文档均仅作参考，本站亦非官方权威。
- 规则格式完全兼容 Kazumi：字段结构、占位符（@keyword / @source / @roadIndex 等）、XPath 与 API 模式均与 Kazumi 一致。

📖 参考文档（必读，优先于任何记忆）：
- 官网：https://qlyyz.xyz/
- 下载页：https://qlyyz.xyz/downloads.html
- GitHub：https://github.com/qldwj/Kazumikfc
- XPath 规则开发：https://qlyyz.xyz/docs/rules/develop-rules.html
- 规则介绍（总览）：https://qlyyz.xyz/docs/rules/introduce-rules.html
- XPath 规则示例：https://qlyyz.xyz/docs/rules/develop-rules-example.html
- 社区教程：https://www.kshare.top
- API 规则开发：https://qlyyz.xyz/docs/rules/develop-api-rules.html
- 需要登录后才能观看（例：次元城 ciyuancheng，不只限它）：https://qlyyz.xyz/docs/rules/login-required.html
- 人机验证应对（图片验证码 / 点击滑块 / CF·Akamai 智能风控）：https://qlyyz.xyz/docs/rules/human-verification.html
- 规则仓库（兼容 Kazumi 格式）：https://github.com/qldwj/Kazuminb6Rules
- 视频嗅探原理：https://qlyyz.xyz/docs/architecture/video-parser.html
- 技术博客：https://www.cnblogs.com/1288blog/p/19506033

💡 MCP 服务已部署完成，请尽快按本规范生成规则。生成的规则必须以樱花动漫模板为准（导入前缀 yhdmgz://），并完全兼容 Kazumi 格式。

⚠️ 关键提醒（我踩过的坑，务必避免）：
1. 规则字段是【扁平结构】，不是嵌套结构。禁止使用 search.mode / search.url / detail.titlePath 这类字段名。
2. 搜索占位符是 @keyword，不是 {keyword}。相关占位符还有 @source / @roadIndex / @episodeIndex（从0开始）/ @roadNumber / @episodeNumber（从1开始）。
3. searchList / searchName / searchResult / chapterRoads / chapterResult 一律用【绝对路径】，以 // 开头。
4. contains() 在官方规则里可以用（dalvdm、MXdm 都在用），不要禁止。
5. type 字段是站点类型（"anime"），不是 "xpath"。
6. api 是版本兼容级别（字符串），取值 "1"~"8"，对应不同 Kazumi 版本。
7. searchURL 末尾常有 &submit=（maccms 站点常见）。
8. 规则存放在我的规则仓库【根目录】（https://github.com/qldwj/Kazuminb6Rules，兼容 Kazumi 格式），不在 rules/ 子目录下。

🔍 搜索方式适配（最重要，务必因站实测，严禁套模板）：
- 每个站点的搜索方式都不一样，100 个站有 100 种搜索写法。动手前先用 curl/浏览器实测目标站的【真实搜索】，看清返回的是"服务端 HTML"还是"JSON 接口"，再决定实现方式，不要凭模板照抄。
- 三种搜索实现，任选其一（用哪种以实测为准）：
  A. XPath 搜索（默认）：searchURL 填搜索页 URL（关键词用 @keyword 替换），searchList / searchName / searchResult 用 XPath 从返回 HTML 提取。适用于服务端渲染完整结果的站。
  B. API 搜索：若搜索是 JSON 接口（浏览器 Network 里能看到 /api/search、/search/do.php 之类返回 JSON），用 searchApiConfig 配 method / url / params / headers，searchList 用受限 JSONPath 提取，api 设为 "8"。
  C. POST 表单搜索：若搜索是 <form method="post"> 提交，设 usePost=true，searchURL 填带查询参数的地址，Kazumi 会自动剥离参数按 Form 提交。
- searchURL 常见形态仅为示例（严禁照抄，必须以实测为准）：
  /search/-------------.html?wd=@keyword、/search/?wd=@keyword、/?key=@keyword、/so/-------------.html?wd=@keyword、/api/search?word=@keyword 等，取决于站点框架。
- 搜索结果 XPath 因站差异巨大：列表可能是 ul>li、div.grid、table tr、a.video、.search_list 等。searchList 必须定位到"每一条结果"的重复节点，再相对其取 searchName（标题）与 searchResult（详情链接）。
- 若搜索有分页/懒加载，优先用站点自带的关键词搜索接口（通常稳定返回 JSON 或整页结果），不要依赖抓首页。
- 人机验证应对与登录后观看（最重要：动手前必须先读这两份文档，按其完整规范处理，严禁只看本摘要就写）：
  · 《需要登录后才能观看》：https://qlyyz.xyz/docs/rules/login-required.html → 针对需要登录才能搜索/观看的站点（例：次元城 ciyuancheng，不只限它）。生成规则时必须配 needLogin=true + loginURL（该站的登录页地址），并在规则说明里提示用户需先在 App 内登录该站。不要遗漏 needLogin/loginURL 字段，否则用户导入后无法播放。
  · 《人机验证应对》：https://qlyyz.xyz/docs/rules/human-verification.html → 针对站点有人机验证的情况。先实测判断站点到底是哪种验证，再按文档选对应档位：
    - 正常【图片验证码】（搜索/详情/播放页返回图片验证码）→ antiCrawlerConfig=1（即 antiCrawlerConfig 对象内 captchaType=1），配 captchaImage/captchaInput/captchaButton 等图片验证识别字段。
    - 【非正常验证】需要点击/滑块/行为验证 → antiCrawlerConfig=2（即 captchaType=2），走自动点击处理，配 captchaButton（放行按钮）与 captchaDetectType/captchaDetectValue 检测字段。
    - 【超级特殊验证】Cloudflare CF、Akamai 等智能风控 → antiCrawlerConfig=3（即 captchaType=3），走自定义 JS 脚本（captchaScript），必要时配合 useWebview=true 用真实浏览器内核过验证。
    - 无论哪种，都要把 antiCrawlerConfig 对象完整给出（enabled 等字段），不能只给数字。实在无法自动处理时，在规则说明中标注需要用户手动配合。

✅ 规则模板（以此为基准，字段名和结构照抄；searchURL/XPath 仅是示例，务必替换为目标站实测值）：
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
  "baseURL": "https://example.com/",
  "searchURL": "https://example.com/s----------.html?wd=@keyword",
  "searchList": "//div/div[3]/ul/li",
  "searchName": "//div/a[2]",
  "searchResult": "//div/a[2]",
  "chapterRoads": "//div/div[4]/div/ul",
  "chapterResult": "//li/a",
  "referer": "",
  "loginURL": "",
  "icon": "https://example.com/favicon.ico",
  "searchMode": "xpath",
  "chapterMode": "xpath",
  "antiCrawlerConfig": {
    "enabled": false,
    "captchaType": 1,
    "captchaImage": "",
    "captchaInput": "",
    "captchaButton": "",
    "captchaDetectType": 1,
    "captchaDetectValue": "",
    "captchaScript": ""
  },
  "enabled": true,
  "needLogin": false
}

📋 最终输出（三项缺一不可，按下面顺序返回）：
1. 【协议导入链接】yhdmgz://<Base64>：把完整规则 JSON 直接 Base64 编码，最前面加 yhdmgz:// 前缀（压缩成 Base64，便于复制/导入）。
2. 【分享链接】https://qlyyz.xyz/share?gz=<Base64>：用同一个 Base64，做成站内分享链接格式（相当于规则分享中间商，点开即可分享），严禁省略。
3. 【未编码前的原始规则】完整 JSON 明文（未做任何 Base64 编码，可读、可核对）。
- 写之前先实际访问目标网站，分析搜索页/详情页/播放页的真实 DOM/JSON 再写，不凭猜测。
- 规则必须带 icon（网站 logo 图片链接）：从目标站 favicon（如 https://域名/favicon.ico）或首页 logo 图提取，严禁留空——否则 App 规则列表不显示图标。
- 若道路与分集在 DOM 中不嵌套，用单一 road 处理。

✅ 客户端测试闭环（交付前必须）：
- 生成规则后，用应用内置的 test_rule 工具真实抓站验证：
  1. 搜索结果数 > 0；
  2. chapterRoads 匹配线路数 > 0；
  3. 每条线路 chapterResult 都有集数；
  4. 实际播放页能嗅探到播放地址。
- 全部通过才能交付给用户；不通过则回查对应 XPath / JSONPath 修正。

🌐 开源共享（最终一步，必须）：
- 规则验证通过、即将交付给用户时，主动询问用户是否需要把规则上传到 qlyyz.xyz/json 公开仓库（开源精神，让更多人使用）。
- 若用户同意，调用 upload_rule 工具上传规则 JSON（multipart 上传到 qlyyz.xyz 文件仓库 p=v0 目录），上传成功后把公开访问地址（https://qlyyz.xyz/json/<规则名>.json）一起给用户。
- 若用户拒绝或不确定，直接交付，不强求。

📌 API 选集分隔符格式（maccms 常见，非嵌套 JSON）：
- 使用 chapterApiConfig.format = "delimited"；
- roadNamesPath 取线路名列表、roadEpisodesPath 取线路分集字符串列表；
- 配 roadSeparator（默认 \$\$\$）、episodeSeparator（默认 #）、fieldSeparator（默认 \$）。
''';

  Future<void> start({int? port}) async {
    if (_running) return;
    if (port != null) _port = port;
    final addr = InternetAddress.anyIPv4;
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
            {'name': 'test_rule', 'description': '真实抓站验证XPath规则是否可用：实际请求搜索页与详情页，统计搜索结果数、线路数、各线路集数。输入规则与测试关键词。', 'inputSchema': {'type': 'object', 'properties': {'rule': {'type': 'string', 'description': '规则JSON / Base64 / yhdmgz://链接'}, 'keyword': {'type': 'string', 'description': '测试关键词，如 仙逆'}}, 'required': ['rule', 'keyword']}},
            {'name': 'upload_rule', 'description': '将规则JSON上传到 qlyyz.xyz/json 公开仓库共享（开源精神）。输入规则JSON或yhdmgz://链接，上传到 p=v0 目录。', 'inputSchema': {'type': 'object', 'properties': {'rule': {'type': 'string', 'description': '规则JSON（对象）或 yhdmgz:// 链接'}, 'filename': {'type': 'string', 'description': '上传文件名（不含.json），默认取规则 name 字段'}}, 'required': ['rule']}},
            {'name': 'scan_rule_icons', 'description': '扫描规则内所有图片资源：提取 icon 字段，并全字段搜索所有带经典图片后缀(.png/.jpg/.jpeg/.ico/.gif/.webp/.avif/.svg)的图片URL（直接解析规则源码，无需访问网站）。无 icon 时给出推荐图标(baseURL/favicon.ico 或文件内第一张图)。', 'inputSchema': {'type': 'object', 'properties': {'rule': {'type': 'string', 'description': '规则JSON / Base64 / yhdmgz://链接'}}, 'required': ['rule']}},
            {'name': 'fetch_site_icon', 'description': '网站图标搜索：输入规则或网站URL，自动请求站点探测真实可用的图标——尝试 /favicon.ico、解析首页 <link rel="icon"> / shortcut icon / apple-touch-icon，返回可用图标URL列表(验证HTTP 200+图片类型)。用于给无图标规则补图。', 'inputSchema': {'type': 'object', 'properties': {'rule': {'type': 'string', 'description': '规则JSON / yhdmgz://链接 / 网站URL(如 https://www.agedm.io/)'}}, 'required': ['rule']}},
            {'name': 'batch_test', 'description': '批量巡检规则：输入多条规则(JSON数组 或 每行一条 yhdmgz://链接/JSON)与测试关键词，逐条真实抓站测试，输出每条的状态报告(✅搜索有结果 / ⚠️风控失败 / ❌死链)。', 'inputSchema': {'type': 'object', 'properties': {'rules': {'type': 'string', 'description': 'JSON数组 或 每行一条(规则JSON/yhdmgz://链接)'}, 'keyword': {'type': 'string', 'description': '测试关键词，如 仙逆'}}, 'required': ['rules', 'keyword']}},
            {'name': 'diff_rules', 'description': '规则对比：输入两条规则(JSON/yhdmgz://链接)，逐字段对比，输出新增/删除/修改字段清单(含值变化)，用于升级前核对版本、baseURL、选择器改动。', 'inputSchema': {'type': 'object', 'properties': {'ruleA': {'type': 'string', 'description': '规则A'}, 'ruleB': {'type': 'string', 'description': '规则B(新版本)'}}, 'required': ['ruleA', 'ruleB']}},
            {'name': 'suggest_rules', 'description': '同类模板推荐：输入新网站URL/域名，拉取规则仓库 index.json，按 baseURL 域名相似度匹配仓库内已有规则作为编写模板参考，并返回仓库规则清单(名称/baseURL/图标)。', 'inputSchema': {'type': 'object', 'properties': {'url': {'type': 'string', 'description': '新网站URL或域名'}}, 'required': ['url']}},
            {'name': 'fix_rule', 'description': '规则自动修复：输入规则与测试关键词，先跑 test_rule 复现失败，再抓取搜索页真实DOM结构(前若干链接的href+文本)作为证据输出，指导修正 XPath/API 配置。返回:失败信息+页面真实结构+修复建议。', 'inputSchema': {'type': 'object', 'properties': {'rule': {'type': 'string', 'description': '规则JSON / Base64 / yhdmgz://链接'}, 'keyword': {'type': 'string', 'description': '测试关键词'}}, 'required': ['rule', 'keyword']}},
            {'name': 'captcha_guide', 'description': '验证码/登录应对指引：按类型输出 antiCrawlerConfig 完整模板。kind 取值 image(正常图片验证码,走图片识别)/click(非正常点击/滑块类)/cf(超级特殊,如Cloudflare等)/purple或login(紫色模板=登录后观看,needLogin+loginURL 全套)；不传则返回全部档位。', 'inputSchema': {'type': 'object', 'properties': {'kind': {'type': 'string', 'description': 'image / click / cf / purple(登录后观看) / 不传返回全部'}}, 'required': []}},
            {'name': 'fetch_page', 'description': '网页结构抓取：输入任意URL，抓取页面并提取标题、前若干链接(href+文本)、表单(action/method/inputs)、iframe、meta描述，供分析站点结构/编写规则前勘察使用。', 'inputSchema': {'type': 'object', 'properties': {'url': {'type': 'string', 'description': '完整URL(含 http/https)'}}, 'required': ['url']}},
            {'name': 'test_with_cookie', 'description': '带Cookie实测规则：用户从站点/浏览器/App复制已登录的Cookie粘贴进来，带上Cookie跑真实搜索+选集测试，验证登录后规则到底能不能用。用于需要登录(紫色线路)或带Cookie才可访问的站点。', 'inputSchema': {'type': 'object', 'properties': {'rule': {'type': 'string', 'description': '规则JSON / Base64 / yhdmgz://链接'}, 'keyword': {'type': 'string', 'description': '测试关键词'}, 'cookie': {'type': 'string', 'description': '已登录Cookie(用户从浏览器/站点复制)'}}, 'required': ['rule', 'keyword', 'cookie']}},
            {'name': 'cookie_helper', 'description': 'Cookie/凭据指引：站点需要登录(Cookie)时规则怎么写。说明 App 端登录态机制(WebView共享Cookie)、userAgent/Referer 字段、Cookie 过期处理，以及何时用 test_with_cookie 实测。', 'inputSchema': {'type': 'object', 'properties': {}, 'required': []}}
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
          } else if (name == 'upload_rule') {
            final rule = (args['rule'] ?? '').toString();
            final filename = (args['filename'] ?? '').toString();
            _uploadRule(rule, filename).then((result) {
              _ok(req, {'jsonrpc': '2.0', 'id': id, 'result': {'content': [{'type': 'text', 'text': jsonEncode(result)}]}});
            });
          } else if (name == 'scan_rule_icons') {
            final result = _scanRuleIcons((args['rule'] ?? '').toString());
            _ok(req, {'jsonrpc': '2.0', 'id': id, 'result': {'content': [{'type': 'text', 'text': jsonEncode(result)}]}});
          } else if (name == 'fetch_site_icon') {
            _fetchSiteIcon((args['rule'] ?? '').toString()).then((result) {
              _ok(req, {'jsonrpc': '2.0', 'id': id, 'result': {'content': [{'type': 'text', 'text': jsonEncode(result)}]}});
            });
          } else if (name == 'batch_test') {
            _batchTest((args['rules'] ?? '').toString(), (args['keyword'] ?? '').toString()).then((result) {
              _ok(req, {'jsonrpc': '2.0', 'id': id, 'result': {'content': [{'type': 'text', 'text': jsonEncode(result)}]}});
            });
          } else if (name == 'diff_rules') {
            final result = _diffRules((args['ruleA'] ?? '').toString(), (args['ruleB'] ?? '').toString());
            _ok(req, {'jsonrpc': '2.0', 'id': id, 'result': {'content': [{'type': 'text', 'text': jsonEncode(result)}]}});
          } else if (name == 'suggest_rules') {
            _suggestRules((args['url'] ?? '').toString()).then((result) {
              _ok(req, {'jsonrpc': '2.0', 'id': id, 'result': {'content': [{'type': 'text', 'text': jsonEncode(result)}]}});
            });
          } else if (name == 'fix_rule') {
            _fixRule((args['rule'] ?? '').toString(), (args['keyword'] ?? '').toString()).then((result) {
              _ok(req, {'jsonrpc': '2.0', 'id': id, 'result': {'content': [{'type': 'text', 'text': jsonEncode(result)}]}});
            });
          } else if (name == 'captcha_guide') {
            final result = _captchaGuide((args['kind'] ?? '').toString());
            _ok(req, {'jsonrpc': '2.0', 'id': id, 'result': {'content': [{'type': 'text', 'text': jsonEncode(result)}]}});
          } else if (name == 'fetch_page') {
            _fetchPage((args['url'] ?? '').toString()).then((result) {
              _ok(req, {'jsonrpc': '2.0', 'id': id, 'result': {'content': [{'type': 'text', 'text': jsonEncode(result)}]}});
            });
          } else if (name == 'test_with_cookie') {
            _testRule((args['rule'] ?? '').toString(), (args['keyword'] ?? '').toString(),
                cookie: (args['cookie'] ?? '').toString()).then((result) {
              _ok(req, {'jsonrpc': '2.0', 'id': id, 'result': {'content': [{'type': 'text', 'text': jsonEncode(result)}]}});
            });
          } else if (name == 'cookie_helper') {
            final result = _cookieHelper();
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
      // 本 App 扩展字段（登录/镜像等）
      'needLogin', 'loginURL', 'mirror', 'remark',
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
      final bodyType = (request['bodyType'] ?? '').toString().toLowerCase();
      if (rawBody is Map) {
        final replaced = _replaceVarsMap(rawBody, vars);
        curlBody = replaced;
        final isForm = bodyType == 'form' ||
            (headers['Content-Type']?.contains('x-www-form-urlencoded') ?? false);
        if (isForm) {
          headers['Content-Type'] = 'application/x-www-form-urlencoded';
          resp = await http.post(uri, headers: headers,
              body: Uri(queryParameters: replaced).query)
              .timeout(const Duration(seconds: 20));
        } else {
          headers['Content-Type'] = 'application/json';
          resp = await http.post(uri, headers: headers, body: jsonEncode(replaced))
              .timeout(const Duration(seconds: 20));
        }
      } else if (rawBody is String) {
        final replaced = _replaceVars(rawBody, vars);
        curlBody = replaced;
        resp = await http.post(uri, headers: headers, body: replaced)
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

  Future<Map<String, dynamic>> _testRule(String raw, String keyword,
      {String cookie = ''}) async {
    final r = _decodeRule(raw);
    if (r == null) {
      return {'ok': false, 'errors': ['无法解析规则：需为规则JSON、Base64 或 yhdmgz:// 链接']};
    }
    final searchMode = (r['searchMode'] ?? 'xpath').toString();
    final chapterMode = (r['chapterMode'] ?? 'xpath').toString();
    final warnings = <String>[];
    final base = (r['baseURL'] ?? '').toString().trim().replaceAll(RegExp(r'/$'), '');
    final ua = <String, String>{'User-Agent': 'Mozilla/5.0 (Kazumi-MCP)'};
    if (cookie.isNotEmpty) ua['Cookie'] = cookie;

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
        searchUrl = searchUrlTpl.contains('@keyword')
            ? searchUrlTpl.replaceAll('@keyword', Uri.encodeQueryComponent(keyword))
            : searchUrlTpl +
                (searchUrlTpl.contains('?') ? '&' : '?') +
                'wd=' +
                Uri.encodeQueryComponent(keyword);
        searchUrl = searchUrl.replaceFirst(RegExp(r'^\.?/'), '');
        final finalSearchUrl = searchUrl.startsWith('http') ? searchUrl : base + searchUrl;
        searchUrl = finalSearchUrl;
        final usePost = r['usePost'] == true;
        http.Response resp;
        if (usePost) {
          // POST 表单搜索：剥离 query 参数，按 Form 提交到 path（兼容 maccms 等 POST 搜索站）
          final uri = Uri.parse(finalSearchUrl);
          final form = <String, String>{};
          uri.queryParameters.forEach((k, v) => form[k] = v);
          final postUri = uri.replace(queryParameters: {});
          final postHeaders = <String, String>{
            ...ua,
            'Content-Type': 'application/x-www-form-urlencoded'
          };
          resp = await http.post(postUri, headers: postHeaders,
              body: Uri(queryParameters: form).query)
              .timeout(const Duration(seconds: 20));
          searchCurl = _sanitizeCurl('POST', postUri.toString(), postHeaders, form);
        } else {
          resp = await http.get(Uri.parse(finalSearchUrl), headers: ua)
              .timeout(const Duration(seconds: 20));
          searchCurl = _sanitizeCurl('GET', finalSearchUrl, ua, null);
        }
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
          final detailUsePost = r['usePost'] == true;
          final detailRaw = first['url'] ?? '';
          http.Response resp;
          if (detailUsePost) {
            // POST 表单选集：剥离 query 参数，按 Form 提交到 path
            final uri = Uri.parse(detailRaw);
            final form = <String, String>{};
            uri.queryParameters.forEach((k, v) => form[k] = v);
            final postUri = uri.replace(queryParameters: {});
            final postHeaders = <String, String>{
              ...ua,
              'Content-Type': 'application/x-www-form-urlencoded'
            };
            resp = await http.post(postUri, headers: postHeaders,
                body: Uri(queryParameters: form).query)
                .timeout(const Duration(seconds: 20));
          } else {
            resp = await http.get(Uri.parse(detailRaw), headers: ua)
                .timeout(const Duration(seconds: 20));
          }
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

  /// 上传规则到 qlyyz.xyz/json 公开仓库（开源共享）。
  /// 接口：POST /json/api.php，FormData: act=upload + jsonfile=<规则JSON文件>
  Future<Map<String, dynamic>> _uploadRule(String raw, String filename) async {
    try {
      String jsonStr = raw.trim();
      if (jsonStr.startsWith('yhdmgz://')) {
        jsonStr = utf8.decode(base64.decode(base64.normalize(jsonStr.substring(9))));
      }
      final decoded = jsonDecode(jsonStr);
      if (decoded is! Map) {
        return {'ok': false, 'errors': ['规则必须是 JSON 对象']};
      }
      var name = filename.trim().isNotEmpty
          ? filename.trim()
          : (decoded['name'] ?? 'rule').toString();
      name = name.replaceAll(RegExp(r'[^\w\u4e00-\u9fa5-]'), '');
      if (name.isEmpty) name = 'rule';
      final uri = Uri.parse('https://qlyyz.xyz/json/api.php');
      final req = http.MultipartRequest('POST', uri)
        ..fields['act'] = 'upload'
        ..files.add(http.MultipartFile.fromString(
          'jsonfile',
          jsonEncode(decoded),
          filename: '$name.json',
        ));
      final streamed = await req.send().timeout(const Duration(seconds: 30));
      final body = await streamed.stream.bytesToString();
      Map<String, dynamic> parsed = {'raw': body};
      try {
        parsed = jsonDecode(body) as Map<String, dynamic>;
      } catch (_) {}
      final ok = streamed.statusCode == 200 && (parsed['code'] ?? 0) != 0;
      return {
        'ok': ok,
        'statusCode': streamed.statusCode,
        'response': parsed,
        'publicUrl': 'https://qlyyz.xyz/json/',
        'message': ok
            ? '上传成功，规则已公开到 https://qlyyz.xyz/json/'
            : '上传失败：$body',
      };
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
  }

  /// 扫描规则内所有图片资源（直接解析规则源码，无需访问网站）。
  /// - 提取 icon 字段（若有）
  /// - 全字段正则搜索所有带经典图片后缀的 URL（png/jpg/jpeg/ico/gif/webp/avif/svg）
  /// - 无 icon 时给出推荐：文件内第一张图，或 baseURL/favicon.ico 后备
  Map<String, dynamic> _scanRuleIcons(String raw) {
    Map<String, dynamic> rule;
    var source = raw.trim();
    try {
      if (source.startsWith('yhdmgz://')) {
        source = utf8.decode(base64Decode(base64.normalize(source.substring(9))));
      } else if (source.startsWith('kazumi://')) {
        source = utf8.decode(base64Decode(base64.normalize(source.substring(9))));
      } else if (!source.startsWith('{')) {
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

    // 经典图片后缀：直接扫描源码字符串
    // （注意：raw 字符串内 \' 是非法转义，故用普通字符串双重转义）
    final imgRe = RegExp(
        'https?://[^\\s"\'\\\\]+?\\.(?:png|jpe?g|ico|gif|webp|avif|svg)(?:\\?[^\\s"\'\\\\]*)?',
        caseSensitive: false);
    final allImages = <String>[];
    final seen = <String>{};
    void walk(dynamic v) {
      if (v is String) {
        for (final m in imgRe.allMatches(v)) {
          final u = m.group(0)!;
          if (seen.add(u)) allImages.add(u);
        }
      } else if (v is Map) {
        v.forEach((_, val) => walk(val));
      } else if (v is List) {
        for (final val in v) {
          walk(val);
        }
      }
    }
    walk(rule);

    final icon = (rule['icon'] ?? '').toString().trim();
    final base = (rule['baseURL'] ?? '').toString().trim();
    String? suggestion;
    if (icon.isEmpty) {
      final baseTrim = base.replaceAll(RegExp(r'/+$'), '');
      suggestion = allImages.isNotEmpty
          ? allImages.first
          : (baseTrim.isNotEmpty ? '$baseTrim/favicon.ico' : null);
    }
    return {
      'ok': true,
      'name': rule['name'],
      'hasIcon': icon.isNotEmpty,
      'icon': icon.isEmpty ? null : icon,
      'imageCount': allImages.length,
      'allImages': allImages,
      'suggestion': suggestion,
      'note': suggestion == null
          ? '规则无 baseURL，无法给出推荐图标'
          : (icon.isEmpty
              ? (allImages.isNotEmpty
                  ? '文件内第 1 张图可用作 icon；仍建议以站点实际 logo 为准'
                  : '推荐值 baseURL/favicon.ico 为站点常见默认图标，若站点有独立 logo 以实际路径为准')
              : '规则已有 icon，无需修改'),
    };
  }

  /// 网站图标搜索：探测站点真实可用图标。
  /// 先试常见路径(favicon.ico/png/apple-touch-icon)，再解析首页 <link rel="icon">。
  Future<Map<String, dynamic>> _fetchSiteIcon(String raw) async {
    var base = raw.trim();
    final rule = _decodeRule(raw);
    if (rule != null) {
      base = (rule['baseURL'] ?? '').toString();
    }
    if (base.isEmpty) {
      if (!base.startsWith('http')) base = 'https://$base';
    }
    if (!base.startsWith('http')) {
      return {'ok': false, 'errors': ['无法解析出网站地址：请输入网站URL或含 baseURL 的规则']};
    }
    final baseTrim = base.replaceAll(RegExp(r'/$'), '');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    final icons = <String>[];
    // 1) 常见路径探测
    for (final c in ['$baseTrim/favicon.ico', '$baseTrim/favicon.png', '$baseTrim/apple-touch-icon.png']) {
      try {
        final req = await client.getUrl(Uri.parse(c));
        req.headers.set('User-Agent', 'Mozilla/5.0 (Kazumi-MCP)');
        final resp = await req.close().timeout(const Duration(seconds: 5));
        final ct = resp.headers.contentType?.mimeType ?? '';
        await resp.drain();
        if (resp.statusCode == 200 && ct.startsWith('image')) {
          icons.add(c);
          break;
        }
      } catch (_) {}
    }
    // 2) 首页 <link rel="icon"> 解析
    if (icons.isEmpty) {
      try {
        final req = await client.getUrl(Uri.parse(baseTrim));
        req.headers.set('User-Agent', 'Mozilla/5.0 (Kazumi-MCP)');
        final resp = await req.close().timeout(const Duration(seconds: 8));
        final body = await resp.transform(utf8.decoder).join();
        client.close();
        if (resp.statusCode == 200) {
          final doc = html_parser.parse(body);
          final nodes = doc.querySelectorAll('link[rel]');
          for (final l in nodes) {
            final rel = (l.attributes['rel'] ?? '').toLowerCase();
            final href = (l.attributes['href'] ?? '').trim();
            if (rel.contains('icon') && href.isNotEmpty) {
              final abs = href.startsWith('http')
                  ? href
                  : '$baseTrim/${href.replaceFirst(RegExp(r'^/'), '')}';
              icons.add(abs);
            }
          }
        }
      } catch (_) {}
    }
    final uniq = <String>[];
    for (final i in icons) {
      if (!uniq.contains(i)) uniq.add(i);
    }
    return {
      'ok': uniq.isNotEmpty,
      'site': baseTrim,
      'icons': uniq,
      'suggestion': uniq.isEmpty ? null : uniq.first,
      'note': uniq.isEmpty
          ? '未探测到可用图标：站点可能拦截请求或路径特殊，建议人工打开首页查看源码'
          : (uniq.length > 1 ? '推荐第 1 个，其余可人工选择' : ''),
    };
  }

  /// 批量巡检：逐条 test_rule 聚合报告。
  Future<Map<String, dynamic>> _batchTest(String rawRules, String keyword) async {
    List<Object?> list;
    final trimmed = rawRules.trim();
    try {
      if (trimmed.startsWith('[')) {
        list = jsonDecode(trimmed) as List;
      } else {
        list = trimmed
            .split('\n')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
      }
    } catch (e) {
      return {'ok': false, 'errors': ['rules 需为 JSON 数组或每行一条(JSON/yhdmgz://链接)']};
    }
    if (list.isEmpty) return {'ok': false, 'errors': ['rules 为空']};
    if (keyword.trim().length < 2) {
      return {'ok': false, 'errors': ['关键词至少 2 个字符']};
    }
    final results = <Map<String, dynamic>>[];
    var passed = 0;
    for (final r in list) {
      final raw = r is String ? r : jsonEncode(r);
      final rule = _decodeRule(raw);
      final name = rule?['name']?.toString() ?? 'unknown';
      final t = await _testRule(raw, keyword);
      final ok = t['ok'] == true;
      if (ok) passed++;
      final err = t['errors'];
      results.add({
        'name': name,
        'ok': ok,
        'status': ok ? '✅ 搜索有结果' : '❌ 失败',
        'detail': err is List ? err.join('; ') : (t['error']?.toString() ?? ''),
      });
    }
    return {
      'ok': results.isNotEmpty,
      'total': results.length,
      'passed': passed,
      'failed': results.length - passed,
      'results': results,
      'note': '失败原因多为：站点风控(403/418)、关键词无结果、或 XPath/API 配置与实际结构不符',
    };
  }

  /// 规则对比：字段级 diff。
  Map<String, dynamic> _diffRules(String rawA, String rawB) {
    final a = _decodeRule(rawA);
    final b = _decodeRule(rawB);
    if (a == null || b == null) {
      return {'ok': false, 'errors': ['规则解析失败：需为规则JSON / Base64 / yhdmgz://链接']};
    }
    final added = <String>[];
    final removed = <String>[];
    final changed = <Map<String, dynamic>>[];
    final keys = {...a.keys, ...b.keys};
    for (final k in keys) {
      final va = a[k];
      final vb = b[k];
      final sa = va is String ? va : jsonEncode(va);
      final sb = vb is String ? vb : jsonEncode(vb);
      if (!a.containsKey(k)) {
        added.add(k);
      } else if (!b.containsKey(k)) {
        removed.add(k);
      } else if (sa != sb) {
        changed.add({
          'field': k,
          'from': sa.length > 200 ? '${sa.substring(0, 200)}…' : sa,
          'to': sb.length > 200 ? '${sb.substring(0, 200)}…' : sb,
        });
      }
    }
    return {
      'ok': true,
      'nameA': a['name'],
      'nameB': b['name'],
      'added': added,
      'removed': removed,
      'changed': changed,
      'changedCount': changed.length,
    };
  }

  /// 同类模板推荐：拉规则仓库 index 返回规则清单（含图标），供 AI 选模板。
  Future<Map<String, dynamic>> _suggestRules(String url) async {
    var host = url.trim();
    if (host.isEmpty) return {'ok': false, 'errors': ['请输入网站URL或域名']};
    if (!host.startsWith('http')) host = 'https://$host';
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    List<dynamic>? idx;
    for (final src in [
      'https://api.atomgit.com/api/v5/repos/qldwi/yhdmgz/raw/index.json',
      'https://raw.githubusercontent.com/qldwj/Kazuminb6Rules/main/index.json',
    ]) {
      try {
        final req = await client.getUrl(Uri.parse(src));
        req.headers.set('User-Agent', 'CycAndroid/5.6.1');
        final resp = await req.close().timeout(const Duration(seconds: 8));
        final body = await resp.transform(utf8.decoder).join();
        final d = jsonDecode(body);
        if (d is List) {
          idx = d;
          break;
        }
      } catch (_) {}
    }
    client.close();
    if (idx == null) return {'ok': false, 'errors': ['规则仓库不可达（镜像与主源均失败）']};
    final allRules = idx.map((e) {
      final m = e as Map;
      return {
        'name': m['name'],
        'icon': m['icon'] ?? '',
      };
    }).toList();
    return {
      'ok': true,
      'target': host,
      'total': idx.length,
      'allRules': allRules,
      'note': '仓库现有规则清单（名称+图标）。若新站点的结构（maccms/API/服务端HTML）与某条相近，可先 validate_rule 该条作模板再改字段；不确定结构时用 test_rule/fix_rule 实测目标站',
    };
  }

  /// 规则自动修复：test 复现失败 + 抓首页真实DOM结构作证据 + 修复建议。
  Future<Map<String, dynamic>> _fixRule(String raw, String keyword) async {
    final t = await _testRule(raw, keyword);
    final rule = _decodeRule(raw);
    final base = (rule?['baseURL'] ?? '').toString().trim().replaceAll(RegExp(r'/$'), '');
    final hints = <Map<String, String>>[];
    if (t['ok'] != true && base.isNotEmpty) {
      try {
        final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
        final req = await client.getUrl(Uri.parse(base));
        req.headers.set('User-Agent', 'Mozilla/5.0 (Kazumi-MCP)');
        final resp = await req.close().timeout(const Duration(seconds: 8));
        final body = await resp.transform(utf8.decoder).join();
        client.close();
        if (resp.statusCode == 200) {
          final doc = html_parser.parse(body);
          final anchors = doc.querySelectorAll('a[href]');
          var n = 0;
          for (final a in anchors) {
            if (n >= 15) break;
            final href = (a.attributes['href'] ?? '').trim();
            final text = (a.text ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
            if (href.isNotEmpty && text.isNotEmpty && text.length < 40) {
              hints.add({
                'href': href.length > 90 ? href.substring(0, 90) : href,
                'text': text.length > 40 ? text.substring(0, 40) : text,
              });
              n++;
            }
          }
        }
      } catch (_) {}
    }
    return {
      'ok': false,
      'testResult': t,
      'domHints': hints,
      'suggestion': hints.isEmpty
          ? '站点页面不可达或结构为空：请人工打开站点确认是否需登录/验证码，或检查 baseURL 是否正确'
          : '以下为站点首页真实链接结构（前若干条）：请据此核对 searchList / searchName / searchResult 的 XPath 层级，修正后重新 validate_rule + test_rule',
    };
  }

  /// 验证码应对指引：输出 antiCrawlerConfig 完整模板（按类型分档）。
  Map<String, dynamic> _captchaGuide(String kind) {
    final k = kind.trim().toLowerCase();
    const baseNote = 'antiCrawlerConfig 仅适用于搜索阶段；命中即必须实现全套字段，不能只给 enabled。'
        '若站点需要登录后才能观看（播放线路呈紫色），还必须同时实现 needLogin=true + loginURL。';

    Map<String, dynamic> image() => {
          'name': '档1-正常图片验证码（captchaType=1，走图片识别）',
          '适用': '搜索/详情页出现图片验证码（输入图中文字/数字），如 whxzyy 的数字算术验证',
          'template': {
            'antiCrawlerConfig': {
              'enabled': true,
              'captchaType': 1,
              'captchaImage': '//img[contains(@id, \'captcha\') or contains(@class, \'captcha\')]',
              'captchaInput': '//input[@name=\'captcha\' or @id=\'captcha_code\']',
              'captchaButton': '//button[@type=\'submit\']',
              'captchaDetectType': 1,
              'captchaDetectValue': '',
              'captchaScript': '',
            },
          },
          '说明': 'captchaImage 指向验证码图片节点（App 内识别后填入）；captchaInput 指向输入框；captchaButton 指向提交按钮。三者 XPath 需按站点实际 DOM 修正。',
        };

    Map<String, dynamic> click() => {
          'name': '档2-点击/滑块类（captchaType=2）',
          '适用': '非普通图片验证：需要点击指定文字/图片、拖动滑块等交互验证',
          'template': {
            'antiCrawlerConfig': {
              'enabled': true,
              'captchaType': 2,
              'captchaImage': '',
              'captchaInput': '',
              'captchaButton': '',
              'captchaDetectType': 2,
              'captchaDetectValue': '',
              'captchaScript': '// 由 App 内置交互处理，captchaDetectType=2 时由客户端完成点击/滑块检测',
            },
          },
          '说明': '档2 由 App 端交互处理（自动点击/滑块），captchaScript 可留说明文案；若为自定义点击目标，可将目标选择器写入 captchaDetectValue。',
        };

    Map<String, dynamic> cf() => {
          'name': '档3-超级特殊验证（captchaType=3，CF/Akamai 等）',
          '适用': 'Cloudflare、Akamai 等强人机验证，App 无法自动通过；播放线路通常呈紫色（需登录）或反复弹验证',
          'template': {
            'antiCrawlerConfig': {
              'enabled': true,
              'captchaType': 3,
              'captchaImage': '',
              'captchaInput': '',
              'captchaButton': '',
              'captchaDetectType': 3,
              'captchaDetectValue': '',
              'captchaScript': '',
            },
            'needLogin': true,
            'loginURL': 'https://目标站登录页',
          },
          '说明': '档3 建议同时开启 needLogin=true + loginURL（走紫色登录线路），并在规则说明中提示用户需在 App 内登录该站后再播放；captchaScript 可留空由人工处理。',
        };

    Map<String, dynamic> purple() => {
          'name': '紫色模板-登录后观看（needLogin=true）',
          '适用': '站点搜索/详情可正常访问，但点击播放需登录（播放线路呈紫色）；或整站内容均需登录后观看',
          'template': {
            'needLogin': true,
            'loginURL': 'https://目标站登录页(真实地址)',
            'antiCrawlerConfig': {
              'enabled': false,
              'captchaType': 1,
              'captchaImage': '',
              'captchaInput': '',
              'captchaButton': '',
              'captchaDetectType': 1,
              'captchaDetectValue': '',
              'captchaScript': '',
            },
          },
          '说明': 'needLogin=true 表示播放需登录（线路显示紫色）；loginURL 必须填该站真实登录页地址（不能占位）。若登录页/搜索同时有验证码，再叠加对应档位 antiCrawlerConfig。规则说明中应提示：用户需先在 App 内登录该站账号，再播放紫色线路。',
        };

    final templates = <String, dynamic>{
      'image': image(),
      'click': click(),
      'cf': cf(),
      'purple': purple(),
      'login': purple(),
    };
    if (k == 'image' || k == 'click' || k == 'cf' || k == 'purple' || k == 'login') {
      return {'ok': true, ...templates[k] as Map<String, dynamic>, 'note': baseNote};
    }
    return {
      'ok': true,
      'guides': [image(), click(), cf(), purple()],
      'note': baseNote,
      '提示': '按目标站实际验证类型选对应档位；需要登录后观看的站点直接用 purple 紫色模板；不确定时先人工访问站点确认',
    };
  }

  /// 网页结构抓取：提取标题/链接/表单/iframe/meta。
  Future<Map<String, dynamic>> _fetchPage(String url) async {
    final u = url.trim();
    if (!u.startsWith('http')) {
      return {'ok': false, 'errors': ['请输入完整URL（含 http/https）']};
    }
    try {
      final resp = await http.get(Uri.parse(u), headers: const {'User-Agent': 'Mozilla/5.0 (Kazumi-MCP)'})
          .timeout(const Duration(seconds: 20));
      if (resp.statusCode != 200) {
        return {'ok': false, 'statusCode': resp.statusCode, 'errors': ['页面返回 ${resp.statusCode}']};
      }
      final doc = html_parser.parse(resp.body);
      final title = doc.querySelector('title')?.text?.trim() ?? '';
      final links = <Map<String, String>>[];
      for (final a in doc.querySelectorAll('a[href]')) {
        if (links.length >= 20) break;
        final href = (a.attributes['href'] ?? '').trim();
        final text = (a.text ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
        if (href.isNotEmpty && text.isNotEmpty) {
          links.add({
            'href': href.length > 100 ? href.substring(0, 100) : href,
            'text': text.length > 30 ? text.substring(0, 30) : text,
          });
        }
      }
      final forms = <Map<String, dynamic>>[];
      for (final f in doc.querySelectorAll('form')) {
        if (forms.length >= 10) break;
        final inputs = <Map<String, String>>[];
        for (final inp in f.querySelectorAll('input')) {
          if (inputs.length >= 10) break;
          final name = (inp.attributes['name'] ?? '').trim();
          final type = (inp.attributes['type'] ?? '').trim();
          final id = (inp.attributes['id'] ?? '').trim();
          if (name.isNotEmpty || id.isNotEmpty) {
            inputs.add({'name': name, 'id': id, 'type': type});
          }
        }
        forms.add({
          'action': (f.attributes['action'] ?? '').trim(),
          'method': (f.attributes['method'] ?? 'get').trim(),
          'inputs': inputs,
        });
      }
      final iframes = <String>[];
      for (final f in doc.querySelectorAll('iframe')) {
        if (iframes.length >= 10) break;
        final src = (f.attributes['src'] ?? '').trim();
        if (src.isNotEmpty) iframes.add(src);
      }
      final metaDesc = doc.querySelector('meta[name="description"]')?.attributes['content'] ?? '';
      return {
        'ok': true,
        'url': u,
        'title': title,
        'metaDescription': metaDesc,
        'links': links,
        'forms': forms,
        'iframes': iframes,
        'note': '若页面无服务端内容（SPA/JS渲染），links 可能为空，需用浏览器抓包找 JSON API（searchMode=api）',
      };
    } catch (e) {
      return {'ok': false, 'errors': [e.toString()]};
    }
  }

  /// Cookie/凭据指引：站点需登录(Cookie)时规则怎么写。
  Map<String, dynamic> _cookieHelper() {
    return {
      'ok': true,
      '标题': '站点需要登录(Cookie)时，规则怎么写',
      '要点': [
        '1. App 登录态机制：YHDM 内置 WebView 与请求共享 Cookie。站点需登录时，用户先在 App 内打开该站(useWebview:true)登录一次，Cookie 自动保存并用于后续请求，规则无需硬编码 Cookie。',
        '2. 规则字段：needLogin=true + loginURL(填真实登录页地址) → 播放线路显示紫色，提示用户需登录。',
        '3. userAgent 字段：部分站点要求浏览器 UA，可填站点常见浏览器的 UA；留空则用默认。',
        '4. Referer 需求：若站点校验来源，可在请求头配置里带 Referer(API 模式 request.headers；XPath 模式一般无需)。',
        '5. Cookie 会过期：失效时重新登录即可；不要把账号密码写进规则(明文不安全)。',
        '6. 编写/调试期实测：让用户从浏览器/站点控制台复制已登录 Cookie，用 test_with_cookie 粘贴实测，确认登录后搜索/选集能否通过。',
      ],
      '适用场景': [
        '整站需登录才能搜索或观看',
        '搜索可访问但播放需登录(紫色线路)',
        '站点对未登录请求返回 302/403 跳登录页',
      ],
    };
  }
}
