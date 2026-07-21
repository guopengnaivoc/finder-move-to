# Finder 右键「移动到…」快速操作 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 做一个 macOS 原生右键「快速操作」——选中文件后右键 →「移动到…」→ 弹框选目标文件夹 → 直接移动(非复制)。

**Architecture:** 核心移动逻辑写在一个 AppleScript(`src/move_to.applescript`),其中 `moveItems` 处理器可被自动化测试;`on run` 负责弹文件夹选择框与错误提示。一个 Python 构建脚本(`build.py`)用 `plistlib` 把这段 AppleScript 注入到一个 Automator 服务工作流 `.workflow` bundle 中(避免手工转义 XML)。安装脚本把 bundle 拷进 `~/Library/Services/` 并刷新服务缓存,右键「快速操作」子菜单即出现「移动到…」。

**Tech Stack:** AppleScript(Finder `move` 动词、`choose folder`)、macOS Automator Service(`.workflow` bundle)、Python 3 `plistlib`(macOS 自带 `/usr/bin/python3`)、bash 安装脚本。全程零第三方软件、纯系统自带能力。

## Global Constraints

- 目标系统:macOS 26.5.2、Apple Silicon(arm64)、系统语言简体中文。
- 右键菜单项名称必须精确为:`移动到…`(注意结尾是省略号字符 `…`,不是三个点 `...`)。
- 零第三方软件、纯 macOS 原生;不修改任何系统安全设置(不关闭 SIP)。
- 移动必须是**真移动**(源消失、目标出现),不是复制副本。
- 只用系统自带的 `/usr/bin/python3` 与命令行工具(已确认存在);不引入 pip 依赖。
- 本次**不做**删除「复制/Duplicate」项(范围外)。
- 生成物目录 `build/` 不纳入版本控制。

---

## File Structure

```
finder-move-to/
  src/move_to.applescript      # 快速操作的“大脑”:on run(弹框/报错) + moveItems(可测试的移动逻辑)
  build.py                     # 用 plistlib 把 AppleScript 注入生成 .workflow bundle
  install.sh                   # 构建 + 拷贝到 ~/Library/Services + 刷新服务缓存
  uninstall.sh                 # 从 ~/Library/Services 删除 bundle + 刷新
  tests/test_moveitems.sh      # 自动化测试:moveItems 移动语义 + 冲突返回失败
  tests/test_build.sh          # 自动化测试:bundle 结构、plist 合法性、注入内容一致
  README.md                    # 安装/卸载/使用说明 + 手动验收清单
  .gitignore                   # 忽略 build/
  build/                       # (生成)构建产物,含 移动到….workflow
```

---

## Task 1: 核心移动脚本 `move_to.applescript`(TDD)

**Files:**
- Create: `src/move_to.applescript`
- Test: `tests/test_moveitems.sh`

**Interfaces:**
- Produces:
  - AppleScript 处理器 `moveItems(itemList, destFolder)` → 返回失败信息列表(`list of text`);`itemList` 每项可为 alias 或 POSIX 路径字符串,`destFolder` 为 folder alias。
  - AppleScript `on run {input, parameters}` → 服务入口(GUI,手动验收)。

- [ ] **Step 1: 写失败测试** — `tests/test_moveitems.sh`

```bash
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
```

- [ ] **Step 2: 运行测试确认失败**

Run: `chmod +x tests/test_moveitems.sh && ./tests/test_moveitems.sh`
Expected: FAIL —— 报 "编译失败"(因为 `src/move_to.applescript` 还不存在)。

- [ ] **Step 3: 写最小实现** — `src/move_to.applescript`

