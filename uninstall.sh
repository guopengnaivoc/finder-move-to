#!/bin/bash
# 卸载「移动到…」快速操作
set -euo pipefail
TARGET="$HOME/Library/Services/移动到….workflow"
if [ -d "$TARGET" ]; then
  rm -rf "$TARGET"
  /System/Library/CoreServices/pbs -flush 2>/dev/null || true
  echo "✅ 已卸载:$TARGET"
else
  echo "未发现已安装的「移动到…」,无需卸载。"
fi
