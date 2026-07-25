#!/bin/bash
# 构建并安装快速操作到 ~/Library/Services
# 用法:  ./install.sh        # 中文版「移动到…」(默认)
#         ./install.sh en     # 英文版「Move To…」
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"

LANG_ARG="${1:-zh}"
case "$LANG_ARG" in
  en) BNAME="Move To…" ;;
  *)  LANG_ARG="zh"; BNAME="移动到…" ;;
esac

/usr/bin/python3 "$ROOT/build.py" "$LANG_ARG"

DEST_DIR="$HOME/Library/Services"
mkdir -p "$DEST_DIR"
rm -rf "$DEST_DIR/${BNAME}.workflow"
cp -R "$ROOT/build/${BNAME}.workflow" "$DEST_DIR/"

# 刷新服务缓存,让右键“快速操作”菜单立即识别
/System/Library/CoreServices/pbs -flush 2>/dev/null || true

echo "✅ 已安装:$DEST_DIR/${BNAME}.workflow"
echo "用法:在 Finder 选中文件 → 右键 → 快速操作 → ${BNAME} → 选目标文件夹。"
echo "若右键未立即出现,重启 Finder:  killall Finder"
