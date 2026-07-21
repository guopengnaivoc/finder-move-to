#!/bin/bash
# 测试 build.py:生成 bundle 结构、plist 合法、注入的脚本与源一致
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
/usr/bin/python3 "$ROOT/build.py" || { echo "FAIL: 构建失败"; exit 1; }

C="$ROOT/build/移动到….workflow/Contents"
for f in "Info.plist" "document.wflow"; do
  [ -f "$C/$f" ] || { echo "FAIL: 缺少 $f"; exit 1; }
  plutil -lint "$C/$f" >/dev/null || { echo "FAIL: plist 非法 $f"; exit 1; }
done

# Info.plist 菜单名必须精确为「移动到…」
name=$(/usr/libexec/PlistBuddy -c "Print :NSServices:0:NSMenuItem:default" "$C/Info.plist")
[ "$name" = "移动到…" ] || { echo "FAIL: 菜单名不对: [$name]"; exit 1; }

# Info.plist 必须限定 Finder,并对文件/文件夹生效
appid=$(/usr/libexec/PlistBuddy -c "Print :NSServices:0:NSRequiredContext:NSApplicationIdentifier" "$C/Info.plist")
[ "$appid" = "com.apple.finder" ] || { echo "FAIL: 未限定 Finder: [$appid]"; exit 1; }
ftype=$(/usr/libexec/PlistBuddy -c "Print :NSServices:0:NSSendFileTypes:0" "$C/Info.plist")
[ "$ftype" = "public.item" ] || { echo "FAIL: NSSendFileTypes 不对: [$ftype]"; exit 1; }

# 注入的 AppleScript 必须与源文件一致
emb=$(/usr/libexec/PlistBuddy -c "Print :actions:0:action:ActionParameters:source" "$C/document.wflow")
src=$(cat "$ROOT/src/move_to.applescript")
[ "$emb" = "$src" ] || { echo "FAIL: 注入脚本与源不一致"; exit 1; }

echo "PASS"
