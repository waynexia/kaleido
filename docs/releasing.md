# 发布与打包

v0.1.0 分发 macOS 13+ 通用 ZIP（arm64 / x86_64）和 SHA-256 校验文件。使用现有 `Kaleido Local Development` 身份；它不是 Developer ID，产物没有 Apple 公证。更换身份、公证及装订仍是独立的待完成流程，见[代码签名说明](code-signing.md)。

## 构建和打包

在仓库根目录使用 Bash 执行。先退出正在运行的 Kaleido，再运行 `make check`，确认版本号、测试、应用包与签名连续性均正确。通用包在独立目录组装，不替换已授权的 `build/Kaleido.app`；打包结束后可通过 `open build/Kaleido.app` 恢复日常运行。

以下为 v0.1.0 的打包步骤；发布其他版本时同时更新版本号、目录名和发布说明。不要提交 `build/` 或 `.build/` 产物。

```bash
set -euo pipefail
export LC_ALL=C
source scripts/toolchain.sh
swift build -c release --arch arm64 --arch x86_64 --scratch-path .build/universal
release_binary_dir="$(swift build -c release --arch arm64 --arch x86_64 --scratch-path .build/universal --show-bin-path)"
release_dir="$PWD/build/releases/v0.1.0"
mkdir -p "$release_dir"
release_staging="$(mktemp -d "$PWD/build/release-v0.1.0.XXXXXX")"
trap 'rm -rf "$release_staging"' EXIT
release_app="$release_staging/Kaleido.app"
mkdir -p "$release_app/Contents/MacOS" "$release_app/Contents/Resources"
cp "$release_binary_dir/Kaleido" "$release_app/Contents/MacOS/Kaleido"
cp Resources/Info.plist "$release_app/Contents/Info.plist"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$release_app/Contents/Info.plist")" = 0.1.0
./scripts/sign-app.sh "$release_app"
codesign --verify --strict --all-architectures "$release_app"
lipo "$release_app/Contents/MacOS/Kaleido" -verify_arch arm64 x86_64
"$release_app/Contents/MacOS/Kaleido" --self-check
ditto -c -k --sequesterRsrc --keepParent "$release_app" "$release_dir/Kaleido-v0.1.0-macos-universal.zip"
(cd "$release_dir" && shasum -a 256 Kaleido-v0.1.0-macos-universal.zip > SHA256SUMS.txt)
mkdir "$release_staging/unpacked"
ditto -x -k "$release_dir/Kaleido-v0.1.0-macos-universal.zip" "$release_staging/unpacked"
codesign --verify --strict --all-architectures "$release_staging/unpacked/Kaleido.app"
"$release_staging/unpacked/Kaleido.app/Contents/MacOS/Kaleido" --self-check
(cd "$release_dir" && shasum -a 256 -c SHA256SUMS.txt)
```

发布前检查归档仅包含应用包；两种架构的最低系统版本均为 13.0，Release 不含 `IntegrationCheck`。记录实际验证的平台，不把交叉编译成功视为 Intel 实机验收。首次下载的 Gatekeeper 行为也不能由本机自检推断。

## GitHub Release

提交版本及文档变更，确认构建对应的源码已推送，再创建并推送注解标签 `v0.1.0`。不要移动已有发布标签或覆盖已发布附件。使用仓库中的发布说明创建带附件的 Release：

```sh
gh release create v0.1.0 \
  build/releases/v0.1.0/Kaleido-v0.1.0-macos-universal.zip \
  build/releases/v0.1.0/SHA256SUMS.txt \
  --repo waynexia/kaleido --verify-tag --latest \
  --title 'Kaleido v0.1.0' --notes-file docs/releases/v0.1.0.md
```

完成后核对 Release 非草稿、标签指向预期提交、两个附件均已上传，并下载附件复查 SHA-256。
