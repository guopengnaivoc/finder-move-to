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

在选择框点"取消"不会做任何操作。若个别文件移动失败(如目标已有同名文件、无权限),会弹提示告知哪几项失败,其余正常移动。

## 卸载

```bash
./uninstall.sh
```

## 开发

- 逻辑源:`src/move_to.applescript`(`moveItems` 处理器有自动化测试)。
- 打包:`python3 build.py` 生成 `build/移动到….workflow`。
- 测试:`./tests/test_moveitems.sh` 和 `./tests/test_build.sh`。
