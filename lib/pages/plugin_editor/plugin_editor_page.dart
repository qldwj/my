import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:yhdm/plugins/plugins.dart';
import 'package:yhdm/plugins/api_rule_config.dart';
import 'package:yhdm/plugins/anti_crawler_config.dart';
import 'package:yhdm/plugins/plugins_controller.dart';
import 'package:yhdm/bean/appbar/sys_app_bar.dart';
import 'package:yhdm/pages/plugin_editor/editor_form_widgets.dart';
import 'package:yhdm/request/config/api_endpoints.dart';
import 'package:yhdm/services/plugin/api_rule_engine.dart';

abstract final class _RuleEditorText {
  static const pageTitle = '规则编辑器';
  static const testRule = '测试规则';
  static const save = '保存';

  static const modeXPath = 'XPath';
  static const modeApi = 'API';
  static const methodGet = 'GET';
  static const methodPost = 'POST';
  static const bodyTypeNone = '无';
  static const bodyTypeJson = 'JSON';
  static const bodyTypeForm = '表单';
  static const formatNested = '嵌套 JSON';
  static const formatDelimited = '分隔字符串';

  static const legacyParser = '简易解析';
  static const legacyParserDesc = '使用简易解析器而不是现代解析器';
  static const adBlocker = '广告过滤';
  static const adBlockerDesc = '启用 HLS 广告过滤';

  static const antiCrawlerEnable = '启用反反爬虫';
  static const antiCrawlerEnableDesc = '检索失败时显示验证码验证按钮而非重试';
  static const captchaTypeLabel = '验证类型';
  static const captchaTypeImage = '图片验证码';
  static const captchaTypeAutoClick = '自动点击';
  static const captchaTypeScript = '自定义脚本';
  static const captchaTypeImageDesc = '展示验证码图片，由用户手动输入';
  static const captchaTypeAutoClickDesc = '检测到验证按钮后自动模拟点击';
  static const captchaTypeScriptDesc = '加载页面后执行规则内的验证脚本';
  static const captchaTypeUnknownDesc = '未知验证类型';
  static const captchaDetectTypeLabel = '验证页检测方式';
  static const captchaDetectTypeDesc = '优先使用该标记判断搜索响应是否为验证页';
  static const captchaDetectText = '文本';
  static const captchaDetectRegex = '正则';
  static const captchaDetectValueHintText = '身份验证';
  static const captchaDetectValueHintRegex = '身份验证|smart_verify';
  static const captchaDetectValueHintXPath = '//button[@id="verify"]';

  // 登录配置（needLogin）
  static const loginModeLabel = '登录方式';
  static const loginModeWebview = '内置浏览器';
  static const loginModeXpath = '弹窗表单';
  static const loginModeApi = 'API 登录';
  static const loginAccountXpath = '账号 XPath';
  static const loginPasswordXpath = '密码 XPath';
  static const loginSubmitXpath = '提交按钮 XPath';
  static const loginSuccessXpath = '登录成功特征 XPath';
  static const loginApiMethod = '登录请求方法';
  static const loginApiUrl = '登录接口 URL';
  static const loginApiHeaders = '登录请求头';
  static const loginApiHeadersHelper = '如 {"Content-Type":"application/json"}';
  static const loginApiBody = '登录请求体';
  static const loginApiBodyHelper = 'JSON 字符串，@account/@password 会被替换';
  static const loginApiAccountField = '账号字段名';
  static const loginApiPasswordField = '密码字段名';
  static const loginApiTokenPath = 'token 提取路径';
  static const loginApiTokenPathHelper = '如 $.data.token';
  static const loginApiCookiePath = 'cookie 提取路径';
  static const checkModeLabel = '登录检查方式';
  static const checkModeApi = 'API 校验';
  static const checkModeXpath = '特征 XPath';
  static const checkModeLocal = '本地有效期';
  static const checkMethod = '检查请求方法';
  static const checkUrl = '检查接口 URL';
  static const checkUrlHelper = '如 /api/user/me，@token 会被替换';
  static const checkHeaders = '检查请求头';
  static const checkHeadersHelper = '如 {"Authorization":"Bearer @token"}';
  static const checkSuccessStatus = '成功状态码';
  static const checkSuccessCode = '成功业务码';
  static const checkTokenPlaceholder = 'token 占位符';
  static const checkXpath = '已登录特征 XPath';
  static const checkXpathHelper = '未登录页面不存在的节点';
  static const captchaImageHint = '//img[@class="captcha"]';
  static const captchaInputHint = '//input[@name="captcha"]';
  static const captchaButtonHint = '//button[@type="submit"]';
  static const captchaScriptHint =
      'KazumiCaptcha.log("ready"); KazumiCaptcha.done();';

  static const sectionBasic = '基本信息';
  static const sectionBasicDesc = '规则的名称、版本与站点地址';
  static const sectionSearch = '搜索规则';
  static const sectionSearchDesc = '定义如何在站点内检索条目';
  static const sectionChapter = '选集规则';
  static const sectionChapterDesc = '定义如何获取播放线路与剧集列表';
  static const advancedOptions = '高级选项';
  static const advancedOptionsDesc = '行为、网络与反反爬虫配置';
  static const groupBehavior = '行为设置';
  static const groupNetwork = '网络设置';
  static const groupAntiCrawler = '反反爬虫';

  static const ruleName = '规则名称';
  static const ruleVersion = '规则版本';
  static const baseUrl = '基础地址（URL）';
  static const searchRuleType = '搜索规则类型';
  static const chapterRuleType = '选集规则类型';

  static const searchUrl = '搜索地址（URL）';
  static const searchListXPath = '搜索结果列表（XPath）';
  static const itemNameXPath = '条目名称（XPath）';
  static const itemLinkXPath = '条目链接（XPath）';
  static const roadListXPath = '播放线路列表（XPath）';
  static const episodeListXPath = '剧集列表（XPath）';

  static const searchMethod = '搜索请求方法';
  static const searchRequestUrl = '搜索请求地址（URL）';
  static const searchHeaders = '搜索请求头（JSON）';
  static const searchQuery = '搜索查询参数（JSON）';
  static const searchBodyType = '搜索请求体类型';
  static const searchBody = '搜索请求体（JSON）';
  static const searchListPath = '搜索结果列表路径（JSONPath）';
  static const itemNamePath = '条目名称路径（JSONPath，相对条目）';
  static const itemSourcePath = '条目来源路径（JSONPath，相对条目）';
  static const detailPageUrl = '详情页地址模板（URL，可选）';
  static const detailPageUrlHelper = '@source 替换为条目来源，如 https://site/GV@source';

  static const chapterMethod = '选集请求方法';
  static const chapterRequestUrl = '选集请求地址（URL）';
  static const chapterHeaders = '选集请求头（JSON）';
  static const chapterQuery = '选集查询参数（JSON）';
  static const chapterBodyType = '选集请求体类型';
  static const chapterBody = '选集请求体（JSON）';
  static const chapterResponseFormat = '选集响应格式';
  static const roadListPath = '播放线路列表路径（JSONPath，留空表示单线路）';
  static const roadNamePath = '线路名称路径（JSONPath，相对线路）';
  static const episodeListPath = '剧集列表路径（JSONPath，相对线路）';
  static const episodeNamePath = '剧集名称路径（JSONPath，相对剧集）';
  static const playbackEntryPath = '播放入口地址路径（JSONPath，使用播放页地址模板时可留空）';
  static const playbackEntryPathHelper = '从剧集对象读取交给 WebView 的地址，可以是播放页面或媒体直链。';
  static const roadNamesPath = '线路名称串路径（JSONPath）';
  static const roadEpisodesPath = '线路剧集串路径（JSONPath）';
  static const roadSeparator = '线路分隔符';
  static const episodeSeparator = '剧集分隔符';
  static const fieldSeparator = '名称与地址分隔符';
  static const responseVariables = '响应变量（JSON：变量名 → JSONPath）';
  static const playPageUrl = '播放页地址模板（URL，可选）';
  static const playPageUrlHelper = '可用变量：@source、@episodeUrl、'
      '@roadIndex/@episodeIndex（从 0 起）、@roadNumber/@episodeNumber（从 1 起）'
      '及响应变量。';
  static const playPageQuery = '播放页查询参数（JSON）';
  static const playPageQueryHelper = '与地址模板可用变量相同，合并进最终 URL 的查询参数。';

