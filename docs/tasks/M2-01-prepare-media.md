# M2-01: 素材处理脚本 prepare-media.sh

- **状态**：review
- **里程碑**：M2
- **依赖**：无（`assets/` 已由 Claude Code 从美化包解压好）
- **分支**：task/M2-01

<!-- ===== 以下需求部分由 Claude Code 编写，Codex 不修改 ===== -->

## 目标

运行 `scripts/prepare-media.sh` 后，把 `assets/` 里的原始素材处理成运行时素材，放到 `~/Library/Application Support/DesktopShell/media/`。视频转成 AVPlayer 能硬件解码的 HEVC，图片缩到合适的尺寸，语音复制并统一命名。

## 背景与约束

- 先读 `AGENTS.md` 的"运行时素材目录""素材来源""设计规范"。
- `assets/` 不进 git，内容已经准备好，**只读，不要修改或删除里面的文件**：

  ```
  assets/
  ├── video/Wallpaper.webm          # 3840×2160 VP9 30fps 30 秒，带 Opus 音轨
  ├── voice/(1).mp3 … (54).mp3      # 54 条语音，1–41 秒
  ├── avatars/1.png … 30.png        # 240×150，自带签名和圆框，原样使用
  ├── ornaments/heart.png           # 5504×3072 透明 PNG，内容在中间一条
  └── backgrounds/
      ├── start-menu/1.png … 56.png # 约 1917×2217 透明 PNG
      ├── folder/*.png              # 6 张，文件名里带原画师 ID（如 "@거품.png"）
      └── settings/设置背景.png      # 2883×2143
  ```

- 输出目录默认为 `$HOME/Library/Application Support/DesktopShell/media`，可以用环境变量 `MEDIA_DIR` 覆盖（方便测试）。
- **所有输出文件名只能由 `[A-Za-z0-9_-]` 加扩展名组成**，因为文件名就是 id，后续 bridge 会按这个规则校验 id。
- 处理规则（参数都已由 Claude Code 实测确认）：

  | 输出 | 来源 | 处理 |
  |---|---|---|
  | `video/aemeath.mp4` | `video/Wallpaper.webm` | 见下方 ffmpeg 命令 |
  | `voice/<N>.mp3` | `voice/(N).mp3` | 原样复制，文件名去掉括号：`(12).mp3` → `12.mp3` |
  | `avatars/<N>.png` | `avatars/<N>.png` | 原样复制 |
  | `ornaments/heart.png` | `ornaments/heart.png` | `sips -c 800 4800`（居中裁剪，已确认能完整包住内容），再 `sips -Z 2400`，得到 2400×400 |
  | `backgrounds/start-<NN>.jpg` | `backgrounds/start-menu/<N>.png` | `sips -Z 1600 -s format jpeg -s formatOptions 82`；NN 为两位数（01–56），按数字顺序编号（不是字符串顺序） |
  | `backgrounds/folder-<NN>.png` | `backgrounds/folder/*.png` | `sips -Z 1600`，**保持 PNG**（这些是 70% 透明的角色立绘，转 JPEG 后透明区域会变白）；按原文件名排序后编号 01–06 |
  | `backgrounds/settings-01.png` | `backgrounds/settings/*.png` | 同上，保持 PNG |
  | `backgrounds/CREDITS.txt` | — | 每行一条 `<输出文件名>\t<原文件相对路径>`，保留原画师署名 |

  视频转码命令（照抄，Claude Code 已验证 AVFoundation 能播放，HEVC 在本机可以硬件解码）：

  ```bash
  ffmpeg -loglevel error -y -i "$SRC" -an \
    -vf "scale=2560:1440:flags=lanczos" \
    -c:v libx265 -preset slow -crf 22 -pix_fmt yuv420p -tag:v hvc1 \
    -color_primaries bt709 -color_trc bt709 -colorspace bt709 \
    -x265-params log-level=error -movflags +faststart \
    "$OUT"
  ```

  完整转码大约需要 2 分钟，生成约 16MB 的文件。

