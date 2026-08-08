# Animeko 规则适配 Kazumi 改造说明

## 概述

本改造为 Kazumi（mp）添加了对 **Animeko web-selector 规则**的原生支持。
使得 Kazumi 能够直接加载和执行 Animeko 导出的 `exportedMediaSourceDataList` JSON 格式的规则。

## 核心架构

```
Animeko JSON Rule
       │
       ▼
AnimekoRuleConverter (转换器)
       │
       ▼
Kazumi Plugin (searchMode/chapterMode = "css", animekoConfig={...})
       │
       ▼
RuleEngine (规则引擎)
       │
       ├── CSS mode? ──► CssRuleStrategy (CSS选择器 + 正则)
       │
       ├── XPath mode? ──► XPathRuleStrategy (XPath选择器)
       │
       └── API mode? ──► ApiRuleStrategy (JSONPath)
```

## 新增文件

| 文件 | 作用 |
|------|------|
| `lib/plugins/animeko_rule_config.dart` | Animeko web-selector 规则的完整数据模型（含所有 Selector、Channel、Video 配置类） |
| `lib/plugins/animeko_converter.dart` | 转换器：将 Animeko JSON → Kazumi Plugin 对象 |
| `lib/services/plugin/css_rule_strategy.dart` | CSS 规则引擎：用 CSS 选择器解析 HTML，提取搜索、章节、视频地址 |

## 修改文件

| 文件 | 修改内容 |
|------|---------|
| `lib/plugins/api_rule_config.dart` | `RuleMode` 新增 `css` 常量 |
| `lib/plugins/plugins.dart` | `Plugin` 类新增 `animekoConfig` 字段，序列化/反序列化支持，`buildHttpHeaders()` 和 `extractVideoUrlFromPage()` 方法 |
| `lib/services/plugin/rule_engine_models.dart` | `RuleExecutionConfig` 新增 `animekoConfig` 字段 |
| `lib/services/plugin/rule_engine.dart` | `RuleEngine` 新增 `CssRuleStrategy` 支持，搜索/章节请求根据 mode 分发到 CSS 策略 |

## 支持的特性

### ✅ 已支持
- **CSS 选择器**：使用 `package:html` 的 `querySelectorAll` 解析搜索结果
- **多格式搜索**：
  - `subjectFormatId: "a"` → 直接取 `<a>` 标签（文本+href）
  - `subjectFormatId: "indexed"` → 分别用 `selectNames` 和 `selectLinks` 两个选择器
- **多线路分集解析**：
  - `channelFormatId: "index-grouped"` → 频道标签 + 分集列表对应
  - `channelFormatNoChannel` → 无频道模式
- **正则提取集号**：`matchEpisodeSortFromName` 从文本中提取"第X集"
- **视频地址正则提取**：`matchVideoUrl` 从播放页 HTML 中提取视频直链
- **验证码检测占位**：通过 `AntiCrawlerConfig` 机制（已有）
- **自定义请求头/Cookie**：从 `matchVideo.addHeadersToVideo` 和 `cookies` 构建

### ⚠️ 部分支持（需进一步开发）
- **嵌套 URL 解析**：`matchNestedUrl` / `enableNestedUrl` 的逻辑已实现基础框架
- **请求间隔**：`requestInterval` 需要配合请求调度器
- **多条搜索词**：`searchUseSubjectNamesCount` 需要额外的搜索策略

### ❌ 暂不支持
- **RSS 源**（`factoryId: "rss"`）：Kazumi 已有自己的 RSS 处理逻辑，需要单独适配
- **WebView 验证码绕过**：需依赖 Kazumi 已有的 `CaptchaVerificationService`

## 使用方法

### 方式一：在 Kazumi 代码中直接导入

```dart
import 'package:kazumi/plugins/animeko_converter.dart';

// 读取 Animeko JSON 文件
final jsonString = await File('animeko_rules.json').readAsString();

// 转换为 Kazumi Plugin 列表
final plugins = AnimekoRuleConverter.convertFromJson(jsonString);

// 添加到 PluginsController
for (final plugin in plugins) {
  pluginsController.pluginList.add(plugin);
}
await pluginsController.savePlugins();
```

### 方式二：使用独立转换脚本

```bash
cd converter_tool/
dart run convert_animeko_rules.dart ./animeko_input.json ./output.json
```

### 方式三：直接加载 Animeko 规则文件

将转换后的 JSON 放到 Kazumi 的插件目录：
- Android: `{应用支持目录}/plugins/v2/plugins.json`
- 或者在 `assets/plugins/` 目录下以 JSON 文件形式打包

## 数据流详解

### 搜索流程

```
用户输入关键词
       │
       ▼
Plugin.searchURL 替换 {keyword}
       │
       ▼
HTTP GET → 搜索结果 HTML
       │
       ▼
CssRuleStrategy.parseSearch()
  ├─ subjectFormatId == "a"
  │   └─ root.querySelectorAll(selectorSubjectFormatA.selectLists)
  │       → 取每个 <a>.text 和 <a>.href
  │
  └─ subjectFormatId == "indexed"
      └─ root.querySelectorAll(selectNames) + root.querySelectorAll(selectLinks)
          → 配对取 name 和 href
        
       ▼
返回 List<SearchItem> (name + src)
```

### 分集流程

```
选择某番剧 → 访问详情页 HTML
       │
       ▼
CssRuleStrategy.parseChapters()
  ├─ channelFormatId == "index-grouped"
  │   1. querySelectorAll(selectChannelNames) → 频道名列表
  │   2. querySelectorAll(selectEpisodeLists) → 分集容器列表
  │   3. 按 index 匹配，在每个容器内 querySelectorAll(selectEpisodesFromList)
  │   4. 正则提取 "第X集" → 生成 Road 列表
  │
  └─ channelFormatNoChannel
      1. querySelectorAll(selectEpisodes) + querySelectorAll(selectEpisodeLinks)
      2. 配对提取
      3. 生成单 Road
       
       ▼
返回 List<Road> (name + data[] + identifier[])
```

### 视频解析流程

```
点击某集播放
       │
       ▼
访问该集播放页 HTML
       │
       ▼
正则匹配 matchVideoUrl → 提取视频直链
  如果 enableNestedUrl:
    先正则 matchNestedUrl → 获取嵌套页 URL
    → 再访问嵌套页 → 正则 matchVideoUrl → 提取视频直链
       │
       ▼
返回视频 URL (mp4/m3u8) 给播放器
```

## 与原生 Animeko 的差异

| 特性 | Animeko | Kazumi 改造版 |
|------|---------|---------------|
| 选择器引擎 | CSS 选择器（内置） | CSS 选择器（`package:html`） |
| 视频提取 | matchVideo 正则 | matchVideo 正则 + WebView 回退 |
| RSS 源 | 原生支持 | 需单独转换（使用 Kazumi 已有机制） |
| 验证码 | 内置处理 | 使用 Kazumi 的 CaptchaVerificationService |
| 多源调度 | tier 优先级 | 通过 Plugin 列表顺序控制 |
| 视频解析 | 正则 + 嵌套 | 正则 + 嵌套 + WebView 回退 |

## 构建提示

如果出现 `package:html` 相关错误，确保 `pubspec.yaml` 中已包含：

```yaml
dependencies:
  html: any
```

（从 Kazumi 的 `xpath_rule_strategy.dart` 可以看到，`html` 包已经是依赖项，无需额外添加）