  static const userAgent = '用户代理（User-Agent）';
  static const userAgentHelper = '仅用于播放器和下载器。';
  static const referer = '播放请求来源（Referer）';
  static const refererHelper = '仅用于播放器和下载器。';

  static const captchaDetectValue = '验证页检测值';
  static const captchaDetectValueHelper = '留空时使用验证码图片或验证按钮的 XPath 进行检测。';
  static const captchaImage = '验证码图片（XPath）';
  static const captchaImageHelper = '填写验证码图片元素的 XPath。';
  static const captchaInput = '验证码输入框（XPath）';
  static const captchaInputHelper = '填写验证码输入框元素的 XPath。';
  static const captchaSubmitButton = '验证提交按钮（XPath）';
  static const captchaSubmitButtonHelper = '填写提交验证码按钮元素的 XPath。';
  static const verifyButton = '验证按钮（XPath）';
  static const verifyButtonHelper = '填写验证按钮元素的 XPath，检测到后将自动点击。';
  static const captchaScript = '验证脚本（JavaScript）';
  static const captchaScriptHelper =
      '可调用 KazumiCaptcha.log、clicked、done 和 fail。';
}

class PluginEditorPage extends StatefulWidget {
  const PluginEditorPage({
    super.key,
    required this.plugin,
    required this.controller,
  });

  final Plugin plugin;
  final PluginsController controller;

  @override
  State<PluginEditorPage> createState() => _PluginEditorPageState();
}

class _PluginEditorPageState extends State<PluginEditorPage> {
  PluginsController get pluginsController => widget.controller;
  final TextEditingController nameController = TextEditingController();
  final TextEditingController versionController = TextEditingController();
  final TextEditingController userAgentController = TextEditingController();
  final TextEditingController baseURLController = TextEditingController();
  final TextEditingController iconController = TextEditingController();
  final TextEditingController searchURLController = TextEditingController();
  final TextEditingController searchListController = TextEditingController();
  final TextEditingController searchNameController = TextEditingController();
  final TextEditingController searchResultController = TextEditingController();
  final TextEditingController chapterRoadsController = TextEditingController();
  final TextEditingController chapterResultController = TextEditingController();
  final TextEditingController refererController = TextEditingController();
  final TextEditingController searchApiURLController = TextEditingController();
  final TextEditingController searchApiHeadersController =
      TextEditingController();
  final TextEditingController searchApiQueryController =
      TextEditingController();
  final TextEditingController searchApiBodyController = TextEditingController();
  final TextEditingController searchApiListPathController =
      TextEditingController();
  final TextEditingController searchApiNamePathController =
      TextEditingController();
  final TextEditingController searchApiSourcePathController =
      TextEditingController();
  final TextEditingController searchApiSourceTemplateController =
      TextEditingController();
  final TextEditingController chapterApiURLController = TextEditingController();
  final TextEditingController chapterApiHeadersController =
      TextEditingController();
  final TextEditingController chapterApiQueryController =
      TextEditingController();
  final TextEditingController chapterApiBodyController =
      TextEditingController();
  final TextEditingController chapterApiRoadsPathController =
      TextEditingController();
  final TextEditingController chapterApiRoadNamePathController =
      TextEditingController();
  final TextEditingController chapterApiEpisodesPathController =
      TextEditingController();
  final TextEditingController chapterApiEpisodeNamePathController =
      TextEditingController();
  final TextEditingController chapterApiEpisodeURLPathController =
      TextEditingController();
  final TextEditingController chapterApiRoadNamesPathController =
      TextEditingController();
  final TextEditingController chapterApiRoadEpisodesPathController =
      TextEditingController();
  final TextEditingController chapterApiRoadSeparatorController =
      TextEditingController();
  final TextEditingController chapterApiEpisodeSeparatorController =
      TextEditingController();
  final TextEditingController chapterApiFieldSeparatorController =
      TextEditingController();
  final TextEditingController chapterApiVariablesController =
      TextEditingController();
  final TextEditingController chapterApiPageURLController =
      TextEditingController();
  final TextEditingController chapterApiPageQueryController =
      TextEditingController();
  String searchMode = RuleMode.xpath;
  String chapterMode = RuleMode.xpath;
  String searchApiMethod = 'GET';
  String searchApiBodyType = ApiBodyType.none;
  String chapterApiMethod = 'GET';
  String chapterApiBodyType = ApiBodyType.none;
  String chapterApiFormat = ApiChapterFormat.nested;
  // Legacy schema values retained on save but no longer exposed as settings.
  late String _api;
  late String _type;
  late bool _muliSources;
  late bool _useWebview;
  late bool _useNativePlayer;
  bool usePost = false;
  bool useLegacyParser = false;
  bool adBlocker = false;

  // AntiCrawler fields
  final TextEditingController captchaImageController = TextEditingController();
  final TextEditingController captchaInputController = TextEditingController();
  final TextEditingController captchaButtonController = TextEditingController();
  final TextEditingController captchaDetectValueController =
      TextEditingController();
  final TextEditingController captchaScriptController = TextEditingController();
  bool antiCrawlerEnabled = false;
  int captchaType = CaptchaType.imageCaptcha;
  int captchaDetectType = CaptchaDetectType.xpath;
  bool needLogin = false;
  final TextEditingController loginUrlController = TextEditingController();
  // 登录配置（login.*）
  String loginMode = 'webview';
  final TextEditingController loginAccountXpathCtrl = TextEditingController();
  final TextEditingController loginPasswordXpathCtrl = TextEditingController();
  final TextEditingController loginSubmitXpathCtrl = TextEditingController();
  final TextEditingController loginSuccessXpathCtrl = TextEditingController();
  final TextEditingController loginApiMethodCtrl =
      TextEditingController(text: 'POST');
  final TextEditingController loginApiUrlCtrl = TextEditingController();
  final TextEditingController loginApiHeadersCtrl = TextEditingController();
  final TextEditingController loginApiBodyCtrl = TextEditingController();
  final TextEditingController loginApiAccountFieldCtrl = TextEditingController();
  final TextEditingController loginApiPasswordFieldCtrl = TextEditingController();
  final TextEditingController loginApiTokenPathCtrl = TextEditingController();
  final TextEditingController loginApiCookiePathCtrl = TextEditingController();
  // 登录检查（check.*）
  String checkMode = 'api';
  final TextEditingController checkMethodCtrl =
      TextEditingController(text: 'GET');
  final TextEditingController checkUrlCtrl = TextEditingController();
  final TextEditingController checkHeadersCtrl = TextEditingController();
  final TextEditingController checkSuccessStatusCtrl =
      TextEditingController(text: '200');
  final TextEditingController checkSuccessCodeCtrl =
      TextEditingController(text: '0');
  final TextEditingController checkTokenPlaceholderCtrl =
      TextEditingController(text: '@token');
  final TextEditingController checkXpathCtrl = TextEditingController();

  static const List<ButtonSegment<String>> _ruleModeSegments = [
    ButtonSegment(
      value: RuleMode.xpath,
      label: Text(_RuleEditorText.modeXPath),
    ),
    ButtonSegment(value: RuleMode.api, label: Text(_RuleEditorText.modeApi)),
  ];

