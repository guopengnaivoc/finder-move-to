#!/usr/bin/python3
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
        # bundle 标识:系统能正常显示的服务都带这些键,缺了会导致右键项不稳定/不显示
        "CFBundleDevelopmentRegion": "zh_CN",
        "CFBundleIdentifier": "com.local.finder.moveto",
        "CFBundleName": "移动到…",
        "CFBundleShortVersionString": "1.0",
        "CFBundlePackageType": "wflw",
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
            # 注:纯脚本无法把它变成右键顶层“快速操作”;文件夹会落在“服务”子菜单。
            # 想要顶层显示需用 Automator GUI 另存为“快速操作”(见 README)。
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
