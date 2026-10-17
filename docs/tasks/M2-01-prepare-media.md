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
  | `backgrounds/start-<NN>.jpg` | `backgrounds/start-menu/<N>.png` | 转 JPEG，`-s formatOptions 90`；**只缩不放**：长边超过 2400 才 `-Z 2400`（见下方说明）；NN 为两位数（01–56），按数字顺序编号（不是字符串顺序） |
  | `backgrounds/folder-<NN>.png` | `backgrounds/folder/*.png` | **保持 PNG**（这些是 70% 透明的角色立绘，转 JPEG 后透明区域会变白）；只缩不放，规则同上；按原文件名排序后编号 01–06 |
  | `backgrounds/settings-01.png` | `backgrounds/settings/*.png` | 同上，保持 PNG |

  **只缩不放**（审查后修订）：`sips -Z N` 遇到小于 N 的图会**放大**，所以必须先用 `sips -g pixelWidth -g pixelHeight` 读出原图尺寸，长边大于 2400 时才加 `-Z 2400`，否则保持原尺寸（PNG 原样复制或只做格式转换）。按现有素材，预期结果是：`start-*.jpg` 保持 1917×2217（个别 1917×2231），`folder-*.png` 保持 726×660，`settings-01.png` 缩到 2400×1784 左右。
  | `backgrounds/CREDITS.txt` | — | 每行一条 `<输出文件名>\t<原文件相对路径>`，保留原画师署名 |

  视频转码命令（照抄，Claude Code 已验证 AVFoundation 能播放，HEVC 在本机可以硬件解码）：

  ```bash
  ffmpeg -loglevel error -y -i "$SRC" -an \
    -vf "setparams=color_primaries=bt709:color_trc=bt709:colorspace=bt709,scale=2560:1440:flags=lanczos" \
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
  - [ ] `sips -g pixelWidth -g pixelHeight` 读 `ornaments/heart.png` 为 2400×400；任意一张背景图的长边不超过 2400
  - [ ] **没有任何图被放大**：每张输出背景图的宽高都不大于对应原图（按 `CREDITS.txt` 逐张对照）；`start-01.jpg` 为 1917×2217，`folder-01.png` 为 726×660
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

### 第二轮（2026-10-17）

- **改动摘要**：
  - 按修订要求，JPEG/PNG 处理前读取并校验原图宽高，任一边超过 2400 才传 `-Z 2400`；未超限的 PNG 原样复制，JPEG 仅转换格式，质量调整为 90。
  - 尺寸读取失败或返回非法尺寸时立即退出，继续沿用暂存/原子替换机制，保留旧输出。视频滤镜中的 `setparams`、心形裁剪、语音、头像及编号规则均保持原样。
- **自测结果**（本轮结果替代上轮的旧缩放规则和色彩观察）：
  - 回归测试先复现旧实现的 5 项失败，再确认修复后全部通过：start-01 为 1917×2217，folder-01 为 726×660，settings-01 为 2400×1784；start-01 与独立 `sips -s format jpeg -s formatOptions 90` 转换逐字节一致；小 PNG 与源文件逐字节一致。
  - `bash -n scripts/prepare-media.sh`、`git diff --check` 通过；`MEDIA_DIR=/tmp/ds-media-test scripts/prepare-media.sh --force` 退出 0，耗时 **149.35 秒**，150 个产物全部生成、零跳过。
  - 修订后的完整素材验收通过：54 条语音、30 张头像、56 张 JPEG、7 张 PNG、2400×400 心形图、63 行署名表及文件名检查全部符合要求。按署名表逐张对照，**63/63 张背景的宽高均不超过对应原图，长边均 ≤2400**；未超限图片尺寸保持不变，6 张 folder PNG 均与原图逐字节一致，7 张 PNG 的 alpha 均保留。
  - 视频仍为 HEVC/hvc1、2560×1440、30fps、30 秒，无音轨；`color_space`、`color_transfer`、`color_primaries` 三项均为 **bt709**，第一轮修正保持生效。
  - 立即增量执行退出 0，150 个产物全部跳过，耗时 **0.12 秒**；产物时间戳和大小保持不变，额外用户文件仍保留。
  - 2400 像素边界原样复制、2401 像素缩到 2400、非法尺寸和工具读取失败四项检查通过；异常时旧产物保持不变、暂存目录已清理。边界夹具首次因复制后的输出较新而触发跳过，明确标为过期后重测通过，未因此调整产品逻辑。原有 14 项异常路径检查也通过。
  - `scripts/test.sh`：**9/9 通过**；149 个源文件 SHA-256 与此前清单一致。测试与日志在 `/tmp/ds-m2-01-validation/round2/`；本轮只改脚本及本任务单状态、交付记录，需求部分和审查记录内容保持不变。
- **剩余事项**：旧运行时素材需执行 `scripts/prepare-media.sh --force` 才会应用新参数；本次仅重建 `/tmp/ds-media-test/`。默认运行时目录的更新、QuickTime 播放效果及 Finder 清晰度/透明效果仍由用户手动确认；原始小图的 AI 放大留待 M3.5。

<!-- ===== 以下由 Claude Code 填写 ===== -->

## 审查记录

- **结论**：**需修改**（第二轮）。用户目测发现部分背景图像素偏低；查明是任务单的缩放规则有误，需求部分已修订，请 Codex 按下方"修改要求"更新脚本。
- **修改要求**（第二轮，2026-10-17）：
  1. **只缩不放**：`sips -Z N` 会把小图放大。6 张 `folder-*.png` 被从 726×660 放大到 1600×1454，所以发糊。改成先读原图尺寸，长边大于上限才缩小，否则保持原尺寸。
  2. **上限从 1600 改为 2400，JPEG 质量从 82 改为 90**：`start-*.jpg` 的原图只有 1917×2217，不该再缩小。
  3. 按修订后的"验收标准"重新自测，特别是新增的"没有任何图被放大"一项。用 `--force`，或者换一个新的 `MEDIA_DIR` 重新生成。
  4. 修改后推送分支，状态改回 `review`，在交付记录末尾追加"第二轮"小节，说明改了什么和自测结果。不要改动 Claude Code 第一轮加的 `setparams` 色彩修正。
  - 原图本身就小的立绘（726px）和头像（240px）**不在本任务处理**，M3.5 定了显示尺寸后再决定要不要用 AI 放大。
- **第一轮结论**：代码审查通过；Claude Code 修正了视频的色彩标记（见下），可执行检查全部通过。
- **Claude Code 的修改**（按"审查时可修正明显问题并注明"）：
  - Codex 指出 `-color_trc bt709` 没有生效，输出仍然标记为 `bt470m`。原因是 ffmpeg 优先使用输入帧自带的色彩属性。这是任务单给的命令有缺陷，不是 Codex 的问题。
  - 实测影响：标记为 `bt470m` 时，AVFoundation 无法识别，解出的帧没有色彩空间（按未标记处理，显示效果取决于渲染路径）；改标为 bt709 后识别为 `kCGColorSpaceCoreMedia709`，色彩管理行为明确，亮度差约 5%。原片 `bt470m` 配 `bt709` 原色和矩阵的组合，基本可以判断是标错了。
  - 修改：在滤镜链最前面加 `setparams=color_primaries=bt709:color_trc=bt709:colorspace=bt709`。脚本只改这一行，任务单里的命令同步更新。
- **复验结果**（Claude Code，2026-10-17；用全新目录 `/tmp/ds-media-review` 从零生成，没有复用 Codex 的产物）：
  - [x] `bash -n` 通过；首次运行退出码 0，耗时 131 秒
  - [x] 数量：语音 54、头像 30、背景 JPEG 56 / PNG 7、心形图 1；`CREDITS.txt` 63 行，带原画师 ID 的文件名完整保留
  - [x] 文件名规则检查没有输出
  - [x] 视频：hevc / hvc1、2560×1440、30fps、30.0 秒、没有音轨、14.5MB；色彩标记三项都是 bt709，AVFoundation 识别为 Rec.709
  - [x] 心形图 2400×400；背景长边最大 1600；`folder-01.png` 有 alpha
  - [x] 54 条语音和 30 张头像与源文件逐字节一致
  - [x] 立即重跑：全部跳过，0.12 秒
  - [x] `git diff --name-only`：只有脚本和本任务单
- **意见**：
  - 脚本质量超出要求：先写暂存目录再原子替换，转码失败不会破坏旧文件；防止输出目录被误指到 `assets/`（包括 `..` 和符号链接）；兼容 Bash 3.2。
  - 关于工具约束：`dirname/mkdir/mktemp/cp/mv/rm` 属于系统自带的基础命令，符合"bash 自带命令"这条要求的本意，**认可**。
  - 关于"新增或重命名素材后要用 `--force`"：认可，记在这里备查。
  - 输出的 mp4 里有一条 ffmpeg 自动加的 `tmcd`（时间码）数据轨，对播放没有影响，不处理。