  static const List<ButtonSegment<String>> _methodSegments = [
    ButtonSegment(value: 'GET', label: Text(_RuleEditorText.methodGet)),
    ButtonSegment(value: 'POST', label: Text(_RuleEditorText.methodPost)),
  ];

  static const List<ButtonSegment<String>> _loginModeSegments = [
    ButtonSegment(
      value: 'webview',
      label: Text(_RuleEditorText.loginModeWebview),
    ),
    ButtonSegment(
      value: 'xpath',
      label: Text(_RuleEditorText.loginModeXpath),
    ),
    ButtonSegment(value: 'api', label: Text(_RuleEditorText.loginModeApi)),
  ];

  static const List<ButtonSegment<String>> _checkModeSegments = [
    ButtonSegment(value: 'api', label: Text(_RuleEditorText.checkModeApi)),
    ButtonSegment(value: 'xpath', label: Text(_RuleEditorText.checkModeXpath)),
    ButtonSegment(value: 'local', label: Text(_RuleEditorText.checkModeLocal)),
  ];

  static const List<ButtonSegment<String>> _bodyTypeSegments = [
    ButtonSegment(
      value: ApiBodyType.none,
      label: Text(_RuleEditorText.bodyTypeNone),
    ),
    ButtonSegment(
      value: ApiBodyType.json,
      label: Text(_RuleEditorText.bodyTypeJson),
    ),
    ButtonSegment(
      value: ApiBodyType.form,
      label: Text(_RuleEditorText.bodyTypeForm),
    ),
  ];

  @override
  void initState() {
    super.initState();
    final Plugin plugin = widget.plugin;
    _api = plugin.api;
    _type = plugin.type;
    nameController.text = plugin.name;
    versionController.text = plugin.version;
    userAgentController.text = plugin.userAgent;
    baseURLController.text = plugin.baseUrl;
    iconController.text = plugin.icon;
    searchURLController.text = plugin.searchURL;
    searchListController.text = plugin.searchList;
    searchNameController.text = plugin.searchName;
    searchResultController.text = plugin.searchResult;
    chapterRoadsController.text = plugin.chapterRoads;
    chapterResultController.text = plugin.chapterResult;
    refererController.text = plugin.referer;
    searchMode = plugin.searchMode;
    chapterMode = plugin.chapterMode;
    searchApiMethod = plugin.searchApiConfig.request.method;
    searchApiBodyType = plugin.searchApiConfig.request.bodyType;
    searchApiURLController.text = plugin.searchApiConfig.request.url;
    searchApiHeadersController.text =
        _prettyJson(plugin.searchApiConfig.request.headers);
    searchApiQueryController.text =
        _prettyJson(plugin.searchApiConfig.request.query);
    searchApiBodyController.text =
        _prettyJson(plugin.searchApiConfig.request.body);
    searchApiListPathController.text = plugin.searchApiConfig.listPath;
    searchApiNamePathController.text = plugin.searchApiConfig.namePath;
    searchApiSourcePathController.text = plugin.searchApiConfig.sourcePath;
    searchApiSourceTemplateController.text =
        plugin.searchApiConfig.sourceTemplate;
    chapterApiMethod = plugin.chapterApiConfig.request.method;
    chapterApiBodyType = plugin.chapterApiConfig.request.bodyType;
    chapterApiFormat = plugin.chapterApiConfig.format;
    chapterApiURLController.text = plugin.chapterApiConfig.request.url;
    chapterApiHeadersController.text =
        _prettyJson(plugin.chapterApiConfig.request.headers);
    chapterApiQueryController.text =
        _prettyJson(plugin.chapterApiConfig.request.query);
    chapterApiBodyController.text =
        _prettyJson(plugin.chapterApiConfig.request.body);
    chapterApiRoadsPathController.text = plugin.chapterApiConfig.roadsPath;
    chapterApiRoadNamePathController.text =
        plugin.chapterApiConfig.roadNamePath;
    chapterApiEpisodesPathController.text =
        plugin.chapterApiConfig.episodesPath;
    chapterApiEpisodeNamePathController.text =
        plugin.chapterApiConfig.episodeNamePath;
    chapterApiEpisodeURLPathController.text =
        plugin.chapterApiConfig.episodeUrlPath;
    chapterApiRoadNamesPathController.text =
        plugin.chapterApiConfig.roadNamesPath;
    chapterApiRoadEpisodesPathController.text =
        plugin.chapterApiConfig.roadEpisodesPath;
    chapterApiRoadSeparatorController.text =
        plugin.chapterApiConfig.roadSeparator;
    chapterApiEpisodeSeparatorController.text =
        plugin.chapterApiConfig.episodeSeparator;
    chapterApiFieldSeparatorController.text =
        plugin.chapterApiConfig.fieldSeparator;
    chapterApiVariablesController.text =
        _prettyJson(plugin.chapterApiConfig.variables);
    chapterApiPageURLController.text =
        plugin.chapterApiConfig.episodePage?.url ?? '';
    chapterApiPageQueryController.text =
        _prettyJson(plugin.chapterApiConfig.episodePage?.query);
    _muliSources = plugin.muliSources;
    _useWebview = plugin.useWebview;
    _useNativePlayer = plugin.useNativePlayer;
    usePost = plugin.usePost;
    useLegacyParser = plugin.useLegacyParser;
    adBlocker = plugin.adBlocker;
    antiCrawlerEnabled = plugin.antiCrawlerConfig.enabled;
    needLogin = plugin.needLogin;
    loginUrlController.text = plugin.loginUrl;
    // 回填登录配置（login.*）
    final lc = plugin.loginConfig;
    if (lc != null) {
      loginMode = lc.mode;
      loginAccountXpathCtrl.text = lc.accountXpath;
      loginPasswordXpathCtrl.text = lc.passwordXpath;
      loginSubmitXpathCtrl.text = lc.submitXpath;
      loginSuccessXpathCtrl.text = lc.successXpath;
      final lapi = lc.api;
      if (lapi != null) {
        loginApiMethodCtrl.text = lapi.request.method;
        loginApiUrlCtrl.text = lapi.request.url;
        loginApiHeadersCtrl.text = _headersToText(lapi.request.headers);
        loginApiBodyCtrl.text =
            lapi.request.body is String ? lapi.request.body as String : '';
        loginApiAccountFieldCtrl.text = lapi.accountField;
        loginApiPasswordFieldCtrl.text = lapi.passwordField;
        loginApiTokenPathCtrl.text = lapi.tokenPath;
        loginApiCookiePathCtrl.text = lapi.cookiePath;
      }
    }
    // 回填登录检查（check.*）
    final cc = plugin.checkConfig;
    if (cc != null) {
      checkMode = cc.mode;
      checkMethodCtrl.text = cc.request.method;
      checkUrlCtrl.text = cc.request.url;
      checkHeadersCtrl.text = _headersToText(cc.request.headers);
      checkSuccessStatusCtrl.text = cc.successStatus.toString();
      checkSuccessCodeCtrl.text = (cc.successCode ?? 0).toString();
      checkTokenPlaceholderCtrl.text = cc.tokenPlaceholder;
      checkXpathCtrl.text = cc.xpath;
    }
    captchaType = plugin.antiCrawlerConfig.captchaType;
    captchaImageController.text = plugin.antiCrawlerConfig.captchaImage;
    captchaInputController.text = plugin.antiCrawlerConfig.captchaInput;
    captchaButtonController.text = plugin.antiCrawlerConfig.captchaButton;
    captchaDetectType = plugin.antiCrawlerConfig.captchaDetectType;
    captchaDetectValueController.text =
        plugin.antiCrawlerConfig.captchaDetectValue;
    captchaScriptController.text = plugin.antiCrawlerConfig.captchaScript;
  }

