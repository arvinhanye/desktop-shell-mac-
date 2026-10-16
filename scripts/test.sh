#!/bin/bash
# 运行单元测试。
# 只装命令行工具时，Testing 框架在工具目录里，但 SwiftPM 默认找不到，需要手动加搜索路径。
# 装了完整 Xcode 并切换过去后，直接运行 swift test 即可。
set -euo pipefail
cd "$(dirname "$0")/.."

DEVDIR="$(xcode-select -p)"
if [[ "$DEVDIR" == *CommandLineTools* ]]; then
  FW="$DEVDIR/Library/Developer/Frameworks"
  LIB="$DEVDIR/Library/Developer/usr/lib"
  exec swift test \
    -Xswiftc -F -Xswiftc "$FW" \
    -Xlinker -F -Xlinker "$FW" \
    -Xlinker -rpath -Xlinker "$FW" \
    -Xlinker -rpath -Xlinker "$LIB" \
    "$@"
else
  exec swift test "$@"
fi
