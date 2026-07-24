# 移动到… — Finder 右键「移动到」快速操作

[![Release](https://img.shields.io/github/v/release/guopengnaivoc/finder-move-to)](https://github.com/guopengnaivoc/finder-move-to/releases/latest)
![Platform](https://img.shields.io/badge/platform-macOS-lightgrey)
[![License: GPL v3](https://img.shields.io/badge/license-GPL--3.0-blue)](LICENSE)

给 macOS 访达(Finder)的右键菜单加一个 **「移动到…」** 快速操作:选中文件/文件夹 → 右键(触控板双指按压亦可)→ **移动到…** → 弹框选目标文件夹 → **直接移动过去**(真移动,不是复制副本)。

- 🍎 **纯 macOS 原生**:只用系统自带能力,**零第三方软件**。
- 🔝 **右键顶层显示**:出现在右键「快速操作」区,文件和文件夹都在。
- 🔁 **同名冲突三选**:目标已有同名项时弹框选 **替换 / 两者都保留 / 跳过**。
- 🔓 **不打扰权限**:搬文件走系统底层命令、**不指挥访达、不用管理员权限** → 不弹"控制访达"授权、不弹密码/指纹。
- ⚡ **开机即用**:装一次后是常驻菜单项,重启、关机再开都在,无后台进程。

## 环境要求

macOS(在 macOS 26 / Apple Silicon 上验证)。只用系统自带的 `python3` / `osascript` / `Automator`,无需额外安装。

## 安装

### 方式 A:不用终端(推荐给普通用户)

到 [**Releases**](https://github.com/guopengnaivoc/finder-move-to/releases/latest) 下载 `move-to-quickaction.zip` → 解压 → **双击** `移动到….workflow` → 在弹窗里点「**安装**」。

### 方式 B:命令行(开发者)

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

一次移动多个文件、有**多个同名**时:第一个同名项弹框选处理方式后,会再问一句「其余同名项也都这样处理吗?」——选「是,全部这样」则其余同名项自动统一处理,不再逐个询问;选「否,逐个问」则继续逐个确认。

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
