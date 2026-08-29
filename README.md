# Kazumi（项目整体说明）

> 本项目是 **整体全局** 的动漫观看应用，基于 Kazumi 官方项目构建。
> 与官方 Kazumi 完全对齐：数据结构、接口路由、功能集均与官方一致，仅在自有后端体系上做了一层镜像代理与增量整合。

## 项目定位

- **客户端**：Flutter 全平台（Android / Windows / Linux / macOS / iOS），与官方 Kazumi 同构；
- **数据层**：Bangumi 条目数据。镜像路由完全照搬官方 `api.kazumi.fyi`，官方路由不可用时自动回退 `api.bgm.tv`；
- **服务层**：`qlyyz.xyz` 提供规则仓库、弹幕、应用升级、社交（好友/聊天）、评论后台等一体化接口；
- **一致性**：表情、关联作品、榜单、时间表等模块与官方 Kazumi 行为对齐，所有流量可收敛到自有域名。

## 核心功能

- 📺 **番剧播放**：多规则源聚合，支持 InvalidSource 错误友好提示；
- 💬 **弹幕**：自建弹幕接口，支持手动检索、透明度与倍速时长设置；
- 🧩 **规则插件**：支持批量导入（`plugin_import_parser`），规则仓库与镜像可切换；
- ✍️ **评论系统**：BBCode 工具栏 + BGM 表情本地渲染（`assets/bgm_stickers`，`(bgmN)` 内联表情）；
- 🔗 **关联作品**：基于 Bangumi `GET /v0/subjects/{id}/subjects` 的真实关联条目（续集/前传/衍生），镜像开启时走官方路由，失败自动回退关键词搜索；
- ⬇️ **离线下载**：下载选集自动定位到当前播放集；
- 📱 **系统集成**：Android 媒体控制修复、收藏页分 Tab 计数、桌面端适配。

## 镜像与后端

| 用途 | 地址 | 说明 |
| --- | --- | --- |
| Bangumi 镜像 | `https://api.kazumi.fyi` | 官方路由，与官方 Kazumi 完全一致 |
| Bangumi 直连 | `https://api.bgm.tv` | 镜像关闭时使用 |
| 规则仓库 | `https://qlyyz.xyz/api/rules/` | 规则镜像 |
| 弹幕 | `https://qlyyz.xyz/api/danmaku.php` | 自建弹幕 |
| 评论后台 | `qlyyz.xyz/api/episode_comment.php` | 评论 / 表情回应 / 举报 |

## 目录结构

```
lib/
├── bean/            # 通用组件（卡片、弹窗、错误页等）
├── modules/         # 数据模型（BangumiItem、SubjectRelation 等）
├── pages/           # 页面（info / player / collect / settings ...）
├── plugins/         # 规则插件体系与批量导入
├── request/         # 网络层（api_endpoints / bangumi_api 等）
├── services/        # 业务服务（弹幕、评论、镜像、通知等）
└── utils/           # 工具（BgmSticker 表情映射、NSFW 过滤等）
```

## 版本

当前版本：**2.3.5**（对齐官方 Kazumi v2.3.0 功能集）。

## 致谢

- [Kazumi](https://github.com/Predidit/Kazumi) —— 上游项目
- [Bangumi](https://bangumi.tv/) —— 条目数据来源
- 弹弹play —— 弹幕数据支持