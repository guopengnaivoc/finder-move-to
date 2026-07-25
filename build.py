#!/usr/bin/python3
"""把 src/move_to.applescript 注入生成 Automator 服务工作流 bundle。"""
import plistlib
import sys
import uuid
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent
SRC = ROOT / "src" / "move_to.applescript"

# 语言:zh(默认,菜单「移动到…」)或 en(菜单「Move To…」,对话框英文)
LANG = sys.argv[1] if len(sys.argv) > 1 and sys.argv[1] in ("zh", "en") else "zh"
NAMES = {
    "zh": {"menu": "移动到…", "bundle": "移动到…"},
    "en": {"menu": "Move To…", "bundle": "Move To…"},
}[LANG]

BUNDLE = ROOT / "build" / f"{NAMES['bundle']}.workflow"
CONTENTS = BUNDLE / "Contents"


def main() -> None:
    source = SRC.read_text(encoding="utf-8")
    if LANG == "en":
        # 英文版:把界面语言开关翻成 en(菜单名另在 Info.plist 里设)
        source = source.replace('property uiLang : "zh"', 'property uiLang : "en"')
    CONTENTS.mkdir(parents=True, exist_ok=True)

    # NSIconName/NSBackgroundColorName 让它以“快速操作”外观出现在右键顶层
    info = {
        "NSServices": [
            {
                "NSBackgroundColorName": "background",
                "NSIconName": "NSActionTemplate",
                "NSMenuItem": {"default": NAMES["menu"]},
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
        # 复刻 Automator“快速操作”导出的元数据;presentationMode=15 是让它进入
        # 右键顶层“快速操作”区(而非“服务”子菜单)的关键。
        "workflowMetaData": {
            "applicationBundleID": "com.apple.finder",
            "applicationBundleIDsByPath": {
                "/System/Library/CoreServices/Finder.app": "com.apple.finder"
            },
            "applicationPath": "/System/Library/CoreServices/Finder.app",
            "applicationPaths": ["/System/Library/CoreServices/Finder.app"],
            "inputTypeIdentifier": "com.apple.Automator.fileSystemObject",
            "outputTypeIdentifier": "com.apple.Automator.nothing",
            "presentationMode": 15,
            "processesInput": False,
            "serviceApplicationBundleID": "com.apple.finder",
            "serviceApplicationPath": "/System/Library/CoreServices/Finder.app",
            "serviceInputTypeIdentifier": "com.apple.Automator.fileSystemObject",
            "serviceOutputTypeIdentifier": "com.apple.Automator.nothing",
            "serviceProcessesInput": False,
            "systemImageName": "NSActionTemplate",
            "useAutomaticInputType": False,
            "workflowTypeIdentifier": "com.apple.Automator.servicesMenu",
        },
    }
    with open(CONTENTS / "document.wflow", "wb") as f:
        plistlib.dump(wflow, f)

    print(f"Built: {BUNDLE}")


if __name__ == "__main__":
    main()