- 脚本要求：
  - `#!/bin/bash`，`set -euo pipefail`，脚本开头 `cd` 到仓库根目录（和 `scripts/test.sh` 写法一致）。
  - 开头检查 `ffmpeg`、`ffprobe`、`sips` 都存在，缺一个就报错退出，并提示怎么安装。
  - 检查 `assets/` 的各个子目录都存在，缺失就报错退出。
  - **增量执行**：输出文件已存在且比源文件新时跳过（视频转码很慢）；传 `--force` 时全部重新生成。
  - 不删除输出目录里的其他文件（以后可能有用户自己放的素材）。
  - 结束时打印汇总：每个子目录生成或跳过了多少个文件，以及视频的编码、分辨率、时长（用 ffprobe 读出来）。
- 本任务**不写 Swift 代码**。

## 允许修改的文件

- `scripts/prepare-media.sh`（新建，`chmod +x`）
- 本任务单的"交付记录"和"状态"

## 不许做

- 遵守 AGENTS.md "不要做的事"。
- 不修改、不删除 `assets/` 里的任何文件，不把 `assets/` 或 `media/` 里的东西加进 git。
- 不使用 `assets/` 之外的任何来源，不联网下载。
- 除 ffmpeg、ffprobe、sips 和 bash 自带命令之外，不引入其他工具（例如 ImageMagick、Python 包）。

## 验收标准

**可执行的检查**（Codex 自测，Claude Code 复验）：

- [ ] `bash -n scripts/prepare-media.sh` 通过
- [ ] `MEDIA_DIR=/tmp/ds-media-test scripts/prepare-media.sh` 退出码 0，然后：
  - [ ] `ls /tmp/ds-media-test/voice | wc -l` 为 54，`avatars` 为 30；`backgrounds` 下 `.jpg` 为 56、`.png` 为 7（6+1）；`ornaments/heart.png` 存在
  - [ ] `sips -g hasAlpha` 读 `backgrounds/folder-01.png`，结果为 `yes`
  - [ ] `ls -R /tmp/ds-media-test | grep -vE '^[A-Za-z0-9_-]+\.(mp4|mp3|png|jpg|txt)$|^$|:$|^[a-z]+$'` 没有输出（所有文件名符合规则）
  - [ ] `ffprobe` 读 `video/aemeath.mp4`：`codec_name=hevc`、`codec_tag_string=hvc1`、2560×1440、30fps、时长约 30 秒、**没有音轨**
  - [ ] `sips -g pixelWidth -g pixelHeight` 读 `ornaments/heart.png` 为 2400×400；任意一张背景图的长边不超过 1600
  - [ ] `backgrounds/CREDITS.txt` 有 63 行
- [ ] 立即再运行一次（不带 `--force`）：退出码 0，汇总显示全部跳过，用时少于 5 秒
- [ ] `git status --short` 只显示 `scripts/prepare-media.sh` 和本任务单

**用户手动验证**：

- [ ] 运行 `scripts/prepare-media.sh`（使用默认目录），然后 `open ~/Library/Application\ Support/DesktopShell/media/video/aemeath.mp4`，用 QuickTime 播放流畅、颜色正常
- [ ] 在访达里打开 `media/backgrounds/`，用空格键预览几张 `start-*.jpg` 和 `folder-*.png`：图片清晰，`folder-*.png` 背景透明

<!-- ===== 以下由 Codex 填写 ===== -->

## 交付记录

- **改动摘要**：
  - 在 `task/M2-01` 新增可执行的 `scripts/prepare-media.sh`，兼容系统 Bash 3.2；支持默认目录、`MEDIA_DIR`、严格按源文件时间增量跳过及 `--force`。
  - 按任务单原参数处理视频和图片；语音、头像逐字节复制；输出 ASCII id，数字序号按数值排列，其他文件按 `LC_ALL=C` 文件名顺序编号，生成保留完整原文件名的 63 行署名表。
  - 转码/复制先写独立暂存目录，成功后逐文件替换；失败保留旧产物，退出只清理本次暂存文件。提前检查工具、目录、源文件及输出类型，防止输出路径指回 `assets/`。
