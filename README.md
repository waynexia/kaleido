# Kaleido

原生 macOS 窗口切换器。Swift + AppKit，macOS 13 及以上，无第三方运行时依赖。

## 开发

需要 Xcode 16 或更新版本（Swift 6 工具链），以及按[代码签名说明](docs/code-signing.md)创建的固定本地签名身份。

```sh
make test     # 单元测试，无需签名身份
make check    # 单元测试、构建、应用包与签名连续性检查
make run      # 构建并打开应用
make preview  # 无需辅助功能权限的界面预览
```

构建产物位于 `build/Kaleido.app`。脚本优先使用 `/Applications/Xcode.app`，不修改全局 `xcode-select`。默认使用登录钥匙串中的 `Kaleido Local Development` 证书签名，身份缺失时构建失败，不会自动退回 ad-hoc。发行构建可传入 `CODE_SIGN_IDENTITY`。

`make check`、`make run`、`make preview` 和预览脚本都会更新同一应用包。更新前先退出正在运行的 Kaleido，再执行 `make run`；关闭设置窗口只会让应用留在后台，`make run` 也不会自动重启已有进程。

## 使用

1. 打开 `build/Kaleido.app`，在“系统设置 → 隐私与安全性 → 辅助功能”中允许 Kaleido。
2. 默认使用 **Control + Tab** 切换所有窗口，**Option + 反引号**（Tab 上方的键）切换当前应用窗口。本机已退出 AltTab，并选中此标准方案；设置会在重启后保留。
3. 按住 Control，重复按 Tab 选择窗口，松开 Control 聚焦。同应用切换时按住 Option 并重复按反引号。Shift 反向选择，方向键导航，Esc 取消，Space 聚焦；W / M / F / Q / H 分别关闭、最小化、全屏、退出应用、隐藏应用。

如需与 AltTab 同时运行，可在设置中选择共存方案：**Control + Option + K**（所有窗口）和 **Control + Option + J**（当前应用）。只有标准方案遇到正在运行的 AltTab 时才待命，避免快捷键冲突。切换方案不会更改 AltTab 设置。

列表使用应用图标和窗口标题，跟随系统主题，在鼠标所在屏幕显示。包含最小化、隐藏和全屏窗口，不显示缩略图，无需录屏授权。

运行时默认显示菜单栏图标，点击直接打开设置。也可以在设置中隐藏图标，再次打开应用可回到设置；已有的隐藏偏好会继续保留。需要登录启动时，将应用移到固定位置再勾选设置中的“登录时启动”。

应用启动时自动检查一次辅助功能权限。缺少权限时会打开设置窗口，点击“打开辅助功能设置…”即可直达 macOS 对应页面；等待授权期间每 1.5 秒检查一次，返回应用时也会立即确认。确认授权后自动隐藏权限按钮并停止检查，无需手动点击“重新检查”。

`./scripts/preview.sh` 无需辅助功能权限即可导出界面预览，`./scripts/fixture.sh` 提供三个独立测试窗口。已完成与待完成的验收见[验证记录](docs/validation.md)。

## 文档

- [功能基线](docs/behavior-baseline.md)
- [架构与开发约定](docs/architecture.md)
- [代码签名与更新授权](docs/code-signing.md)
- [验证记录](docs/validation.md)

窗口列表只在内存中处理，不保存窗口标题、屏幕图像或应用使用历史。

保持同一签名证书、bundle ID 与安装路径，正常重建无需逐次重新授权。首次从 ad-hoc 迁移到证书签名时需要更新一次辅助功能授权，详见签名说明。设置窗口中的运行状态以应用自身权限为准；从终端直接运行 `--diagnose` 检查的是命令进程，不能替代已启动应用的权限状态。
