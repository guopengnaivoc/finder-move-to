#!/bin/bash
# 构建并安装「移动到…」快速操作到 ~/Library/Services
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"

/usr/bin/python3 "$ROOT/build.py"

DEST_DIR="$HOME/Library/Services"
mkdir -p "$DEST_DIR"
rm -rf "$DEST_DIR/移动到….workflow"
cp -R "$ROOT/build/移动到….workflow" "$DEST_DIR/"

# 刷新服务缓存,让右键“快速操作”菜单立即识别
/System/Library/CoreServices/pbs -flush 2>/dev/null || true

echo "✅ 已安装:$DEST_DIR/移动到….workflow"
echo "用法:在 Finder 选中文件 → 右键 → 快速操作 → 移动到… → 选目标文件夹。"
echo "若右键未立即出现,重启 Finder:  killall Finder"
echo "或到 系统设置 → 键盘 → 键盘快捷键 → 服务 里确认「移动到…」已勾选。"