  @override
  void dispose() {
    _pageController.dispose();
    nameController.dispose();
    versionController.dispose();
    userAgentController.dispose();
    baseURLController.dispose();
    iconController.dispose();
    searchURLController.dispose();
    searchListController.dispose();
    searchNameController.dispose();
    searchResultController.dispose();
    chapterRoadsController.dispose();
    chapterResultController.dispose();
    refererController.dispose();
    searchApiURLController.dispose();
    searchApiHeadersController.dispose();
    searchApiQueryController.dispose();
    searchApiBodyController.dispose();
    searchApiListPathController.dispose();
    searchApiNamePathController.dispose();
    searchApiSourcePathController.dispose();
    searchApiSourceTemplateController.dispose();
    chapterApiURLController.dispose();
    chapterApiHeadersController.dispose();
    chapterApiQueryController.dispose();
    chapterApiBodyController.dispose();
    chapterApiRoadsPathController.dispose();
    chapterApiRoadNamePathController.dispose();
    chapterApiEpisodesPathController.dispose();
    chapterApiEpisodeNamePathController.dispose();
    chapterApiEpisodeURLPathController.dispose();
    chapterApiRoadNamesPathController.dispose();
    chapterApiRoadEpisodesPathController.dispose();
    chapterApiRoadSeparatorController.dispose();
    chapterApiEpisodeSeparatorController.dispose();
    chapterApiFieldSeparatorController.dispose();
    chapterApiVariablesController.dispose();
    chapterApiPageURLController.dispose();
    chapterApiPageQueryController.dispose();
    captchaImageController.dispose();
    captchaInputController.dispose();
    captchaButtonController.dispose();
    captchaDetectValueController.dispose();
    captchaScriptController.dispose();
    loginUrlController.dispose();
    loginAccountXpathCtrl.dispose();
    loginPasswordXpathCtrl.dispose();
    loginSubmitXpathCtrl.dispose();
    loginSuccessXpathCtrl.dispose();
    loginApiMethodCtrl.dispose();
    loginApiUrlCtrl.dispose();
    loginApiHeadersCtrl.dispose();
    loginApiBodyCtrl.dispose();
    loginApiAccountFieldCtrl.dispose();
    loginApiPasswordFieldCtrl.dispose();
    loginApiTokenPathCtrl.dispose();
    loginApiCookiePathCtrl.dispose();
    checkMethodCtrl.dispose();
    checkUrlCtrl.dispose();
    checkHeadersCtrl.dispose();
    checkSuccessStatusCtrl.dispose();
    checkSuccessCodeCtrl.dispose();
    checkTokenPlaceholderCtrl.dispose();
    checkXpathCtrl.dispose();
    super.dispose();
  }

  static String _prettyJson(Object? value) {
    if (value == null) return '';
    if (value is Map && value.isEmpty) return '{}';
    return const JsonEncoder.withIndent('  ').convert(value);
  }

  // 🆕 向导式编辑器：当前步骤（0=基本 1=搜索 2=选集 3=高级）
  int _step = 0;
  static const _stepTitles = ['基本', '搜索', '选集', '高级'];
  static const _stepIcons = [
    Icons.badge_rounded,
    Icons.search_rounded,
    Icons.playlist_play_rounded,
    Icons.tune_rounded,
  ];

  /// 🆕 左右滑动切换步骤用的 PageController
  late final PageController _pageController =
      PageController(initialPage: _step);

  void _goStep(int step) {
    if (step < 0 || step >= _stepTitles.length) return;
    setState(() => _step = step);
    if (_pageController.hasClients) {
      _pageController.animateToPage(
        step,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
      );
    }
  }

  /// 保存当前规则
  Future<void> _savePlugin() async {
    final editedPlugin = _tryBuildEditedPlugin();
    if (editedPlugin == null) return;
    try {
      await pluginsController.updatePlugin(editedPlugin);
    } catch (error) {
      _showEditorError(error);
      return;
    }
    if (!context.mounted) return;
    context.pop();
  }

