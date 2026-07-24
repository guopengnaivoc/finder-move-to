# 「移动到…」v2 无权限打扰版 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把「移动到…」快速操作的内部搬运从"指挥访达"改为"底层 `mv` 命令",消灭"控制访达"授权与密码/指纹打扰,同时保留右键顶层显示与同名冲突三选(替换/两者都保留/跳过)。

**Architecture:** 仅重写 `src/move_to.applescript` 的内部实现:全程用 `do shell script` 的 `mv`/`test`/`basename` 搬运与判断,**不含任何 `tell application "Finder"`**,因此运行时不发 Apple Events、不需自动化授权;不使用管理员权限,失败时给文字提示而非弹密码。`build.py`(含 `presentationMode=15` 使其顶层显示)、`install.sh`、`uninstall.sh` 不变。

**Tech Stack:** AppleScript(`choose folder`、`display dialog`、`do shell script`)、macOS Automator 快速操作 bundle、Python 3 `plistlib`、bash 测试。

## Global Constraints

- 目标系统:macOS 26.5.2、Apple Silicon(arm64)、系统语言简体中文。
- `src/move_to.applescript` **绝不能包含** `tell application "Finder"`(由测试强制校验)。
- **绝不能包含** `with administrator privileges` 或 `sudo`(不弹密码/指纹)。
- 右键菜单项名称精确为 `移动到…`(结尾为省略号字符 `…` = U+2026,非三个点)。
- 搬运只用 `/bin/mv`;"替换"选项把旧项移入废纸篓(可恢复),废纸篓目录由 `moveOne` 的 `trashDir` 参数传入,`on run` 用 `$HOME/.Trash/`。
- 冲突三选按钮文案精确为:`替换`、`两者都保留`、`跳过`。
- 只用系统自带工具(`osacompile`/`osascript`、`/usr/bin/python3` 仅标准库、`/bin/mv`、`/bin/test`、`/usr/bin/basename`);无第三方软件、无 pip。
- `build.py` 保持不变(已含 `presentationMode=15`、`NSIconName` 等顶层显示元数据)。

---

## File Structure

```
finder-move-to/
  src/move_to.applescript   # (重写)纯 shell 搬运,不碰访达;GUI 外壳 + 可测试处理器
  tests/test_moveitems.sh   # (重写)对 hasConflict/moveOne/uniqueName 的自成体系测试
  tests/test_build.sh       # (不变)构建产物结构/合法性/注入一致
  build.py                  # (不变)注入脚本生成快速操作 bundle
  install.sh / uninstall.sh # (不变)
  README.md                 # (更新)v2 说明:无权限打扰、底层 mv
```

---

## Task 1: 重写 move_to.applescript 为纯 shell 搬运(TDD)

**Files:**
- Modify(整体重写): `src/move_to.applescript`
- Modify(整体重写): `tests/test_moveitems.sh`

**Interfaces:**
- Produces(供测试与 `on run` 调用):
  - `hasConflict(srcPosix, destDir)` → boolean(`destDir` 以 `/` 结尾)
  - `uniqueName(dir, name)` → text(在 `dir` 下不冲突的新名字,如 `a 2.txt`)
  - `moveOne(srcPosix, destDir, choice, trashDir)` → text(成功/跳过返回 `""`,失败返回错误文本);`choice ∈ {"move","replace","keepboth","skip"}`
  - `on run {input, parameters}` → 服务入口(GUI,人工验收)

- [ ] **Step 1: 写失败测试** — 用下面内容**整体覆盖** `tests/test_moveitems.sh`

```bash
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
```

- [ ] **Step 2: 运行测试确认失败**

Run: `chmod +x tests/test_moveitems.sh && ./tests/test_moveitems.sh`
Expected: FAIL —— 因为 `src/move_to.applescript` 仍是 v1(含 `tell application "Finder"`),会命中 grep 校验报 "脚本仍在指挥访达"(或旧处理器名不匹配)。

- [ ] **Step 3: 整体重写** `src/move_to.applescript` 为下面内容

