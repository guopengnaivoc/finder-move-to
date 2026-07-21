#!/bin/bash
# 测试 move_to.applescript 的 moveItems 处理器:真移动 + 冲突返回失败
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCPT="$ROOT/build/move_to.scpt"
mkdir -p "$ROOT/build"
osacompile -o "$SCPT" "$ROOT/src/move_to.applescript" || { echo "FAIL: 编译失败"; exit 1; }

work="$(mktemp -d)"
mkdir -p "$work/src" "$work/dest"
echo hello > "$work/src/a.txt"

# 1) 正常移动:目标出现、源消失、无失败信息
out=$(osascript -e "set sc to load script (POSIX file \"$SCPT\")" \
               -e "tell sc to moveItems({\"$work/src/a.txt\"}, (POSIX file \"$work/dest\") as alias)")
[ -f "$work/dest/a.txt" ] || { echo "FAIL: 未移动到目标"; rm -rf "$work"; exit 1; }
[ -e "$work/src/a.txt" ] && { echo "FAIL: 源仍存在(是复制不是移动)"; rm -rf "$work"; exit 1; }
[ -z "$out" ] || { echo "FAIL: 预期无失败,实际: $out"; rm -rf "$work"; exit 1; }

# 2) 同名冲突:应返回非空失败信息,且不破坏已有文件
echo world > "$work/dest/b.txt"
echo again > "$work/src/b.txt"
out2=$(osascript -e "set sc to load script (POSIX file \"$SCPT\")" \
                -e "tell sc to moveItems({\"$work/src/b.txt\"}, (POSIX file \"$work/dest\") as alias)")
[ -n "$out2" ] || { echo "FAIL: 同名冲突应返回失败信息"; rm -rf "$work"; exit 1; }

echo "PASS"
rm -rf "$work"
