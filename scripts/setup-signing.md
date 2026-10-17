# 创建 DesktopShell 的自签名代码签名证书

只需要做**一次**。由用户亲手执行（涉及钥匙串，属于安全设置，Claude Code 和 Codex 都不代做）。

## 为什么需要

macOS 按签名里的"指定要求"（designated requirement）识别应用，用来决定系统权限（例如 M5.5 要用的"系统录音"）给谁：

- **ad-hoc 签名**（`codesign -s -`）：指定要求绑定代码哈希，每次重新编译都会变，系统会把它当成新应用，要重新授权。
- **固定证书签名**：指定要求绑定"bundle id + 证书"，重新编译也不变，授权一直有效。

## 会做什么

在你的**登录钥匙串**里添加一个名为 `DesktopShell Self-Signed` 的代码签名身份（证书 + 私钥），有效期 10 年，只用来签 DesktopShell。**不修改系统的证书信任设置**（第 5 步只在必要时才做）。

## 步骤

在终端里依次运行。

**1. 在临时目录里生成证书和私钥**（用系统自带的 `/usr/bin/openssl`，不要用 conda 或 Homebrew 的版本）：

```bash
cd "$(mktemp -d)"
```

```bash
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -keyout key.pem -out cert.pem -subj "/CN=DesktopShell Self-Signed" -addext "basicConstraints=critical,CA:false" -addext "keyUsage=critical,digitalSignature" -addext "extendedKeyUsage=critical,codeSigning"
```

```bash
/usr/bin/openssl pkcs12 -export -inkey key.pem -in cert.pem -out signing.p12 -passout pass:desktopshell -name "DesktopShell Self-Signed"
```

**2. 导入登录钥匙串**，并允许 `codesign` 使用这把私钥（可能会要求输入登录密码）：

```bash
security import signing.p12 -k ~/Library/Keychains/login.keychain-db -P desktopshell -T /usr/bin/codesign
```

看到 `1 identity imported.` 就成功了。

**3. 删除临时文件**（私钥已经在钥匙串里，磁盘上的副本不要留）：

```bash
rm -f key.pem cert.pem signing.p12 && cd ~
```

**4. 检查**：

```bash
security find-identity -p codesigning
```

在 `Matching identities` 下能看到 `"DesktopShell Self-Signed"` 即可。后面带着 `CSSMERR_TP_NOT_TRUSTED` 是**正常的**：自签名证书没有被系统信任，但签名不需要信任。

**5.（仅在需要时）设置信任**：如果之后 `scripts/bundle.sh` 报错 `DesktopShell Self-Signed: no identity found`，才做这一步：打开"钥匙串访问"→ 左侧"登录"→"我的证书"→ 双击 `DesktopShell Self-Signed` →展开"信任"→"代码签名"选"始终信任"→ 关闭窗口并输入密码。

## 第一次签名时的弹窗

第一次用这个证书签名时，系统可能弹出"codesign 想要使用钥匙串中的密钥签名"，输入登录密码后点**"始终允许"**，以后就不会再问。

## 撤销

不再需要时：打开"钥匙串访问"→"登录"→"我的证书"，删除 `DesktopShell Self-Signed`。之后 DesktopShell 只能用 ad-hoc 签名，系统权限在每次编译后都要重新授权。
