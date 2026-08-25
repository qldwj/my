# 更新公告

## v2.3.5 (2030050)

### 新增功能
- **Bangumi 登录 UI 重做**：模仿 Animeko 简洁风格，点击按钮跳转浏览器授权，无需手动粘贴 Token
- **HLS 伪装流嗅探**：自动识别 `.webp`/`.png` 等伪装后缀的 HLS 流（如次元城动画），强制 HLS 解复用播放
- **网页版分享链接深链适配**：支持 `qlyyz.xyz/yhdm/detail.html?id=xxx` 格式，自动跳转详情页
- **弹幕集数修复**：解决列表倒序时弹幕指向错误集数的问题
- **Android 后台暂停预取**（官方 2.2.9）：防止后台切换返回后播放卡死
- **Material 3 UI 改进**（官方 2.2.9）：源选择列表、设置页面视觉优化
- **一起看面板**（官方 2.2.9）：Syncplay 功能入口

### 合并官方 2.2.8 → 2.2.9 更新
- Android 后台暂停预取（防止后台播放卡死）
- Material 3 outlined text fields
- PIP rect 缓存改进
- 源选择 UI 重设计
- 日志精简（去除 verbose stacktrace）
- Flutter 3.47.0 → 3.47.1

### 修复
- HLS 嗅探 Range 请求不稳定（改用流式读取前 1KB）
- 弹幕集数 fallback 使用 1-based（listIndex+1）
- 搜索失败日志过于冗长（去除 stacktrace 输出）
- 登录页面路由路径修正

### 构建
- 包名改为 `com.predidit.YHDM`
- 版本号动态同步（构建时自动更新 api_endpoints.dart + pubspec.yaml）
- 新 Logo 图片
- 新增 `flutter_launcher_icons` 构建步骤（自动重生成图标）

---

## v2.3.4 (2030040)
- 初始版本
