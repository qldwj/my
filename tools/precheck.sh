#!/usr/bin/env bash
# 打包前本地预检：提前发现会导致 GitHub Actions 构建失败的语法/分析错误
#
# 用法：  bash tools/precheck.sh
# 退出码：0 = 通过（可以打包）；非 0 = 有问题（先修再打包）

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

echo "=============================================="
echo " 樱花动漫 打包前预检"
echo "=============================================="

fail=0

# 1) 依赖是否装好
if [ ! -f .dart_tool/package_config.json ]; then
  echo "[1/3] 警告：还没执行 flutter pub get，先跑：flutter pub get"
  echo "      （不跑的话下面的分析会大量误报）"
  fail=1
else
  echo "[1/3] 依赖已安装（.dart_tool/package_config.json）"
fi

# 2) 正式分析（只把 error 当问题，warning/info 忽略）
echo "[2/3] 运行 flutter analyze（只看 error）..."
if command -v flutter >/dev/null 2>&1; then
  out=$(flutter analyze --no-fatal-infos --no-fatal-warnings 2>&1)
  errs=$(printf '%s\n' "$out" | grep -E "^[[:space:]]*error[[:space:]]" || true)
  if [ -n "$errs" ]; then
    echo "发现编译错误："
    printf '%s\n' "$errs" | head -50
    fail=1
  else
    echo "没有编译错误"
  fi
else
  echo "未找到 flutter 命令，跳过 analyze"
fi

# 3) 关键资源/依赖存在性检查
echo "[3/3] 检查关键文件..."
for f in \
  "lib/main.dart" \
  "pubspec.yaml" \
  "lib/services/network/bangumi_ech_image_service.dart" \
  "lib/services/network/image_file_service.dart" \
  "lib/services/sync/webdav.dart" \
  "lib/pages/settings/sync/sync_settings_page.dart"
do
  if [ -f "$f" ]; then
    echo "  OK  $f"
  else
    echo "  缺失：$f"
    fail=1
  fi
done

# ech_http 原生依赖声明（缺了会构建失败）
if grep -q "ech_http" pubspec.yaml; then
  echo "  OK  ech_http 依赖已声明"
else
  echo "  错误 pubspec.yaml 缺少 ech_http 依赖"
  fail=1
fi

echo "=============================================="
if [ "$fail" -eq 0 ]; then
  echo " 预检通过，可以打包"
  exit 0
else
  echo " 预检未通过，请先修复上面的问题再打包"
  exit 1
fi
