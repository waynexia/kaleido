# 架构与开发约定

## 模块边界

`KaleidoCore` 不依赖 AppKit，负责窗口描述、内存 MRU 排序、切换会话、快捷键状态机和尺寸约束。XCTest 覆盖边界行为。

`Kaleido` 是 AppKit 应用：

- `WindowRepository` 在串行工作队列中读取普通应用及辅助应用的标准窗口和对话框；AXObserver 及 NSWorkspace 通知驱动刷新，3 秒轮询兜底，60 ms 合并通知。单次 AX 消息设超时，失败时保留已知记录。Space 动画造成的不完整列表保留最多 1.5 秒并重试；明确的销毁通知和应用退出立即移除。
- `Accessibility` 集中封装 AX 读写。动态查找 `_AXUIElementGetWindow` 来关联 WindowServer 的稳定 ID；该非公开符号不可用时退回 AX 对象比较。该兼容边界不用于执行窗口动作。
- `GlobalShortcuts` 在主 RunLoop 上用 CGEventTap 截获输入，调用纯状态机。事件回调不执行 AX 枚举或网络操作。会话期间以 25 ms 定时核对修饰键状态，防止遗漏松键通知后继续吞掉输入。事件 tap 被系统禁用时取消当前会话并重新启用。
- `SwitcherCoordinator` 管理缓存、100 ms 显示延迟、选择与聚焦。打开期间保持列表原顺序，标题/状态更新和窗口消失不会任意改变选择。
- `SwitcherPanelController` 使用非激活 NSPanel、NSVisualEffectView 与原生图标；跟随系统深浅色、减少动态效果设置，按鼠标所在屏幕定位。选中行自动滚入可视区。
- `PreferencesWindowController` 管理权限入口、暂停、菜单栏图标和 SMAppService 登录项。菜单栏图标默认显示，按钮直接调用设置入口；可在设置中隐藏，显式保存的可见性偏好优先于默认值。关闭设置不退出后台进程，再次打开应用可回到设置。

## 权限和进程

仅需要辅助功能授权，不需要屏幕录制；不使用 AppleScript、截图、网络服务或私有窗口操作接口。窗口标题和 MRU 只驻留内存，诊断输出不包含标题。开发预览使用内置样本数据。

快捷键方案保存在 Kaleido 自身偏好中。标准方案在 AltTab 运行时保持待命；共存方案使用 Control + Option + K / J，两者可同时工作。`--coexist` 可选中并保存共存方案。不会修改 AltTab 偏好、登录项或授权。

全屏远程桌面/虚拟机的默认例外与基线一致。没有窗口的应用不创建占位项。支持标准窗口与对话框；不将非活动标准标签页单列为窗口。

## 限制与取舍

- 不同应用实现 AX 的质量不同；未暴露标准窗口、关闭按钮或全屏属性的应用无法保证相应动作成功。失败会发出系统提示音，不能强行绕过。
- 通过 AX 枚举所有应用，包含其他桌面的窗口；跨桌面/原生全屏的最终前置行为仍受 macOS 与目标应用影响，需要多显示器/多桌面人工验收。
- Dock 通知标识仅在其 AX 接口提供 `AXStatusLabel` 时读取；不会读取应用私有数据库来取得未公开计数。
- 窗口 ID 桥接为非公开兼容点，不承诺 Mac App Store 兼容性。替换此桥接不应影响 core 或 UI。
- Option + Tab 上方键按物理键码识别（美式布局为反引号）。快捷键以物理位置为准，不提供键盘布局编辑器。
- 使用仍受支持的 `hudWindow` 语义材质代替参考版本已废弃的 light/dark 材质；不同 macOS 版本、背景和辅助功能对比度设置下透明效果会略有差异。
- 登录启动已实现为系统登录项，但构建或首次运行不会自动注册；将应用放入固定位置后由用户启用。开发构建更换 ad-hoc 签名后可能需要重新授权。

## 开发流程

1. 使用 `codex/` 或其他职责明确的分支。
2. 一次提交只承载一个完整变化，采用 `chore:`、`feat:`、`fix:`、`docs:` 等前缀。
3. 状态机变化补充行为测试；原生 UI 改动检查浅色、深色、长标题、滚动与键盘输入。
4. 运行 `make check`。需要优化构建时运行 `CONFIGURATION=release make build`。
5. 更新行为基线、验证记录和已知限制。不提交构建产物、机器专属路径配置、真实窗口标题或完整用户偏好导出。

不将任务描述、实现目的、开发过程说明写入产品界面。UI 仅显示窗口内容、操作入口和必要的运行状态。

## 本地测试入口

```sh
./scripts/preview.sh        # 导出浅色/深色样本视图到 build/previews
./scripts/fixture.sh        # 打开三个可安全关闭的测试窗口
build/Kaleido.app/Contents/MacOS/Kaleido --diagnose
```

预览 PNG 是 AppKit 视图的离屏绘制，用于尺寸与文字排版检查，不包含实际桌面毛玻璃取样。真实透明效果通过正常浮层人工检查。

`IntegrationCheck` 是显式启用的 Debug 测试入口。它通过 CGEvent 发送真实全局按键，独立的 `FixtureAccessibility` actor 在后台查询测试窗口，避免阻塞主线程事件 tap。窗口管理动作限定在 `dev.waynexia.Kaleido.WindowFixture`；所有窗口范围只检查列表并取消。报告不含真实窗口标题，Release 不包含此入口。运行方法见验证记录。