```applescript
-- 移动到… Quick Action
-- input: Finder 传入的选中项(alias 列表);parameters: 未使用
-- 行为:弹出文件夹选择框,把选中项移动(非复制)到目标文件夹

on run {input, parameters}
	if input is {} then return input
	set destFolder to missing value
	try
		set destFolder to (choose folder with prompt "移动到哪个文件夹?")
	on error number -128
		-- 用户取消,静默退出
		return input
	end try
	set failedMessages to moveItems(input, destFolder)
	if (count of failedMessages) > 0 then
		set AppleScript's text item delimiters to return
		set report to (failedMessages as text)
		set AppleScript's text item delimiters to ""
		display dialog "有 " & (count of failedMessages) & " 项移动失败:" & return & report buttons {"好"} default button "好" with icon caution
	end if
	return input
end run

-- 把 itemList 中每一项移动到 destFolder;返回失败信息列表(可自动化测试)
on moveItems(itemList, destFolder)
	set failedMessages to {}
	repeat with anItem in itemList
		try
			if class of anItem is text then
				set theAlias to (POSIX file anItem) as alias
			else
				set theAlias to anItem as alias
			end if
			tell application "Finder" to move theAlias to destFolder
		on error errMsg
			set end of failedMessages to errMsg
		end try
	end repeat
	return failedMessages
end moveItems
```

- [ ] **Step 4: 运行测试确认通过**

Run: `./tests/test_moveitems.sh`
Expected: PASS。
（首次运行 osascript 驱动 Finder 时,若系统弹出「终端请求控制 Finder / 自动化」授权,点允许。这是一次性授权,属正常。）

- [ ] **Step 5: 提交**

```bash
git add src/move_to.applescript tests/test_moveitems.sh
git commit -m "feat: 核心移动脚本 move_to.applescript(moveItems 已测试)"
```

---

## Task 2: 构建 `.workflow` bundle(`build.py`,TDD)

**Files:**
- Create: `build.py`
- Test: `tests/test_build.sh`

**Interfaces:**
- Consumes: `src/move_to.applescript`(Task 1 产物)。
- Produces: `build/移动到….workflow/`,内含 `Contents/Info.plist`(声明 NSServices,菜单名「移动到…」,限定 Finder)与 `Contents/document.wflow`(Run AppleScript 动作,`ActionParameters.source` 为注入的脚本)。

- [ ] **Step 1: 写失败测试** — `tests/test_build.sh`

```bash
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

# 注入的 AppleScript 必须与源文件一致
emb=$(/usr/libexec/PlistBuddy -c "Print :actions:0:action:ActionParameters:source" "$C/document.wflow")
src=$(cat "$ROOT/src/move_to.applescript")
[ "$emb" = "$src" ] || { echo "FAIL: 注入脚本与源不一致"; exit 1; }

echo "PASS"
```

- [ ] **Step 2: 运行测试确认失败**

Run: `chmod +x tests/test_build.sh && ./tests/test_build.sh`
Expected: FAIL —— 报 "构建失败"(`build.py` 还不存在)。

- [ ] **Step 3: 写最小实现** — `build.py`

