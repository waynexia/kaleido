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

本地证书只用于本机开发，不是 Developer ID，也不提供公证或发行信任。分发构建使用适当的 Apple 签名身份：

```sh
CODE_SIGN_IDENTITY='Developer ID Application: …' CONFIGURATION=release make check
```

此命令只指定签名身份与构建配置；当前脚本没有发行所需的完整打包、公证和装订流程，不能据此宣称已完成对外发行验收。

`CODE_SIGN_IDENTITY` 可填写唯一身份名称或证书指纹；不要在钥匙串中创建多个同名身份。证书、私钥、密码、导出文件均不进入仓库。保留原身份；删除重建同名证书仍然是不同身份，可能需要重新授权。

没有签名身份的 CI / 临时预览可显式运行 `CODE_SIGN_IDENTITY=- make check`，此方式不保证更新保留授权，并会跳过持久身份检查。不要用它覆盖已经授权的日常使用构建。

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
