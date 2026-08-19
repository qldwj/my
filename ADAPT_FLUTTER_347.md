# Kazumi (YHDM) 适配 Flutter 3.47 说明

适配时间：2026-08-19
适配前环境：Flutter 3.44.7 / Dart 3.11（pubspec.lock: dart >=3.11.0, flutter >=3.44.7）
适配目标：Flutter 3.47.x / Dart 3.12+

## 一、本次已完成的修改

### 1. pubspec.yaml — 版本约束
```yaml
environment:
  sdk: ">=3.12.0 <4.0.0"        # 原: ">=3.3.4 <4.0.0"（Flutter 3.47 对应 Dart 3.12+）
  flutter: ">=3.47.0 <3.48.0"   # 原: 3.44.7
```

### 2. lib/utils/constants.dart — 移除已删除的 Material 兼容开关
- `ProgressIndicatorThemeData(year2023: false)` → `ProgressIndicatorThemeData()`
  （`year2023` 参数自 Flutter 3.24 弃用，3.44+ 已移除，保留会编译失败）
- `SliderThemeData(year2023: false, ...)` → `SliderThemeData(showValueIndicator: ...,)`
- 同时删除了对应的 `// ignore: deprecated_member_use` 注释

### 3. lib/pages/settings/theme_settings_page.dart — Color.value 迁移
- `e['color'].value.toRadixString(16)` → `e['color'].toARGB32().toRadixString(16)`
  （`Color.value` 已弃用并移除，新 API 为 `toARGB32()`，行为一致）

### 4. withOpacity → withValues(alpha:) 批量替换（5 个文件 7 处）
`Color.withOpacity()` 自 Flutter 3.27 弃用、后续版本移除，已全部替换为等价 API：
| 文件 | 修改 |
|------|------|
| lib/pages/collect/collect_folder_page.dart | 1 处 |
| lib/pages/my/chat_room_page.dart | 4 处 |
| lib/pages/my/feedback_page.dart | 1 处 |
| lib/pages/my/qrcode_login_page.dart | 1 处 |

### 5. 检查确认无需改动的项
- ✅ `Color.value` 残留：已全部清理（其余 `.value` 均为 Map/枚举字段）
- ✅ `WillPopScope` / `RawKeyboard` / `surfaceVariant` / `MaterialState*`：项目未使用
- ✅ `textScaleFactor`：仅自定义函数参数名，非 API 调用
- ✅ `useMaterial3`、`colorSchemeSeed`、`MenuAnchor`、`PopScope` 等：新版 API 已在使用
- ✅ `material_color_utilities`：pubspec 已有 `any` 依赖，palette_card.dart 正常
- ✅ Android 配置（AGP 8.11.1 / Gradle 8.14.5 / Kotlin 2.2.21 / NDK 28.2 / compileSdk 跟随 flutter）：已是较新版本，与 3.47 兼容
- ✅ iOS deployment target 13.0、Podfile：无需改动
- ✅ `android.newDsl=false` / `android.builtInKotlin=false` 迁移标志：保留（如 3.47 提示迁移到新 DSL，见下文备用方案）

## 二、用户侧需要执行的操作

```bash
cd mp
flutter pub get        # 重新解析依赖，更新 pubspec.lock
flutter analyze        # 检查是否还有剩余告警/错误
flutter run            # 或直接构建
```

> 注意：本次改动未更新 pubspec.lock（需在目标 Flutter 3.47 环境执行 pub get 自动更新）。
> `.metadata` 中的 Flutter revision 也由 flutter 工具自动更新。

## 三、备用方案（若 Flutter 3.47 强制新 Android DSL）

如果构建报错提示迁移 Android 新 DSL，需修改：

1. `android/gradle.properties`：删除以下两行
   ```
   android.builtInKotlin=false
   android.newDsl=false
   ```
2. `android/app/build.gradle`：`kotlinOptions { jvmTarget = '17' }` 替换为
   ```groovy
   kotlin {
       compilerOptions {
           jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
       }
   }
   ```
3. 或直接运行 `flutter migrate` 让工具自动迁移。

## 四、其他说明
- `assets/plugins/7sefun.json` 的差异（v1.2→v1.3）为压缩包自带内容，非本次适配修改。
- pubspec.yaml 中 version 2.3.4+2030040 同为压缩包自带。
- 本适配未改动任何业务逻辑，仅处理 API 兼容性。