```python
#!/usr/bin/env python3
"""把 src/move_to.applescript 注入生成 Automator 服务工作流 bundle。"""
import plistlib
import uuid
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent
SRC = ROOT / "src" / "move_to.applescript"
BUNDLE = ROOT / "build" / "移动到….workflow"
CONTENTS = BUNDLE / "Contents"


def main() -> None:
    source = SRC.read_text(encoding="utf-8")
    CONTENTS.mkdir(parents=True, exist_ok=True)

    info = {
        "NSServices": [
            {
                "NSMenuItem": {"default": "移动到…"},
                "NSMessage": "runWorkflowAsService",
                "NSRequiredContext": {"NSApplicationIdentifier": "com.apple.finder"},
                "NSSendFileTypes": ["public.item"],
            }
        ]
    }
    with open(CONTENTS / "Info.plist", "wb") as f:
        plistlib.dump(info, f)

    action = {
        "action": {
            "AMAccepts": {
                "Container": "List",
                "Optional": True,
                "Types": ["com.apple.cocoa.string"],
            },
            "AMActionVersion": "1.0.2",
            "AMApplication": ["Automator"],
            "AMParameterProperties": {"source": {}},
            "AMProvides": {
                "Container": "List",
                "Types": ["com.apple.cocoa.string"],
            },
            "ActionBundlePath": "/System/Library/Automator/Run AppleScript.action",
            "ActionName": "Run AppleScript",
            "ActionParameters": {"source": source},
            "BundleIdentifier": "com.apple.Automator.RunScript",
            "CFBundleVersion": "1.0.2",
            "CanShowSelectedItemsWhenRun": False,
            "CanShowWhenRun": True,
            "Category": ["AMCategoryUtilities"],
            "Class Name": "RunScriptAction",
            "InputUUID": str(uuid.uuid4()).upper(),
            "Keywords": ["Run"],
            "OutputUUID": str(uuid.uuid4()).upper(),
            "UUID": str(uuid.uuid4()).upper(),
            "UnlocalizedApplications": ["Automator"],
            "arguments": {},
            "isViewVisible": 1,
        },
        "isViewVisible": 1,
    }

    wflow = {
        "AMApplicationBuild": "521",
        "AMApplicationVersion": "2.10",
        "AMDocumentVersion": "2",
        "actions": [action],
        "connectors": {},
        "workflowMetaData": {
            "serviceApplicationBundleID": "com.apple.finder",
            "serviceApplicationPath": "/System/Library/CoreServices/Finder.app",
            "serviceInputTypeIdentifier": "com.apple.Automator.fileSystemObject",
            "serviceOutputTypeIdentifier": "com.apple.Automator.nothing",
            "serviceProcessesInput": 0,
            "workflowTypeIdentifier": "com.apple.Automator.servicesMenu",
        },
    }
    with open(CONTENTS / "document.wflow", "wb") as f:
        plistlib.dump(wflow, f)

    print(f"Built: {BUNDLE}")


if __name__ == "__main__":
    main()
```

- [ ] **Step 4: 运行测试确认通过**

