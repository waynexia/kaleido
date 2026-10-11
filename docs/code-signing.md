# 代码签名与更新授权

Kaleido 的 bundle ID 固定为 `dev.waynexia.Kaleido`。只有固定 ID 并不足以保留系统授权：ad-hoc 签名的 designated requirement 绑定内容哈希，代码变化后它也会变化。证书签名把要求绑定到签名身份，因此同一身份签署的新版本可继续满足原有要求。

## 本机开发

默认 `make build` / `make check` 使用登录钥匙串中名为 `Kaleido Local Development` 的签名身份。此身份在本机创建一次并持续复用，不随 `make clean` 删除；脚本不会生成证书，也不会在签名失败时自动使用 ad-hoc。

新电脑的设置步骤：

1. 打开“钥匙串访问 → 证书助理 → 创建证书”。名称填写 `Kaleido Local Development`，身份类型选择“自签名根证书”，证书类型选择“代码签名”。
2. 勾选覆盖默认值，设置合适有效期（本机开发证书为 3650 天）。使用 RSA 2048 位或以上；密钥使用仅签名，扩展密钥使用仅代码签名，不启用 SSL / 邮件用途。无须设置主题备用名称。
3. 将证书和私钥存入“登录”钥匙串。无须把证书设成系统全局信任，也无须导出私钥。自签名身份可能在 `security find-identity -p codesigning` 中显示未受信任，但可以用于本地签名及 designated requirement 校验。
4. 首次 `make build` 时，在钥匙串提示中允许系统 `/usr/bin/codesign` 使用此密钥；如需后续构建不重复询问，选择“始终允许”。不要把私钥访问权限设置为允许所有应用。
5. 退出旧 Kaleido，通过 `open build/Kaleido.app` 启动；首次授权辅助功能。应用和签名身份保持固定后，更新只需退出、构建、重新打开。

本地证书不是 Developer ID，也不提供公证或 Apple 发行信任。v0.1.0 的下载包沿用此固定身份，并明确标注为未公证构建；Gatekeeper 可能阻止直接打开，不能把本机授权保留视为新用户安装验收。打包步骤见[发布与打包](releasing.md)。需要 Apple 发行信任时，应使用适当的 Apple 签名身份并完成公证：

```sh
CODE_SIGN_IDENTITY='Developer ID Application: …' CONFIGURATION=release make check
```

此命令只指定签名身份与构建配置，并会更新本机应用包。若需更换分发签名，应在独立 checkout 构建，保留日常使用路径中的原签名。当前发布步骤支持 ZIP 打包，但没有公证和装订流程，不能据此宣称已完成 Apple 发行信任验收。

`CODE_SIGN_IDENTITY` 可填写唯一身份名称或证书指纹；不要在钥匙串中创建多个同名身份。证书、私钥、密码、导出文件均不进入仓库。保留原身份；删除重建同名证书仍然是不同身份，可能需要重新授权。

没有签名身份的 CI / 临时预览可在独立 checkout 显式运行 `CODE_SIGN_IDENTITY=- make check`，此方式不保证更新保留授权，并会跳过持久身份检查。构建脚本拒绝用 ad-hoc 覆盖已有证书签名的日常应用。

GitHub Actions 的一次性 macOS runner 显式使用此 ad-hoc 模式，只做测试和包结构检查，不上传发行包，也不接收本机私钥。固定证书的签名连续性在本机验证，Release 附件使用本机既有证书单独签署。

构建先检查 Kaleido 已退出，在 `build/` 下临时目录组装、签名并自检新包，成功后再替换固定路径；签名或自检失败保留旧包。默认本地身份还会与旧包的证书绑定要求比较，防止同名证书被重建后无声丢失授权。显式传入其他 `CODE_SIGN_IDENTITY` 表示有意切换身份，仍需自行处理相应授权迁移。替换前会再次确认应用没有启动；中途失败尽可能恢复旧包。

## 从临时签名迁移

从现有 ad-hoc 构建切换到固定证书属于一次身份变更。若旧辅助功能条目失效，在系统设置中移除旧 Kaleido，重新添加固定路径中的证书签名应用并重启。此过程由用户完成 macOS 要求的身份验证，不修改 TCC 数据库。

保留同一证书、bundle ID 与路径能维持正常更新的身份连续性；用户撤销授权、系统重置权限、迁移安装位置或更换签名身份仍可能要求重新授权。不要把 designated requirement 放宽为仅检查 bundle ID，这会失去对实际签名者的约束。

## 验证

```sh
codesign -d -r- build/Kaleido.app
make check
```

本地证书签名的要求应包含 `identifier "dev.waynexia.Kaleido"` 和 `certificate leaf = H"…"`，而不是只包含 `cdhash`。`make check` 先重新构建并签名 `build/Kaleido.app`，因此应先退出正在使用此路径的 Kaleido。

随后执行的 `scripts/check-signing.sh` 才是副本检查：复制已构建的应用到临时目录、改变版本号、重新签名，确认内容哈希已变化而证书绑定要求完全一致，再删除临时副本。单独运行此脚本不会替换原应用，也不会修改系统权限。`make test` 只运行单元测试，不要求签名身份。

这项检查验证签名连续性；辅助功能是否实际保留，需要在经 LaunchServices 启动的应用中观察“已就绪”状态，或运行隔离测试窗口的集成验收。Shell 中直接运行 `--diagnose` 不能替代应用进程的授权状态。

参考：[Apple Code Signing Guide](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/Procedures/Procedures.html)、[macOS Code Signing In Depth](https://developer.apple.com/library/archive/technotes/tn2206/)。
