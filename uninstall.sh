#!/bin/bash
# 卸载快速操作(中文「移动到…」和英文「Move To…」两个版本都会被移除)
set -euo pipefail
DEST_DIR="$HOME/Library/Services"
removed=0
for BNAME in "移动到…" "Move To…"; do
  TARGET="$DEST_DIR/${BNAME}.workflow"
  if [ -d "$TARGET" ]; then
    rm -rf "$TARGET"
    echo "✅ 已卸载:$TARGET"
    removed=1
  fi
done
if [ "$removed" = "1" ]; then
  /System/Library/CoreServices/pbs -flush 2>/dev/null || true
else
  echo "未发现已安装的「移动到…」/「Move To…」,无需卸载。"
fi