Run: `./tests/test_build.sh`
Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add build.py tests/test_build.sh
git commit -m "feat: build.py 生成 移动到… 服务工作流 bundle"
```

---

## Task 3: 安装 / 卸载脚本 + `.gitignore`

**Files:**
- Create: `install.sh`
- Create: `uninstall.sh`
- Create: `.gitignore`

**Interfaces:**
- Consumes: `build.py`(Task 2)。
- Produces: `~/Library/Services/移动到….workflow`(安装后);`install.sh` / `uninstall.sh` 可执行。

- [ ] **Step 1: 写 `.gitignore`**

```gitignore
build/
```

- [ ] **Step 2: 写 `install.sh`**

```bash
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
```

- [ ] **Step 3: 写 `uninstall.sh`**

```bash
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
```

- [ ] **Step 4: 赋可执行权限并验证安装/卸载**

Run:
```bash
chmod +x install.sh uninstall.sh
./install.sh
test -d "$HOME/Library/Services/移动到….workflow" && echo "INSTALL-OK"
plutil -lint "$HOME/Library/Services/移动到….workflow/Contents/document.wflow"
./uninstall.sh
test ! -d "$HOME/Library/Services/移动到….workflow" && echo "UNINSTALL-OK"
```
Expected: 打印 `INSTALL-OK`、`document.wflow: OK`、`UNINSTALL-OK`。
之后重新安装一次以便下一步手动验收:`./install.sh`

- [ ] **Step 5: 提交**

```bash
git add install.sh uninstall.sh .gitignore
git commit -m "feat: 安装/卸载脚本 + gitignore"
```

---

## Task 4: README + 手动验收清单

**Files:**
- Create: `README.md`

**Interfaces:**
- Consumes: 全部前置任务。
- Produces: 用户可读的安装/使用/卸载说明与验收清单。

- [ ] **Step 1: 写 `README.md`**

````markdown
# Finder 右键「移动到…」快速操作

在 Finder 选中文件/文件夹,右键 →「快速操作」→「移动到…」→ 弹框选目标文件夹 → 直接移动过去(真移动,不是复制副本)。纯 macOS 原生,零第三方软件,开机即用。

## 安装

```bash
./install.sh
```

安装后如果右键没立刻出现,执行 `killall Finder` 重启 Finder,或到
系统设置 → 键盘 → 键盘快捷键 → 服务 里确认「移动到…」已勾选。

## 使用

1. 在 Finder 里选中一个或多个文件/文件夹。
2. 右键 → 快速操作 → 移动到…
3. 在弹出的文件夹选择框里选目标文件夹。
4. 文件被移动过去(源位置不再有)。

在选择框点“取消”不会做任何操作。若个别文件移动失败(如目标已有同名文件、无权限),会弹提示告知哪几项失败,其余正常移动。

## 卸载

```bash
./uninstall.sh
```

## 开发

- 逻辑源:`src/move_to.applescript`(`moveItems` 处理器有自动化测试)。
- 打包:`python3 build.py` 生成 `build/移动到….workflow`。
- 测试:`./tests/test_moveitems.sh` 和 `./tests/test_build.sh`。
````

- [ ] **Step 2: 提交**

```bash
git add README.md
git commit -m "docs: README + 使用说明"
```

- [ ] **Step 3: 手动验收(由用户在 Finder 中执行)**

在 Finder 中逐项确认(这些是图形界面操作,无法自动化):

1. 新建两个测试文件夹 `A`、`B`,在 `A` 里放一个测试文件 `t.txt`。
2. 选中 `A/t.txt` → 右键 → 快速操作 → 确认出现「移动到…」并点击。
3. 弹出文件夹选择框 → 选 `B` → 确认 `t.txt` 从 `A` 消失、出现在 `B`。
4. 一次选中多个文件 → 移动到… → 选目标 → 确认全部移动过去。
5. 再点一次「移动到…」但在选择框点“取消” → 确认文件原封不动。

全部通过即视为完成。

---

## Self-Review

**1. Spec coverage(逐条对照规格):**
- 架构:原生快速操作装到 `~/Library/Services` → Task 2/3 ✅
- 交互:选中→右键→choose folder→Finder 移动 → Task 1(`on run`)+ Task 4 验收 ✅
- 错误处理:取消静默退出(`on error number -128`)、失败弹框汇总 → Task 1 ✅;同名冲突计入失败信息 → Task 1 Step1 测试 ✅
- 真移动非复制 → Task 1 测试断言源消失 ✅
- 手工构建 bundle(不开 Automator GUI)→ Task 2 `build.py` ✅
- 交付:项目目录 + 安装脚本 + 刷新缓存 → Task 3 ✅
- 验证:osascript 先验证移动逻辑 + 安装后 Finder 手动验收 → Task 1 + Task 4 ✅
- 范围外(删复制)未纳入 → 规格与本计划一致 ✅

**2. Placeholder scan:** 无 TBD/TODO;每步含完整代码或完整命令。✅

**3. Type consistency:** `moveItems(itemList, destFolder)` 在 Task 1 定义、Task 2 测试按同名读取注入内容;菜单名「移动到…」在 build.py、install.sh、uninstall.sh、测试、README 中一致(均为省略号 `…`)。✅

## 已知风险与兜底

- **wflow 兼容性**:`document.wflow` 为手工构造。极小概率某些可选键在本机 macOS 26 上不被 WorkflowServiceRunner 接受,导致菜单项不出现或点击无反应。兜底:Task 4 手动验收若失败,进入 systematic-debugging;最终兜底方案是用 Automator GUI 新建一次同样的「快速操作」(粘贴 `src/move_to.applescript` 内容、输入类型选“文件或文件夹”、限定 Finder)再保存——此为一次性 GUI 操作,不违反“零第三方软件”约束。
- **自动化授权**:首次用 osascript 驱动 Finder 会触发一次系统自动化授权弹窗,点允许即可。