```applescript
-- 移动到… Quick Action(v2:纯 shell 搬运,不碰访达,不提权)
-- 选中项移动到用户选择的文件夹;目标存在同名项时弹框三选:替换 / 两者都保留 / 跳过。
-- 搬运/删除全部走 do shell script 的 mv/test/basename,不发送任何 Apple Events 给访达。

on run {input, parameters}
	if input is {} then return input
	try
		set destFolder to (choose folder with prompt "移动到哪个文件夹?")
	on error number -128
		return input
	end try
	set dd to my destDir(destFolder)
	set trashDir to (do shell script "echo $HOME/.Trash/")
	set failed to {}
	repeat with anItem in input
		set srcPosix to my toPosix(anItem)
		set choice to "move"
		if my hasConflict(srcPosix, dd) then
			set nm to my baseName(srcPosix)
			try
				set btn to button returned of (display dialog "目标文件夹已存在同名项:" & return & nm & return & return & "请选择处理方式:" buttons {"跳过", "两者都保留", "替换"} default button "两者都保留" with icon caution)
			on error number -128
				set btn to "跳过"
			end try
			if btn is "替换" then
				set choice to "replace"
			else if btn is "两者都保留" then
				set choice to "keepboth"
			else
				set choice to "skip"
			end if
		end if
		set em to my moveOne(srcPosix, dd, choice, trashDir)
		if em is not "" then set end of failed to em
	end repeat
	if (count of failed) > 0 then
		set AppleScript's text item delimiters to return
		set report to (failed as text)
		set AppleScript's text item delimiters to ""
		display dialog "有 " & (count of failed) & " 项移动失败:" & return & report buttons {"好"} default button "好" with icon caution
	end if
	return input
end run

-- 把输入项(Finder 传入的 alias,或 POSIX 路径文本)统一成 POSIX 路径文本
on toPosix(anItem)
	if class of anItem is text then
		return POSIX path of ((POSIX file anItem) as alias)
	else
		return POSIX path of (anItem as alias)
	end if
end toPosix

-- 目标文件夹 POSIX 路径(确保以 / 结尾)
on destDir(destFolder)
	set p to POSIX path of destFolder
	if p does not end with "/" then set p to p & "/"
	return p
end destDir

-- 项目名(文件或文件夹)
on baseName(srcPosix)
	return do shell script "/usr/bin/basename " & quoted form of srcPosix
end baseName

-- 目标里是否已存在同名项
on hasConflict(srcPosix, dd)
	set target to dd & my baseName(srcPosix)
	try
		do shell script "/bin/test -e " & quoted form of target
		return true
	on error
		return false
	end try
end hasConflict

-- 执行单项移动。choice: "move" | "replace" | "keepboth" | "skip"
-- 成功或跳过返回 "";失败返回错误信息文本。绝不弹密码:失败即返回错误由上层汇总提示。
on moveOne(srcPosix, dd, choice, trashDir)
	if choice is "skip" then return ""
	try
		set nm to my baseName(srcPosix)
		if choice is "replace" then
			-- 旧的先移入废纸篓(可恢复),再把新的移入
			set trashTarget to trashDir & my uniqueName(trashDir, nm)
			do shell script "/bin/mv " & quoted form of (dd & nm) & " " & quoted form of trashTarget
			do shell script "/bin/mv " & quoted form of srcPosix & " " & quoted form of (dd & nm)
		else if choice is "keepboth" then
			set newName to my uniqueName(dd, nm)
			do shell script "/bin/mv -n " & quoted form of srcPosix & " " & quoted form of (dd & newName)
		else
			do shell script "/bin/mv " & quoted form of srcPosix & " " & quoted form of (dd & nm)
		end if
		return ""
	on error errMsg
		return errMsg
	end try
end moveOne

-- 在目录 dir 下为 name 生成不冲突的新名字,如 "foo 2.txt"、"foo 3.txt"
on uniqueName(dir, name)
	set {base, ext} to my splitExt(name)
	set i to 2
	repeat
		if ext is "" then
			set candidate to base & " " & (i as text)
		else
			set candidate to base & " " & (i as text) & "." & ext
		end if
		try
			do shell script "/bin/test -e " & quoted form of (dir & candidate)
			set i to i + 1
		on error
			return candidate
		end try
	end repeat
end uniqueName

-- 把名字拆成 {主名, 扩展名};无扩展名则扩展名为 ""
on splitExt(fname)
	if fname contains "." then
		set AppleScript's text item delimiters to "."
		set parts to text items of fname
		set ext to last item of parts
		set base to (items 1 thru -2 of parts) as text
		set AppleScript's text item delimiters to ""
		return {base, ext}
	else
		return {fname, ""}
	end if
end splitExt
```

