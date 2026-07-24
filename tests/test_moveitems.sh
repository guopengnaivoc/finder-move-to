#!/bin/bash
# v2 测试:纯 shell mv,不碰访达。覆盖 hasConflict / moveOne(move/skip/keepboth/replace) / uniqueName
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCPT="$ROOT/build/move_to.scpt"
mkdir -p "$ROOT/build"
osacompile -o "$SCPT" "$ROOT/src/move_to.applescript" || { echo "FAIL: 编译失败"; exit 1; }

# 关键约束:脚本绝不能指挥访达,也不能提权
grep -q 'tell application "Finder"' "$ROOT/src/move_to.applescript" && { echo "FAIL: 脚本仍在指挥访达(违反无权限约束)"; exit 1; }
grep -Eq 'administrator privileges|sudo' "$ROOT/src/move_to.applescript" && { echo "FAIL: 脚本含提权(会弹密码)"; exit 1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/src" "$work/dest" "$work/trash"
run() { osascript -e "set sc to load script (POSIX file \"$SCPT\")" -e "tell sc to $1"; }
DST="\"$work/dest/\""
TRASH="\"$work/trash/\""

# 1) 无冲突 + 普通移动(真移动:目标出现、源消失)
echo hello > "$work/src/a.txt"
hc=$(run "hasConflict(\"$work/src/a.txt\", $DST)")
[ "$hc" = "false" ] || { echo "FAIL: 无冲突应为 false, got $hc"; exit 1; }
run "moveOne(\"$work/src/a.txt\", $DST, \"move\", $TRASH)" >/dev/null
[ -f "$work/dest/a.txt" ] || { echo "FAIL: 普通移动未到目标"; exit 1; }
[ -e "$work/src/a.txt" ] && { echo "FAIL: 普通移动源仍在"; exit 1; }

# 2) 冲突检测
echo new > "$work/src/a.txt"; echo old > "$work/dest/a.txt"
hc=$(run "hasConflict(\"$work/src/a.txt\", $DST)")
[ "$hc" = "true" ] || { echo "FAIL: 有冲突应为 true, got $hc"; exit 1; }

# 3) 跳过:源与目标都不动
run "moveOne(\"$work/src/a.txt\", $DST, \"skip\", $TRASH)" >/dev/null
[ -e "$work/src/a.txt" ] || { echo "FAIL: skip 不应移走源"; exit 1; }
[ "$(cat "$work/dest/a.txt")" = "old" ] || { echo "FAIL: skip 不应改目标"; exit 1; }

# 4) 两者都保留:生成 'a 2.txt',原 dest/a.txt 保留,源移走
run "moveOne(\"$work/src/a.txt\", $DST, \"keepboth\", $TRASH)" >/dev/null
[ -f "$work/dest/a 2.txt" ] || { echo "FAIL: keepboth 应生成 'a 2.txt'"; exit 1; }
[ "$(cat "$work/dest/a 2.txt")" = "new" ] || { echo "FAIL: keepboth 新文件内容不对"; exit 1; }
[ "$(cat "$work/dest/a.txt")" = "old" ] || { echo "FAIL: keepboth 不应动原文件"; exit 1; }
[ -e "$work/src/a.txt" ] && { echo "FAIL: keepboth 源应已移走"; exit 1; }

# 5) 替换:目标变新内容,源移走,旧的进(临时)废纸篓可恢复
echo newer > "$work/src/a.txt"
run "moveOne(\"$work/src/a.txt\", $DST, \"replace\", $TRASH)" >/dev/null
[ "$(cat "$work/dest/a.txt")" = "newer" ] || { echo "FAIL: replace 应覆盖为新内容"; exit 1; }
[ -e "$work/src/a.txt" ] && { echo "FAIL: replace 源应已移走"; exit 1; }
[ "$(cat "$work/trash/a.txt")" = "old" ] || { echo "FAIL: replace 旧文件应进废纸篓(可恢复)"; exit 1; }

echo "PASS"
