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
2. 退出 AltTab 后，Kaleido 自动启用；两者同时运行时 Kaleido 待命。
3. 按住 Control、按 Tab 选择窗口，松开 Control 聚焦。Shift 反向选择，Esc 取消；Option + ` 切换当前应用的窗口。

列表使用应用图标和窗口标题，跟随系统主题，在鼠标所在屏幕显示。包含最小化、隐藏和全屏窗口，不显示缩略图，无需录屏授权。

菜单栏图标默认隐藏，再次打开应用可进入设置。需要登录启动时，将应用移到固定位置再勾选设置中的“登录时启动”。

`./scripts/preview.sh` 可以在没有授权时生成界面预览，`./scripts/fixture.sh` 提供三个独立测试窗口。已完成与待完成的验收见[验证记录](docs/validation.md)。

## 文档

- [功能基线](docs/behavior-baseline.md)
- [架构与开发约定](docs/architecture.md)
- [验证记录](docs/validation.md)

窗口列表只在内存中处理，不保存窗口标题、屏幕图像或应用使用历史。