- **自测结果**（2026-10-17）：
  - `bash -n scripts/prepare-media.sh` 通过；权限为 `100755`。
  - 从仓库外启动，`MEDIA_DIR=/tmp/ds-media-test scripts/prepare-media.sh` 首次执行退出 0：视频 1、语音 54、头像 30、背景 JPEG 56 / PNG 7、装饰图 1，另有 `CREDITS.txt` 63 行；共 150 个生成文件。任务单的文件名筛选命令无输出。
  - `ffprobe`：`hevc` / `hvc1`、2560×1440、30/1 fps、30.000000 秒，无音轨；`ffmpeg -v error -i /tmp/ds-media-test/video/aemeath.mp4 -map 0:v:0 -f null -` 完整解码通过。
  - `sips`：心形图 2400×400，全部 63 张背景的长边均 ≤1600；6 张 folder 和 1 张 settings 均保留 alpha。54 条语音、30 张头像用 `cmp` 对照源文件一致；署名表前 56 行按 1–56 数值顺序逐行校验通过。
  - 立即再次运行退出 0，150 个文件全部跳过，耗时 **0.11 秒**（`/usr/bin/time -p`）；全部产物的修改时间和大小未变。
  - 增量边界通过：仅令 `voice/12.mp3` 过期后只重建该文件；署名表内容损坏后单独修复；额外放入的用户文件保持不变；临时 `HOME` 下验证默认目录及含空格路径。
  - 14 项异常路径检查通过：未知/多余/空参数、空 `MEDIA_DIR`、三个工具分别缺失、素材目录或文件缺失、输出指向源目录（含 `..` 和符号链接）、输出子目录符号链接、模拟转码中途失败。失败转码保留旧文件且暂存目录已清理。
  - `MEDIA_DIR=/tmp/ds-media-test scripts/prepare-media.sh --force` 退出 0，耗时 163.53 秒；150 个产物全部重新生成、零跳过，修改时间均晚于运行前标记，额外用户文件保持不变；重建后重新跑完整素材验收通过，149 个源文件 SHA-256 仍一致。
  - `scripts/test.sh`：9/9 通过。首次执行受沙盒编译缓存写入权限影响；通过权限流程原样重试后通过，没有修改工具链、测试或配置。
  - 149 个源文件 SHA-256 均与执行前一致。测试脚本和日志保留在 `/tmp/ds-m2-01-validation/`，未向仓库增加测试辅助文件；差异仅涉及本脚本和本任务单的状态、交付记录。
- **疑问 / 偏离**：
  - 工具约束解释：媒体处理仅依赖 ffmpeg、ffprobe、sips；与现有测试脚本一致使用系统 `dirname`，并使用 macOS 自带 `mkdir/mktemp/cp/mv/rm` 创建目录、原样复制、原子替换及清理暂存文件，没有安装其他工具。请审查确认该口径。
  - 当前针对任务单给定的固定素材集。以后新增或重命名 folder/settings 素材导致排序编号变化时，应使用 `--force`，避免旧编号产物被时间戳规则跳过。
  - 补充观察：严格沿用指定 ffmpeg 命令后，本机 `ffprobe` 读取源和输出的 `color_transfer` 均为 `bt470m`，虽然命令中包含 `-color_trc bt709`；`color_space` 和 `color_primaries` 均为 `bt709`。未自行调整既定转码参数，颜色仍交由 QuickTime 目测确认。
  - 用户手动项待验证：运行默认目录的脚本，再按验收步骤用 QuickTime 检查流畅度/颜色，用 Finder 预览图片清晰度及透明背景。本次真实产物位于 `/tmp/ds-media-test/`；没有写入用户真实的默认运行时目录。

<!-- ===== 以下由 Claude Code 填写 ===== -->

## 审查记录

- **结论**：
- **意见**：
