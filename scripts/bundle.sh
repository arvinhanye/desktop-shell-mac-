#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

fail() { printf '错误：%s\n' "$*" >&2; exit 1; }
usage() { printf '用法：scripts/bundle.sh [--debug] [--adhoc] [--open]\n'; }

CONFIGURATION=release
ADHOC=false
OPEN_APP=false
for argument in "$@"; do
  case "$argument" in
    --debug) CONFIGURATION=debug ;;
    --adhoc) ADHOC=true ;;
    --open) OPEN_APP=true ;;
    *) usage >&2; fail "未知参数：$argument" ;;
  esac
done

SIGN_IDENTITY=${DESKTOPSHELL_SIGN_IDENTITY-DesktopShell Self-Signed}
if [[ "$ADHOC" == true ]]; then
  SIGN_IDENTITY=-
  printf '警告：ad-hoc 签名每次编译都会变，系统权限需要重新授权，仅用于测试\n' >&2
else
  # Untrusted self-signed identities are usable; -v would filter them out.
  identities=$(security find-identity -p codesigning) || fail '读取代码签名身份失败。'
  if [[ -z "$SIGN_IDENTITY" ]] || ! grep -Fq -- "\"$SIGN_IDENTITY\"" <<< "$identities"; then
    fail "未找到签名身份：${SIGN_IDENTITY}；请先按 scripts/setup-signing.md 创建证书，或用 --adhoc 测试"
  fi
fi

BUILD_DIR="$PWD/build"
APP="$BUILD_DIR/DesktopShell.app"
[[ ! -L "$BUILD_DIR" && ( ! -e "$BUILD_DIR" || -d "$BUILD_DIR" ) ]] || fail 'build 必须是普通目录。'
[[ ! -L "$APP" && ( ! -e "$APP" || -d "$APP" ) ]] || fail 'build/DesktopShell.app 必须是普通目录。'

swift build -c "$CONFIGURATION"
BIN_DIR=$(swift build -c "$CONFIGURATION" --show-bin-path)
[[ -x "$BIN_DIR/DesktopShell" ]] || fail "缺少可执行编译产物：$BIN_DIR/DesktopShell"
if ! BUILD_NUMBER=$(git rev-list --count HEAD 2>/dev/null); then BUILD_NUMBER=1; fi

mkdir -p "$BUILD_DIR"
STAGING=$(mktemp -d "$BUILD_DIR/.bundle.XXXXXX")
CANDIDATE="$STAGING/DesktopShell.app"
BACKUP="$STAGING/previous.app"
cleanup() {
  local status=$?
  trap - EXIT
  # Both renames stay on the same filesystem. Restore the old app if publication fails.
  if [[ -d "$BACKUP" && ! -e "$APP" && ! -L "$APP" ]]; then
    if ! mv "$BACKUP" "$APP"; then
      printf '错误：恢复旧应用失败；旧应用保留在 %s\n' "$BACKUP" >&2
      exit 1
    fi
  fi
  if [[ "$status" -ne 0 && -d "$BACKUP" ]]; then
    printf '旧应用备份保留在：%s\n' "$BACKUP" >&2
  else
    rm -rf -- "$STAGING" || printf '警告：临时目录清理失败：%s\n' "$STAGING" >&2
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

CONTENTS="$CANDIDATE/Contents"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources/web"
cp "$BIN_DIR/DesktopShell" "$CONTENTS/MacOS/DesktopShell"
rsync -a --exclude='.DS_Store' web/ "$CONTENTS/Resources/web/"
printf 'APPL????' > "$CONTENTS/PkgInfo"
cat > "$CONTENTS/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>local.desktopshell.DesktopShell</string>
  <key>CFBundleName</key><string>DesktopShell</string>
  <key>CFBundleDisplayName</key><string>DesktopShell</string>
  <key>CFBundleExecutable</key><string>DesktopShell</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAudioCaptureUsageDescription</key><string>DesktopShell 读取系统正在播放的声音的频谱，用来驱动桌面上的音频律动条；不录制、不保存任何音频。</string>
</dict>
</plist>
EOF
plutil -lint "$CONTENTS/Info.plist"
codesign --force --timestamp=none --sign "$SIGN_IDENTITY" "$CANDIDATE"
codesign --verify --strict --verbose=2 "$CANDIDATE"
codesign -d -r- "$CANDIDATE"

# Only replace the old bundle after every assembly and signature check has succeeded.
if [[ -d "$APP" ]]; then mv "$APP" "$BACKUP"; fi
mv "$CANDIDATE" "$APP"
printf '\n已打包：%s（%s）\n' "$APP" "$CONFIGURATION"

if [[ "$OPEN_APP" == true ]]; then
  if pkill -x DesktopShell; then
    :
  else
    status=$?
    [[ "$status" -eq 1 ]] || fail "结束 DesktopShell 失败（退出码 ${status}）。"
  fi
  # LaunchServices may reactivate the old instance until it has actually exited.
  for ((attempt = 0; ; attempt++)); do
    if pgrep -x DesktopShell >/dev/null; then
      [[ "$attempt" -lt 50 ]] || fail '等待 DesktopShell 退出超时（5 秒）。'
      sleep 0.1
    else
      status=$?
      [[ "$status" -eq 1 ]] || fail "检查 DesktopShell 进程失败（退出码 ${status}）。"
      break
    fi
  done
  open "$APP"
  printf '%s\n' '查看日志：' '/usr/bin/log stream --style compact --predicate '\''subsystem == "local.desktopshell.DesktopShell"'\'''
fi
