#!/bin/bash
# 测试 move_to.applescript 的核心处理器:
#   toAlias/moveOne 真移动、hasConflict 冲突检测、以及三种冲突处理(替换/两者都保留/跳过)
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCPT="$ROOT/build/move_to.scpt"
mkdir -p "$ROOT/build"
osacompile -o "$SCPT" "$ROOT/src/move_to.applescript" || { echo "FAIL: 编译失败"; exit 1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/src" "$work/dest"

# 调用脚本里的某个处理器
run() { osascript -e "set sc to load script (POSIX file \"$SCPT\")" -e "tell sc to $1"; }
SRC() { echo "(POSIX file \"$work/src/$1\") as alias"; }
DST="(POSIX file \"$work/dest\") as alias"

# 1) 无冲突检测 + 普通移动(真移动:目标出现、源消失)
echo hello > "$work/src/a.txt"
hc=$(run "hasConflict($(SRC a.txt), $DST)")
[ "$hc" = "false" ] || { echo "FAIL: 无冲突应为 false, 实际 $hc"; exit 1; }
run "moveOne($(SRC a.txt), $DST, \"move\")" >/dev/null
[ -f "$work/dest/a.txt" ] || { echo "FAIL: 普通移动未到目标"; exit 1; }
[ -e "$work/src/a.txt" ] && { echo "FAIL: 普通移动源仍在(复制非移动)"; exit 1; }

# 2) 有冲突检测
echo new > "$work/src/a.txt"; echo old > "$work/dest/a.txt"
hc=$(run "hasConflict($(SRC a.txt), $DST)")
[ "$hc" = "true" ] || { echo "FAIL: 有冲突应为 true, 实际 $hc"; exit 1; }

# 3) 跳过:源和目标都不动
run "moveOne($(SRC a.txt), $DST, \"skip\")" >/dev/null
[ -e "$work/src/a.txt" ] || { echo "FAIL: skip 不应移走源"; exit 1; }
[ "$(cat "$work/dest/a.txt")" = "old" ] || { echo "FAIL: skip 不应改动目标"; exit 1; }

# 4) 两者都保留:生成 "a 2.txt",原 dest/a.txt 保留,源移走
run "moveOne($(SRC a.txt), $DST, \"keepboth\")" >/dev/null
[ -f "$work/dest/a 2.txt" ] || { echo "FAIL: keepboth 应生成 'a 2.txt'"; exit 1; }
[ "$(cat "$work/dest/a 2.txt")" = "new" ] || { echo "FAIL: keepboth 新文件内容不对"; exit 1; }
[ "$(cat "$work/dest/a.txt")" = "old" ] || { echo "FAIL: keepboth 不应动原文件"; exit 1; }
[ -e "$work/src/a.txt" ] && { echo "FAIL: keepboth 源应已移走"; exit 1; }

# 5) 替换:dest/a.txt 变成新内容,源移走(旧的进废纸篓)
echo newer > "$work/src/a.txt"
run "moveOne($(SRC a.txt), $DST, \"replace\")" >/dev/null
[ "$(cat "$work/dest/a.txt")" = "newer" ] || { echo "FAIL: replace 应覆盖为新内容"; exit 1; }
[ -e "$work/src/a.txt" ] && { echo "FAIL: replace 源应已移走"; exit 1; }

echo "PASS"