  /// 打开规则测试页
  void _testPlugin() {
    final editedPlugin = _tryBuildEditedPlugin();
    if (editedPlugin == null) return;
    context.pushNamed(
      '/settings/plugin/test',
      arguments: editedPlugin,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: SysAppBar(
        title: const Text(_RuleEditorText.pageTitle),
      ),
      body: Column(
        children: [
          // 顶部步骤指示器
          _buildStepIndicator(context),
          Expanded(
            // 🆕 左右滑动切换步骤
            child: PageView.builder(
              controller: _pageController,
              itemCount: _stepTitles.length,
              onPageChanged: (i) => setState(() => _step = i),
              itemBuilder: (context, index) => SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1000),
                    child: _buildStepContent(index),
                  ),
                ),
              ),
            ),
          ),
          // 底部按钮栏
          _buildBottomBar(context),
        ],
      ),
    );
  }

  /// 当前步骤对应的内容
  Widget _buildCurrentStep() => _buildStepContent(_step);

  /// 指定步骤的内容
  Widget _buildStepContent(int step) {
    switch (step) {
      case 0:
        return EditorSectionCard(
          icon: Icons.badge_rounded,
          title: _RuleEditorText.sectionBasic,
          description: _RuleEditorText.sectionBasicDesc,
          children: [
            EditorTextField(
              controller: nameController,
              label: _RuleEditorText.ruleName,
            ),
            EditorTextField(
              controller: versionController,
              label: _RuleEditorText.ruleVersion,
            ),
            EditorTextField(
              controller: baseURLController,
              label: _RuleEditorText.baseUrl,
            ),
            EditorTextField(
              controller: iconController,
              label: '图标 URL（动漫头像，可留空用默认）',
            ),
            const EditorSubheader(label: '认证选项'),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('该网站需要验证'),
              subtitle: const Text('检索失败时显示验证码验证按钮而非重试'),
              value: antiCrawlerEnabled,
              activeColor: Colors.blue,
              secondary: const Icon(Icons.verified_user_outlined,
                  color: Colors.blue),
              onChanged: (value) =>
                  setState(() => antiCrawlerEnabled = value ?? false),
            ),
            if (antiCrawlerEnabled)
              EditorSegmentedField<int>(
                label: _RuleEditorText.captchaTypeLabel,
                value: captchaType,
                segments: const [
                  ButtonSegment(
                    value: CaptchaType.imageCaptcha,
                    label: Text(_RuleEditorText.captchaTypeImage),
                  ),
                  ButtonSegment(
                    value: CaptchaType.autoClickButton,
                    label: Text(_RuleEditorText.captchaTypeAutoClick),
                  ),
                  ButtonSegment(
                    value: CaptchaType.customJavaScript,
                    label: Text(_RuleEditorText.captchaTypeScript),
                  ),
                ],
                onChanged: (value) => setState(() => captchaType = value),
              ),
            EditorAnimatedSection(
              activeKey: captchaType,
              child: Column(
                spacing: 16,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (captchaType == CaptchaType.imageCaptcha) ...[
                    EditorTextField(
                      controller: captchaImageController,
                      label: _RuleEditorText.captchaImage,
                      hint: _RuleEditorText.captchaImageHint,
                      helper: _RuleEditorText.captchaImageHelper,
                    ),
                    EditorTextField(
                      controller: captchaInputController,
                      label: _RuleEditorText.captchaInput,
                      hint: _RuleEditorText.captchaInputHint,
                      helper: _RuleEditorText.captchaInputHelper,
                    ),
                  ],
                  if (captchaType != CaptchaType.customJavaScript)
                    EditorTextField(
                      controller: captchaButtonController,
                      label: captchaType == CaptchaType.imageCaptcha
                          ? _RuleEditorText.captchaSubmitButton
                          : _RuleEditorText.verifyButton,
                      hint: _RuleEditorText.captchaButtonHint,
                      helper: captchaType == CaptchaType.imageCaptcha
                          ? _RuleEditorText.captchaSubmitButtonHelper
                          : _RuleEditorText.verifyButtonHelper,
                    ),
                  if (captchaType == CaptchaType.customJavaScript)
                    EditorTextField(
                      controller: captchaScriptController,
                      label: _RuleEditorText.captchaScript,
                      hint: _RuleEditorText.captchaScriptHint,
                      helper: _RuleEditorText.captchaScriptHelper,
                      maxLines: 8,
                    ),
                ],
              ),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('该网站需要登录'),
              subtitle: const Text('观看前需登录验证，用内置 WebView 登录'),
              value: needLogin,
              activeColor: Colors.purple,
              secondary: const Icon(Icons.lock_outline, color: Colors.purple),
              onChanged: (value) => setState(() => needLogin = value ?? false),
            ),
            if (needLogin) ..._buildLoginConfigFields(),
          ],
        );
      case 1:
        return EditorSectionCard(
          icon: Icons.search_rounded,
          title: _RuleEditorText.sectionSearch,
          description: _RuleEditorText.sectionSearchDesc,
          children: [
            EditorSegmentedField<String>(
              label: _RuleEditorText.searchRuleType,
              value: searchMode,
              segments: _ruleModeSegments,
              onChanged: (value) => setState(() => searchMode = value),
            ),
            EditorAnimatedSection(
              activeKey: searchMode,
              child: Column(
                spacing: 16,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: searchMode == RuleMode.xpath
                    ? _buildXPathSearchFields()
                    : _buildApiSearchFields(),
              ),
            ),
          ],
        );
      case 2:
        return EditorSectionCard(
          icon: Icons.playlist_play_rounded,
          title: _RuleEditorText.sectionChapter,
          description: _RuleEditorText.sectionChapterDesc,
          children: [
            EditorSegmentedField<String>(
              label: _RuleEditorText.chapterRuleType,
              value: chapterMode,
              segments: _ruleModeSegments,
              onChanged: (value) => setState(() => chapterMode = value),
            ),
            EditorAnimatedSection(
              activeKey: chapterMode,
              child: Column(
                spacing: 16,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: chapterMode == RuleMode.xpath
                    ? _buildXPathChapterFields()
                    : _buildApiChapterFields(),
              ),
            ),
          ],
        );
      default:
        return _buildAdvancedOptionsCard();
    }
  }

  /// 顶部步骤指示器（1 基本 → 2 搜索 → 3 选集 → 4 高级）
  Widget _buildStepIndicator(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(
          bottom: BorderSide(color: colors.outlineVariant.withOpacity(0.5)),
        ),
      ),
      child: Row(
        children: [
          for (var i = 0; i < _stepTitles.length; i++) ...[
            if (i > 0)
              Expanded(
                child: Container(
                  height: 2,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  color: i <= _step
                      ? colors.primary
                      : colors.outlineVariant.withOpacity(0.5),
                ),
              ),
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _goStep(i),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: i == _step
                            ? colors.primary
                            : i < _step
                                ? colors.primaryContainer
                                : colors.surfaceContainerHighest,
                        shape: BoxShape.circle,
                      ),
                      child: i < _step
                          ? Icon(Icons.check_rounded,
                              size: 18, color: colors.onPrimaryContainer)
                          : Icon(
                              _stepIcons[i],
                              size: 16,
                              color: i == _step
                                  ? colors.onPrimary
                                  : colors.onSurfaceVariant,
                            ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _stepTitles[i],
                      style: text.labelSmall?.copyWith(
                        color: i == _step
                            ? colors.primary
                            : colors.onSurfaceVariant,
                        fontWeight:
                            i == _step ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 底部按钮栏：左下「测试」+「上一步」，右下「下一页 / 保存」
  Widget _buildBottomBar(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isLast = _step == _stepTitles.length - 1;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(
          top: BorderSide(color: colors.outlineVariant.withOpacity(0.5)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // 左下：测试
            OutlinedButton.icon(
              onPressed: _testPlugin,
              icon: const Icon(Icons.bug_report_outlined, size: 18),
              label: const Text('测试'),
            ),
            const SizedBox(width: 8),
            // 上一步
            if (_step > 0)
              TextButton.icon(
                onPressed: () => _goStep(_step - 1),
                icon: const Icon(Icons.chevron_left_rounded, size: 18),
                label: const Text('上一步'),
              ),
            const Spacer(),
            // 右下：下一页 / 保存
            if (isLast)
              FilledButton.icon(
                onPressed: _savePlugin,
                icon: const Icon(Icons.save_rounded, size: 18),
                label: const Text(_RuleEditorText.save),
              )
            else
              FilledButton.icon(
                onPressed: () => _goStep(_step + 1),
                icon: const Icon(Icons.chevron_right_rounded, size: 18),
                label: const Text('下一页'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdvancedOptionsCard() {
    return EditorExpandableSectionCard(
      icon: Icons.tune_rounded,
      title: _RuleEditorText.advancedOptions,
      description: _RuleEditorText.advancedOptionsDesc,
      children: [
        const EditorSubheader(label: _RuleEditorText.groupBehavior),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text(_RuleEditorText.legacyParser),
          subtitle: const Text(_RuleEditorText.legacyParserDesc),
          value: useLegacyParser,
          onChanged: (value) => setState(() => useLegacyParser = value),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text(_RuleEditorText.adBlocker),
          subtitle: const Text(_RuleEditorText.adBlockerDesc),
          value: adBlocker,
          onChanged: (value) => setState(() => adBlocker = value),
        ),
        const EditorSubheader(label: _RuleEditorText.groupNetwork),
        EditorTextField(
          controller: userAgentController,
          label: _RuleEditorText.userAgent,
          helper: _RuleEditorText.userAgentHelper,
        ),
        const SizedBox(height: 16),
        EditorTextField(
          controller: refererController,
          label: _RuleEditorText.referer,
          helper: _RuleEditorText.refererHelper,
        ),
        if (searchMode == RuleMode.xpath) ...[
          const EditorSubheader(label: _RuleEditorText.groupAntiCrawler),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(_RuleEditorText.antiCrawlerEnable),
            subtitle: const Text(_RuleEditorText.antiCrawlerEnableDesc),
            value: antiCrawlerEnabled,
            onChanged: (value) => setState(() => antiCrawlerEnabled = value),
          ),
          EditorAnimatedSection(
            activeKey: antiCrawlerEnabled,
            child: antiCrawlerEnabled
                ? Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Column(
                      spacing: 16,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: _buildAntiCrawlerFields(),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ],
    );
  }

  List<Widget> _buildAntiCrawlerFields() => [
        EditorSegmentedField<int>(
          label: _RuleEditorText.captchaTypeLabel,
          value: captchaType,
          segments: const [
            ButtonSegment(
              value: CaptchaType.imageCaptcha,
              label: Text(_RuleEditorText.captchaTypeImage),
            ),
            ButtonSegment(
              value: CaptchaType.autoClickButton,
              label: Text(_RuleEditorText.captchaTypeAutoClick),
            ),
            ButtonSegment(
              value: CaptchaType.customJavaScript,
              label: Text(_RuleEditorText.captchaTypeScript),
            ),
          ],
          onChanged: (value) => setState(() => captchaType = value),
          description: (value) => switch (value) {
            CaptchaType.imageCaptcha => _RuleEditorText.captchaTypeImageDesc,
            CaptchaType.autoClickButton =>
              _RuleEditorText.captchaTypeAutoClickDesc,
            CaptchaType.customJavaScript =>
              _RuleEditorText.captchaTypeScriptDesc,
            _ => _RuleEditorText.captchaTypeUnknownDesc,
          },
        ),
        EditorSegmentedField<int>(
          label: _RuleEditorText.captchaDetectTypeLabel,
          value: captchaDetectType,
          segments: const [
            ButtonSegment(
              value: CaptchaDetectType.xpath,
              label: Text(_RuleEditorText.modeXPath),
            ),
            ButtonSegment(
              value: CaptchaDetectType.text,
              label: Text(_RuleEditorText.captchaDetectText),
            ),
            ButtonSegment(
              value: CaptchaDetectType.regex,
              label: Text(_RuleEditorText.captchaDetectRegex),
            ),
          ],
          onChanged: (value) => setState(() => captchaDetectType = value),
          description: (_) => _RuleEditorText.captchaDetectTypeDesc,
        ),
        EditorTextField(
          controller: captchaDetectValueController,
          label: _RuleEditorText.captchaDetectValue,
          hint: captchaDetectType == CaptchaDetectType.text
              ? _RuleEditorText.captchaDetectValueHintText
              : captchaDetectType == CaptchaDetectType.regex
                  ? _RuleEditorText.captchaDetectValueHintRegex
                  : _RuleEditorText.captchaDetectValueHintXPath,
          helper: _RuleEditorText.captchaDetectValueHelper,
        ),
        EditorAnimatedSection(
          activeKey: captchaType,
          child: Column(
            spacing: 16,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (captchaType == CaptchaType.imageCaptcha) ...[
                EditorTextField(
                  controller: captchaImageController,
                  label: _RuleEditorText.captchaImage,
                  hint: _RuleEditorText.captchaImageHint,
                  helper: _RuleEditorText.captchaImageHelper,
                ),
                EditorTextField(
                  controller: captchaInputController,
                  label: _RuleEditorText.captchaInput,
                  hint: _RuleEditorText.captchaInputHint,
                  helper: _RuleEditorText.captchaInputHelper,
                ),
              ],
              if (captchaType != CaptchaType.customJavaScript)
                EditorTextField(
                  controller: captchaButtonController,
                  label: captchaType == CaptchaType.imageCaptcha
                      ? _RuleEditorText.captchaSubmitButton
                      : _RuleEditorText.verifyButton,
                  hint: _RuleEditorText.captchaButtonHint,
                  helper: captchaType == CaptchaType.imageCaptcha
                      ? _RuleEditorText.captchaSubmitButtonHelper
                      : _RuleEditorText.verifyButtonHelper,
                ),
              if (captchaType == CaptchaType.customJavaScript)
                EditorTextField(
                  controller: captchaScriptController,
                  label: _RuleEditorText.captchaScript,
                  hint: _RuleEditorText.captchaScriptHint,
                  helper: _RuleEditorText.captchaScriptHelper,
                  maxLines: 8,
                ),
            ],
          ),
        ),
      ];

  /// 🆕 登录配置表单（needLogin 开启时）：登录方式 + 各模式字段 + 登录检查。
  List<Widget> _buildLoginConfigFields() => [
        EditorTextField(
          controller: loginUrlController,
          label: '登录 URL',
          helper: '填写登录页地址，观看前用内置 WebView 打开登录',
        ),
        EditorSegmentedField<String>(
          label: _RuleEditorText.loginModeLabel,
          value: loginMode,
          segments: _loginModeSegments,
          onChanged: (value) => setState(() => loginMode = value),
        ),
        EditorAnimatedSection(
          activeKey: loginMode,
          child: Column(
            spacing: 16,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: _buildLoginModeFields(),
          ),
        ),
        const SizedBox(height: 8),
        EditorSegmentedField<String>(
          label: _RuleEditorText.checkModeLabel,
          value: checkMode,
          segments: _checkModeSegments,
          onChanged: (value) => setState(() => checkMode = value),
        ),
        EditorAnimatedSection(
          activeKey: checkMode,
          child: Column(
            spacing: 16,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: _buildCheckModeFields(),
          ),
        ),
      ];

  List<Widget> _buildLoginModeFields() {
    if (loginMode == 'xpath') {
      return [
        EditorTextField(
          controller: loginAccountXpathCtrl,
          label: _RuleEditorText.loginAccountXpath,
        ),
        EditorTextField(
          controller: loginPasswordXpathCtrl,
          label: _RuleEditorText.loginPasswordXpath,
        ),
        EditorTextField(
          controller: loginSubmitXpathCtrl,
          label: _RuleEditorText.loginSubmitXpath,
        ),
        EditorTextField(
          controller: loginSuccessXpathCtrl,
          label: _RuleEditorText.loginSuccessXpath,
        ),
      ];
    }
    if (loginMode == 'api') {
      return [
        EditorSegmentedField<String>(
          label: _RuleEditorText.loginApiMethod,
          value: loginApiMethodCtrl.text.isEmpty
              ? 'POST'
              : loginApiMethodCtrl.text,
          segments: _methodSegments,
          onChanged: (value) =>
              setState(() => loginApiMethodCtrl.text = value),
        ),
        EditorTextField(
          controller: loginApiUrlCtrl,
          label: _RuleEditorText.loginApiUrl,
        ),
        EditorTextField(
          controller: loginApiHeadersCtrl,
          label: _RuleEditorText.loginApiHeaders,
          helper: _RuleEditorText.loginApiHeadersHelper,
        ),
        EditorTextField(
          controller: loginApiBodyCtrl,
          label: _RuleEditorText.loginApiBody,
          helper: _RuleEditorText.loginApiBodyHelper,
          maxLines: 4,
        ),
        EditorTextField(
          controller: loginApiAccountFieldCtrl,
          label: _RuleEditorText.loginApiAccountField,
        ),
        EditorTextField(
          controller: loginApiPasswordFieldCtrl,
          label: _RuleEditorText.loginApiPasswordField,
        ),
        EditorTextField(
          controller: loginApiTokenPathCtrl,
          label: _RuleEditorText.loginApiTokenPath,
          helper: _RuleEditorText.loginApiTokenPathHelper,
        ),
        EditorTextField(
          controller: loginApiCookiePathCtrl,
          label: _RuleEditorText.loginApiCookiePath,
        ),
      ];
    }
    return const [];
  }

  List<Widget> _buildCheckModeFields() {
    if (checkMode == 'xpath') {
      return [
        EditorTextField(
          controller: checkXpathCtrl,
          label: _RuleEditorText.checkXpath,
          helper: _RuleEditorText.checkXpathHelper,
        ),
      ];
    }
    if (checkMode == 'local') return const [];
    return [
      EditorSegmentedField<String>(
        label: _RuleEditorText.checkMethod,
        value: checkMethodCtrl.text.isEmpty ? 'GET' : checkMethodCtrl.text,
        segments: _methodSegments,
        onChanged: (value) => setState(() => checkMethodCtrl.text = value),
      ),
      EditorTextField(
        controller: checkUrlCtrl,
        label: _RuleEditorText.checkUrl,
        helper: _RuleEditorText.checkUrlHelper,
      ),
      EditorTextField(
        controller: checkHeadersCtrl,
        label: _RuleEditorText.checkHeaders,
        helper: _RuleEditorText.checkHeadersHelper,
      ),
      EditorTextField(
        controller: checkSuccessStatusCtrl,
        label: _RuleEditorText.checkSuccessStatus,
      ),
      EditorTextField(
        controller: checkSuccessCodeCtrl,
        label: _RuleEditorText.checkSuccessCode,
      ),
      EditorTextField(
        controller: checkTokenPlaceholderCtrl,
        label: _RuleEditorText.checkTokenPlaceholder,
      ),
    ];
  }

  List<Widget> _buildXPathSearchFields() => [
        EditorSegmentedField<String>(
          label: _RuleEditorText.searchMethod,
          value: usePost ? 'POST' : 'GET',
          segments: _methodSegments,
          onChanged: (value) => setState(() => usePost = value == 'POST'),
        ),
        EditorTextField(
          controller: searchURLController,
          label: _RuleEditorText.searchUrl,
        ),
        EditorTextField(
          controller: searchListController,
          label: _RuleEditorText.searchListXPath,
        ),
        EditorTextField(
          controller: searchNameController,
          label: _RuleEditorText.itemNameXPath,
        ),
        EditorTextField(
          controller: searchResultController,
          label: _RuleEditorText.itemLinkXPath,
        ),
      ];

  List<Widget> _buildXPathChapterFields() => [
        EditorTextField(
          controller: chapterRoadsController,
          label: _RuleEditorText.roadListXPath,
        ),
        EditorTextField(
          controller: chapterResultController,
          label: _RuleEditorText.episodeListXPath,
        ),
      ];

  List<Widget> _buildApiSearchFields() => [
        EditorSegmentedField<String>(
          label: _RuleEditorText.searchMethod,
          value: searchApiMethod,
          segments: _methodSegments,
          onChanged: (value) => setState(() => searchApiMethod = value),
        ),
        EditorTextField(
          controller: searchApiURLController,
          label: _RuleEditorText.searchRequestUrl,
        ),
        EditorTextField(
          controller: searchApiHeadersController,
          label: _RuleEditorText.searchHeaders,
          maxLines: 4,
        ),
        EditorTextField(
          controller: searchApiQueryController,
          label: _RuleEditorText.searchQuery,
          maxLines: 4,
        ),
        EditorSegmentedField<String>(
          label: _RuleEditorText.searchBodyType,
          value: searchApiBodyType,
          segments: _bodyTypeSegments,
          onChanged: (value) => setState(() => searchApiBodyType = value),
        ),
        if (searchApiBodyType != ApiBodyType.none)
          EditorTextField(
            controller: searchApiBodyController,
            label: _RuleEditorText.searchBody,
            maxLines: 5,
          ),
        EditorTextField(
          controller: searchApiListPathController,
          label: _RuleEditorText.searchListPath,
        ),
        EditorTextField(
          controller: searchApiNamePathController,
          label: _RuleEditorText.itemNamePath,
        ),
        EditorTextField(
          controller: searchApiSourcePathController,
          label: _RuleEditorText.itemSourcePath,
        ),
        EditorTextField(
          controller: searchApiSourceTemplateController,
          label: _RuleEditorText.detailPageUrl,
          helper: _RuleEditorText.detailPageUrlHelper,
        ),
      ];

  List<Widget> _buildApiChapterFields() => [
        EditorSegmentedField<String>(
          label: _RuleEditorText.chapterMethod,
          value: chapterApiMethod,
          segments: _methodSegments,
          onChanged: (value) => setState(() => chapterApiMethod = value),
        ),
        EditorTextField(
          controller: chapterApiURLController,
          label: _RuleEditorText.chapterRequestUrl,
        ),
        EditorTextField(
          controller: chapterApiHeadersController,
          label: _RuleEditorText.chapterHeaders,
          maxLines: 4,
        ),
        EditorTextField(
          controller: chapterApiQueryController,
          label: _RuleEditorText.chapterQuery,
          maxLines: 4,
        ),
        EditorSegmentedField<String>(
          label: _RuleEditorText.chapterBodyType,
          value: chapterApiBodyType,
          segments: _bodyTypeSegments,
          onChanged: (value) => setState(() => chapterApiBodyType = value),
        ),
        if (chapterApiBodyType != ApiBodyType.none)
          EditorTextField(
            controller: chapterApiBodyController,
            label: _RuleEditorText.chapterBody,
            maxLines: 5,
          ),
        EditorSegmentedField<String>(
          label: _RuleEditorText.chapterResponseFormat,
          value: chapterApiFormat,
          segments: const [
            ButtonSegment(
              value: ApiChapterFormat.nested,
              label: Text(_RuleEditorText.formatNested),
            ),
            ButtonSegment(
              value: ApiChapterFormat.delimited,
              label: Text(_RuleEditorText.formatDelimited),
            ),
          ],
          onChanged: (value) => setState(() => chapterApiFormat = value),
        ),
        EditorAnimatedSection(
          activeKey: chapterApiFormat,
          child: Column(
            spacing: 16,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: chapterApiFormat == ApiChapterFormat.nested
                ? [
                    EditorTextField(
                      controller: chapterApiRoadsPathController,
                      label: _RuleEditorText.roadListPath,
                    ),
                    EditorTextField(
                      controller: chapterApiRoadNamePathController,
                      label: _RuleEditorText.roadNamePath,
                    ),
                    EditorTextField(
                      controller: chapterApiEpisodesPathController,
                      label: _RuleEditorText.episodeListPath,
                    ),
                    EditorTextField(
                      controller: chapterApiEpisodeNamePathController,
                      label: _RuleEditorText.episodeNamePath,
                    ),
                    EditorTextField(
                      controller: chapterApiEpisodeURLPathController,
                      label: _RuleEditorText.playbackEntryPath,
                      helper: _RuleEditorText.playbackEntryPathHelper,
                    ),
                  ]
                : [
                    EditorTextField(
                      controller: chapterApiRoadNamesPathController,
                      label: _RuleEditorText.roadNamesPath,
                    ),
                    EditorTextField(
                      controller: chapterApiRoadEpisodesPathController,
                      label: _RuleEditorText.roadEpisodesPath,
                    ),
                    EditorTextField(
                      controller: chapterApiRoadSeparatorController,
                      label: _RuleEditorText.roadSeparator,
                    ),
                    EditorTextField(
                      controller: chapterApiEpisodeSeparatorController,
                      label: _RuleEditorText.episodeSeparator,
                    ),
                    EditorTextField(
                      controller: chapterApiFieldSeparatorController,
                      label: _RuleEditorText.fieldSeparator,
                    ),
                  ],
          ),
        ),
        EditorTextField(
          controller: chapterApiVariablesController,
          label: _RuleEditorText.responseVariables,
          maxLines: 5,
        ),
        EditorTextField(
          controller: chapterApiPageURLController,
          label: _RuleEditorText.playPageUrl,
          helper: _RuleEditorText.playPageUrlHelper,
        ),
        EditorTextField(
          controller: chapterApiPageQueryController,
          label: _RuleEditorText.playPageQuery,
          helper: _RuleEditorText.playPageQueryHelper,
          maxLines: 5,
        ),
      ];

  /// Builds the edited plugin, surfacing build/validation errors to the
  /// user. Returns null when the current input does not form a valid rule.
  Plugin? _tryBuildEditedPlugin() {
    try {
      return _buildEditedPlugin();
    } catch (error) {
      _showEditorError(error);
      return null;
    }
  }

  Plugin _buildEditedPlugin() {
    final searchConfig = _buildSearchApiConfig();
    final chapterConfig = _buildChapterApiConfig();
    return Plugin(
      api: searchMode == RuleMode.api || chapterMode == RuleMode.api
          ? ApiEndpoints.apiLevel.toString()
          : _api,
      type: _type,
      name: nameController.text,
      version: versionController.text,
      muliSources: _muliSources,
      useWebview: _useWebview,
      useNativePlayer: _useNativePlayer,
      usePost: usePost,
      useLegacyParser: useLegacyParser,
      adBlocker: adBlocker,
      needLogin: needLogin,
      loginUrl: loginUrlController.text.trim(),
      loginConfig: _buildLoginConfig(),
      checkConfig: _buildCheckConfig(),
      userAgent: userAgentController.text,
      baseUrl: baseURLController.text,
      icon: iconController.text.trim(),
      searchURL: searchURLController.text,
      searchList: searchListController.text,
      searchName: searchNameController.text,
      searchResult: searchResultController.text,
      chapterRoads: chapterRoadsController.text,
      chapterResult: chapterResultController.text,
      referer: refererController.text,
      searchMode: searchMode,
      chapterMode: chapterMode,
      searchApiConfig: searchConfig,
      chapterApiConfig: chapterConfig,
      antiCrawlerConfig: AntiCrawlerConfig(
        enabled: antiCrawlerEnabled,
        captchaType: captchaType,
        captchaImage: captchaImageController.text,
        captchaInput: captchaInputController.text,
        captchaButton: captchaButtonController.text,
        captchaDetectType: captchaDetectType,
        captchaDetectValue: captchaDetectValueController.text,
        captchaScript: captchaScriptController.text,
      ),
    );
  }

  ApiSearchConfig _buildSearchApiConfig() {
    final shouldValidate = searchMode == RuleMode.api;
    String valueOf(TextEditingController controller) =>
        shouldValidate ? controller.text.trim() : controller.text;
    final config = ApiSearchConfig(
      request: ApiRequestConfig(
        method: searchApiMethod,
        url: valueOf(searchApiURLController),
        headers: _parseJsonMap(searchApiHeadersController, '搜索请求头'),
        query: _parseJsonMap(searchApiQueryController, '搜索查询参数'),
        bodyType: searchApiBodyType,
        body: _parseBody(
          searchApiBodyController,
          searchApiBodyType,
          '搜索请求体',
        ),
      ),
      listPath: valueOf(searchApiListPathController),
      namePath: valueOf(searchApiNamePathController),
      sourcePath: valueOf(searchApiSourcePathController),
      sourceTemplate: valueOf(searchApiSourceTemplateController),
    );
    if (!shouldValidate) return config;
    if (config.request.url.isEmpty) {
      throw const FormatException('搜索请求地址不能为空');
    }
    const ApiRuleStrategy()
      ..prepareRequest(config.request, const {'keyword': 'test'})
      ..validateSearchConfig(config);
    return config;
  }

  ApiChapterConfig _buildChapterApiConfig() {
    final pageUrl = chapterApiPageURLController.text.trim();
    final variablesRaw = _parseJsonMap(
      chapterApiVariablesController,
      '选集响应变量',
    );
    final config = ApiChapterConfig(
      request: ApiRequestConfig(
        method: chapterApiMethod,
        url: chapterApiURLController.text.trim(),
        headers: _parseJsonMap(chapterApiHeadersController, '选集请求头'),
        query: _parseJsonMap(chapterApiQueryController, '选集查询参数'),
        bodyType: chapterApiBodyType,
        body: _parseBody(
          chapterApiBodyController,
          chapterApiBodyType,
          '选集请求体',
        ),
      ),
      format: chapterApiFormat,
      roadsPath: chapterApiRoadsPathController.text.trim(),
      roadNamePath: chapterApiRoadNamePathController.text.trim(),
      episodesPath: chapterApiEpisodesPathController.text.trim(),
      episodeNamePath: chapterApiEpisodeNamePathController.text.trim(),
      episodeUrlPath: chapterApiEpisodeURLPathController.text.trim(),
      roadNamesPath: chapterApiRoadNamesPathController.text.trim(),
      roadEpisodesPath: chapterApiRoadEpisodesPathController.text.trim(),
      roadSeparator: chapterApiRoadSeparatorController.text,
      episodeSeparator: chapterApiEpisodeSeparatorController.text,
      fieldSeparator: chapterApiFieldSeparatorController.text,
      variables: variablesRaw.map(
        (key, value) => MapEntry(key, value.toString()),
      ),
      episodePage: pageUrl.isEmpty
          ? null
          : ApiEpisodePageConfig(
              url: pageUrl,
              query: _parseJsonMap(
                chapterApiPageQueryController,
                '播放页查询参数',
              ),
            ),
    );
    if (chapterMode != RuleMode.api) return config;
    if (config.request.url.isEmpty) {
      throw const FormatException('选集请求地址不能为空');
    }
    const ApiRuleStrategy()
      ..prepareRequest(config.request, const {'source': 'test'})
      ..validateChapterConfig(config);
    return config;
  }

  Map<String, dynamic> _parseJsonMap(
    TextEditingController controller,
    String label,
  ) {
    final text = controller.text.trim();
    if (text.isEmpty) return <String, dynamic>{};
    final value = jsonDecode(text);
    if (value is! Map) throw FormatException('$label 必须是 JSON 对象');
    return value.map((key, value) => MapEntry(key.toString(), value));
  }

  String _headersToText(Map<String, dynamic> headers) {
    if (headers.isEmpty) return '';
    return jsonEncode(headers);
  }

  /// 🆕 构建登录配置（login.*）；needLogin 关闭或 API 未填 URL 时返回 null。
  PluginLoginConfig? _buildLoginConfig() {
    if (!needLogin) return null;
    final mode = loginMode;
    if (mode == 'xpath') {
      return PluginLoginConfig(
        mode: mode,
        accountXpath: loginAccountXpathCtrl.text.trim(),
        passwordXpath: loginPasswordXpathCtrl.text.trim(),
        submitXpath: loginSubmitXpathCtrl.text.trim(),
        successXpath: loginSuccessXpathCtrl.text.trim(),
      );
    }
    if (mode == 'api') {
      final url = loginApiUrlCtrl.text.trim();
      if (url.isEmpty) return null;
      Map<String, dynamic> headers;
      try {
        headers = _parseJsonMap(loginApiHeadersCtrl, '登录请求头');
      } catch (_) {
        headers = <String, dynamic>{};
      }
      final bodyText = loginApiBodyCtrl.text.trim();
      return PluginLoginConfig(
        mode: mode,
        api: ApiLoginConfig(
          request: ApiRequestConfig(
            method: loginApiMethodCtrl.text.trim().isEmpty
                ? 'POST'
                : loginApiMethodCtrl.text.trim(),
            url: url,
            headers: headers,
            bodyType: bodyText.isEmpty ? ApiBodyType.none : ApiBodyType.json,
            body: bodyText.isEmpty ? null : bodyText,
          ),
          accountField: loginApiAccountFieldCtrl.text.trim(),
          passwordField: loginApiPasswordFieldCtrl.text.trim(),
          tokenPath: loginApiTokenPathCtrl.text.trim(),
          cookiePath: loginApiCookiePathCtrl.text.trim(),
        ),
      );
    }
    return PluginLoginConfig(mode: mode);
  }

  /// 🆕 构建登录检查（check.*）；needLogin 关闭或 API 未填 URL 时返回 null。
  PluginCheckConfig? _buildCheckConfig() {
    if (!needLogin) return null;
    final cc = PluginCheckConfig(
      mode: checkMode,
      successStatus: int.tryParse(checkSuccessStatusCtrl.text.trim()) ?? 200,
      successCode: int.tryParse(checkSuccessCodeCtrl.text.trim()),
      tokenPlaceholder: checkTokenPlaceholderCtrl.text.trim().isEmpty
          ? '@token'
          : checkTokenPlaceholderCtrl.text.trim(),
      xpath: checkXpathCtrl.text.trim(),
    );
    if (checkMode == 'api') {
      final url = checkUrlCtrl.text.trim();
      if (url.isEmpty) return null;
      Map<String, dynamic> headers;
      try {
        headers = _parseJsonMap(checkHeadersCtrl, '检查请求头');
      } catch (_) {
        headers = <String, dynamic>{};
      }
      cc.request = ApiRequestConfig(
        method: checkMethodCtrl.text.trim().isEmpty
            ? 'GET'
            : checkMethodCtrl.text.trim(),
        url: url,
        headers: headers,
      );
    }
    return cc;
  }

  dynamic _parseBody(
    TextEditingController controller,
    String bodyType,
    String label,
  ) {
    if (bodyType == ApiBodyType.none) return null;
    final text = controller.text.trim();
    if (text.isEmpty) return <String, dynamic>{};
    final dynamic value;
    try {
      value = jsonDecode(text);
    } on FormatException catch (error) {
      throw FormatException('$label 不是有效 JSON：${error.message}');
    }
    if (bodyType == ApiBodyType.form && value is! Map) {
      throw FormatException('$label 在表单模式下必须是 JSON 对象');
    }
    return value;
  }

  void _showEditorError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error.toString())),
    );
  }
}