- [ ] **Step 4: 运行测试确认通过**

Run: `./tests/test_moveitems.sh`
Expected: PASS。

- [ ] **Step 5: 确认构建仍正常(build.py 注入新脚本)**

Run: `./tests/test_build.sh`
Expected: PASS(`Built: …移动到….workflow` 后 `PASS`)。

- [ ] **Step 6: 提交**

```bash
git add src/move_to.applescript tests/test_moveitems.sh
git commit -m "feat(v2): 纯 shell mv 搬运,不碰访达(消灭控制访达授权与密码打扰)"
```

---

## Task 2: 更新 README 为 v2

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: Task 1 的行为(纯 shell、无权限打扰)。

- [ ] **Step 1: 用下面内容整体覆盖 `README.md`**

````markdown
# 移动到… — Finder 右键「移动到」快速操作

给 macOS 访达(Finder)的右键菜单加一个 **「移动到…」** 快速操作:选中文件/文件夹 → 右键(触控板双指按压亦可)→ **移动到…** → 弹框选目标文件夹 → **直接移动过去**(真移动,不是复制副本)。

- 🍎 **纯 macOS 原生**:只用系统自带能力,**零第三方软件**。
- 🔝 **右键顶层显示**:出现在右键「快速操作」区,文件和文件夹都在。
- 🔁 **同名冲突三选**:目标已有同名项时弹框选 **替换 / 两者都保留 / 跳过**。
- 🔓 **不打扰权限**:搬文件走系统底层命令、**不指挥访达、不用管理员权限** → 不弹"控制访达"授权、不弹密码/指纹。
- ⚡ **开机即用**:装一次后是常驻菜单项,重启、关机再开都在,无后台进程。

## 环境要求

macOS(在 macOS 26 / Apple Silicon 上验证)。只用系统自带的 `python3` / `osascript` / `Automator`,无需额外安装。

## 安装

```bash
./install.sh
```

安装后如右键里没立刻出现,重启访达即可:`killall Finder`。

## 使用

1. 在访达里选中一个或多个文件/文件夹。
2. 右键(或双指按压)→ 在「快速操作」区点 **移动到…**。
3. 在弹出的文件夹选择框里选目标文件夹。
4. 选中项被**移动**过去。

### 同名冲突处理

目标文件夹已存在同名项时弹框:

| 选项 | 行为 |
|------|------|
| **替换** | 旧的移入**废纸篓**(可恢复),新的移入 |
| **两者都保留** | 自动改名(如 `报告.pdf` → `报告 2.pdf`),两个都留 |
| **跳过** | 该项不动,继续其余 |

若个别项因无写入权限等失败,会在最后汇总一句文字提示(**不会弹密码框**),其余项照常移动。

## 关于权限

本工具搬文件用系统底层 `mv` 命令,**不发送任何"控制访达"事件、不请求管理员权限**,所以正常使用不会弹自动化授权或密码/指纹。唯一可能:首次移动"桌面/文稿/下载"等受保护文件夹里的文件时,系统可能弹一次"允许访问"——点一次"允许"即可,持久生效、非密码、不会每次开机再问。

## 卸载

```bash
./uninstall.sh
```

## 工作原理

- `src/move_to.applescript` —— 弹文件夹选择框、检测同名冲突、用 `do shell script` 的 `mv` 执行移动(不含任何 `tell application "Finder"`)。`moveOne` / `hasConflict` / `uniqueName` 等纯逻辑处理器可自动化测试。
- `build.py` —— 用 `plistlib` 把该脚本注入生成 Automator 快速操作 bundle;`presentationMode = 15` 等元数据使其在右键顶层显示。
- `install.sh` / `uninstall.sh` —— 安装/卸载到 `~/Library/Services/` 并刷新服务缓存。

## 开发

