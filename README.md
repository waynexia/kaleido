# Kaleido

原生 macOS 窗口切换器。Swift + AppKit，macOS 13 及以上，无第三方运行时依赖。

## 开发

需要 Xcode 16 或更新版本（Swift 6 工具链）。

```sh
make check    # 单元测试、构建、签名与应用包检查
make run      # 构建并打开应用
make preview  # 无需系统权限的界面预览
```

构建产物位于 `build/Kaleido.app`。脚本优先使用 `/Applications/Xcode.app`，不修改全局 `xcode-select`。默认使用本地 ad-hoc 签名；发行构建可传入 `CODE_SIGN_IDENTITY`。

## 使用

1. 打开 `build/Kaleido.app`，在“系统设置 → 隐私与安全性 → 辅助功能”中允许 Kaleido。
2. 在设置中选择快捷键方案。与 AltTab 共存时使用 **Control + Option + K**（所有窗口）和 **Control + Option + J**（当前应用）；本机已选择此方案。
3. 按住修饰键，重复按 K / J 选择窗口，松开修饰键聚焦。Shift 反向选择，方向键导航，Esc 取消，Space 聚焦；W / M / F / Q / H 分别关闭、最小化、全屏、退出应用、隐藏应用。

标准方案保留 **Control + Tab** 和 **Option + `**。只有标准方案遇到正在运行的 AltTab 时才待命，避免快捷键冲突。切换方案不会更改 AltTab 设置。

列表使用应用图标和窗口标题，跟随系统主题，在鼠标所在屏幕显示。包含最小化、隐藏和全屏窗口，不显示缩略图，无需录屏授权。

运行时默认显示菜单栏图标，点击直接打开设置。也可以在设置中隐藏图标，再次打开应用可回到设置。需要登录启动时，将应用移到固定位置再勾选设置中的“登录时启动”。

`./scripts/preview.sh` 可以在没有授权时生成界面预览，`./scripts/fixture.sh` 提供三个独立测试窗口。已完成与待完成的验收见[验证记录](docs/validation.md)。

## 文档

- [功能基线](docs/behavior-baseline.md)
- [架构与开发约定](docs/architecture.md)
- [验证记录](docs/validation.md)

窗口列表只在内存中处理，不保存窗口标题、屏幕图像或应用使用历史。

开发构建更新后，ad-hoc 签名变化可能使旧辅助功能授权失效。此时在系统设置中移除旧 Kaleido 条目、重新添加当前应用并重启。设置窗口中的运行状态以应用自身权限为准；从终端直接运行 `--diagnose` 检查的是命令进程，不能替代已启动应用的权限状态。
