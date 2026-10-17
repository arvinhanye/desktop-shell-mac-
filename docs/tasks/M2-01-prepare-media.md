# M2-01: 素材处理脚本 prepare-media.sh

- **状态**：todo
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
- **自测结果**：
- **疑问 / 偏离**：

<!-- ===== 以下由 Claude Code 填写 ===== -->

## 审查记录

- **结论**：
- **意见**：
