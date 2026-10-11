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

## 文档

- [功能基线](docs/behavior-baseline.md)
- [架构与开发约定](docs/architecture.md)
- [验证记录](docs/validation.md)

窗口列表只在内存中处理，不保存窗口标题、屏幕图像或应用使用历史。
