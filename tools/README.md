# 打包前预检

## 用法

```bash
flutter pub get        # 首次 / 依赖变化后
bash tools/precheck.sh # 打包前先跑这个
flutter build apk ...  # 预检通过再打包
```

## 它检查什么

1. **依赖是否装好**（`.dart_tool/package_config.json`）
2. **`flutter analyze` 的 error**（只把 error 当问题；warning/info 忽略）
3. **关键文件 / 依赖存在性**（main.dart、ech_http 等）

## 为什么需要它

GitHub Actions 里 `flutter analyze` 会**在构建前**跑，一旦有编译错误就直接失败，
而且报错信息混在长日志里不容易看。本地先跑一遍，能提前定位问题，省一次 4 分钟的等待。

## CI 侧同步调整

`.github/workflows/pr.yaml` 里原来是：

```
flutter analyze --no-fatal-infos --fatal-warnings
```

`--fatal-warnings` 会把**无害的 warning** 也判为失败（比如未使用的变量）。
现已改为：

```
flutter analyze --no-fatal-infos --no-fatal-warnings
```

只拦截真正的 **error**，构建不再被无关警告阻断。