```bash
python3 build.py            # 生成 bundle
./tests/test_moveitems.sh   # 移动语义 + 同名冲突三种处理(自成体系,无需访达授权)
./tests/test_build.sh       # bundle 结构、plist 合法性、注入内容一致
```

设计与实现文档见 [`docs/superpowers/`](docs/superpowers/)。

## 许可证

本项目基于 **GNU General Public License v3.0**(GPL-3.0)发布,详见 [`LICENSE`](LICENSE)。

Copyright (C) 2026 guopengnaivoc
````

- [ ] **Step 2: 提交**

```bash
git add README.md
git commit -m "docs(v2): README 更新为无权限打扰版"
```

---

## Task 3: 安装并人工验收(含重启零打扰确认)

**Files:** 无(执行与验收)。

**Interfaces:**
- Consumes: Task 1、Task 2。

- [ ] **Step 1: 重新安装并重启访达**

Run:
```bash
./install.sh
killall Finder
```
Expected: 打印 `✅ 已安装:…移动到….workflow`。

- [ ] **Step 2: 人工验收(由用户在访达中执行)**

在访达中逐项确认(图形界面操作,无法自动化):

1. 新建文件夹 `A`、`B`,`A` 里放一个测试文件。
2. 右键 `A` 里的文件 → 确认「移动到…」出现在**顶层「快速操作」区** → 点它 → 选 `B` → 确认文件从 `A` 移到 `B`。
3. 右键一个**文件夹** → 确认「移动到…」同样在顶层出现、可用。
4. 在 `A`、`B` 各放一个同名文件 → 移动 → 确认弹出三选框(替换/两者都保留/跳过),分别验证:替换后旧的在废纸篓、两者都保留生成 `名字 2.ext`、跳过不动。
5. **关键**:重启电脑 → 再用一次「移动到…」→ **确认全程不弹"控制访达"授权、不弹密码/指纹**(顶多首次访问受保护文件夹时点一次"允许")。

全部通过即视为完成。若第 5 步仍出现反复授权/密码,记录当时的框内原话,回到 systematic-debugging。

---

## Self-Review

**1. Spec coverage(逐条对照 v2 设计):**
- 右键顶层「移动到…」(文件/文件夹) → build.py(不变,presentationMode=15)+ Task 3 验收 ✅
- 选目标文件夹后移动 → Task 1 `on run` + `moveOne("move")` ✅
- 同名冲突三选(替换/两者都保留/跳过) → Task 1 `on run` 弹框 + `moveOne` 三分支 + 测试 4/5 ✅
- 替换=旧的进废纸篓可恢复 → Task 1 `moveOne` replace + 测试断言 `trash/a.txt` ✅
- 常驻/重启在/无后台 → 快速操作天然;Task 3 Step 5 验收 ✅
- 无"控制访达"授权 → 脚本无 `tell application "Finder"`,测试 grep 强制 ✅
- 无密码/指纹 → 无 `administrator privileges`/`sudo`,测试 grep 强制;失败给文字提示(`on run` 汇总)✅
- 失败给友好提示而非密码框 → Task 1 `on run` 失败汇总 dialog ✅

**2. Placeholder scan:** 无 TBD/TODO;每步含完整代码或完整命令。✅

**3. Type consistency:** `moveOne(srcPosix, dd, choice, trashDir)`、`hasConflict(srcPosix, dd)`、`uniqueName(dir, name)`、`splitExt`、`baseName`、`toPosix`、`destDir` 在脚本定义与测试调用中签名一致;冲突按钮文案 `替换/两者都保留/跳过` 与 `choice` 分支映射一致;`trashDir` 在 `on run`(`$HOME/.Trash/`)与测试(临时目录)均以 `/` 结尾传入。✅

## 已知风险与兜底

- build.py 生成的 bundle 顶层显示(presentationMode=15)此前由 Automator 导出反推、未经脚本安装在真机复验(v1 用户是用 Automator 手建的那份)。若 Task 3 Step 2 发现未在顶层显示,兜底:用 Automator GUI 新建「快速操作」,粘贴 `src/move_to.applescript` 内容另存(v1 已验证此法可行)。
- 跨卷移动到 `~/.Trash`:`mv` 跨卷会复制+删除,语义正确但非系统原生"放回原处"元数据;可接受(仍可从废纸篓恢复)。
