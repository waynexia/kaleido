# 发布与打包

v0.1.0 之后的版本仅支持 Apple Silicon，分发 macOS 13+ 的 arm64 ZIP 和 SHA-256 校验文件，不再构建或打包 Intel（x86_64）。已发布的 v0.1.0 通用包及其[验证记录](validation.md)保留，历史打包步骤可在 `v0.1.0` 标签中查阅。

使用现有 `Kaleido Local Development` 身份；它不是 Developer ID，产物没有 Apple 公证。更换身份、公证及装订仍是独立的待完成流程，见[代码签名说明](code-signing.md)。

## 构建和打包

在 Apple Silicon Mac 的仓库根目录使用 Bash 执行。先退出正在运行的 Kaleido，再运行 `make check`，确认版本号、测试、应用包与签名连续性均正确。发行包在独立目录组装，不替换已授权的 `build/Kaleido.app`；打包结束后可通过 `open build/Kaleido.app` 恢复日常运行。

以下为后续版本的打包步骤。发布前先更新 `Resources/Info.plist` 中的版本号，并准备对应的 `docs/releases/v<版本号>.md`；目录和附件名从版本号生成，不要以 v0.1.0 重新发布。不要提交 `build/` 或 `.build/` 产物。

```bash
set -euo pipefail
export LC_ALL=C
source scripts/toolchain.sh
release_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
swift build -c release --arch arm64 --scratch-path .build/release-arm64
release_binary_dir="$(swift build -c release --arch arm64 --scratch-path .build/release-arm64 --show-bin-path)"
release_dir="$PWD/build/releases/v$release_version"
release_archive="Kaleido-v${release_version}-macos-arm64.zip"
mkdir -p "$release_dir"
release_staging="$(mktemp -d "$PWD/build/release-v${release_version}.XXXXXX")"
trap 'rm -rf "$release_staging"' EXIT
release_app="$release_staging/Kaleido.app"
mkdir -p "$release_app/Contents/MacOS" "$release_app/Contents/Resources"
cp "$release_binary_dir/Kaleido" "$release_app/Contents/MacOS/Kaleido"
cp Resources/Info.plist "$release_app/Contents/Info.plist"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$release_app/Contents/Info.plist")" = "$release_version"
./scripts/sign-app.sh "$release_app"
codesign --verify --strict --all-architectures "$release_app"
test "$(lipo -archs "$release_app/Contents/MacOS/Kaleido")" = arm64
"$release_app/Contents/MacOS/Kaleido" --self-check
ditto -c -k --sequesterRsrc --keepParent "$release_app" "$release_dir/$release_archive"
(cd "$release_dir" && shasum -a 256 "$release_archive" > SHA256SUMS.txt)
mkdir "$release_staging/unpacked"
ditto -x -k "$release_dir/$release_archive" "$release_staging/unpacked"
codesign --verify --strict --all-architectures "$release_staging/unpacked/Kaleido.app"
test "$(lipo -archs "$release_staging/unpacked/Kaleido.app/Contents/MacOS/Kaleido")" = arm64
"$release_staging/unpacked/Kaleido.app/Contents/MacOS/Kaleido" --self-check
(cd "$release_dir" && shasum -a 256 -c SHA256SUMS.txt)
```

发布前检查归档仅包含应用包，二进制架构必须恰好为 arm64，最低系统版本为 13.0，Release 不含 `IntegrationCheck`。记录实际验证的 Apple Silicon 和 macOS 版本；Intel 不在后续发布的支持或验收范围内。首次下载的 Gatekeeper 行为也不能由本机自检推断。

## GitHub Release

提交版本及文档变更，确认构建对应的源码已推送，再创建并推送对应的注解标签 `v<版本号>`。不要移动已有发布标签或覆盖已发布附件。在上述打包命令的同一 Bash 会话中，使用仓库中的发布说明创建带附件的 Release：

```sh
gh release create "v$release_version" \
  "$release_dir/$release_archive" \
  "$release_dir/SHA256SUMS.txt" \
  --repo waynexia/kaleido --verify-tag --latest \
  --title "Kaleido v$release_version" --notes-file "docs/releases/v$release_version.md"
```

完成后核对 Release 非草稿、标签指向预期提交、两个附件均已上传，并下载附件复查 SHA-256。
