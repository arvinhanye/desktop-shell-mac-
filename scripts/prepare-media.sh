#!/bin/bash
# Prepare local runtime media. Source assets are read-only; unrelated outputs are retained.
set -euo pipefail
cd "$(dirname "$0")/.."
export LC_ALL=C

fail() { printf '错误：%s\n' "$*" >&2; exit 1; }

FORCE=false
case "${1:-}" in
  '') [[ $# -eq 0 ]] || fail '用法：scripts/prepare-media.sh [--force]' ;;
  --force) FORCE=true; shift ;;
  *) fail '用法：scripts/prepare-media.sh [--force]' ;;
esac
[[ $# -eq 0 ]] || fail '用法：scripts/prepare-media.sh [--force]'

for tool in ffmpeg ffprobe sips; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    case "$tool" in
      ffmpeg|ffprobe) fail "缺少 $tool；请先安装 ffmpeg（已安装 Homebrew 时运行 brew install ffmpeg）。" ;;
      sips) fail '缺少 sips；它由 macOS 自带，请检查 /usr/bin 是否在 PATH 中，或修复 macOS 系统工具。' ;;
    esac
  fi
done

for directory in video voice avatars ornaments backgrounds/start-menu backgrounds/folder backgrounds/settings; do
  [[ -d "assets/$directory" ]] || fail "缺少素材目录：assets/$directory"
done

# Resolve existing ancestors before mkdir, including symlinks and '..', so an
# accidental MEDIA_DIR inside assets never writes into the read-only source tree.
resolve_directory() {
  local input=$1 resolved=/ part
  local parts=()
  [[ "$input" == /* ]] || input="$PWD/$input"
  IFS=/ read -r -a parts <<< "$input"
  for part in "${parts[@]}"; do
    case "$part" in
      ''|.) continue ;;
      ..) resolved=${resolved%/*}; resolved=${resolved:-/} ;;
      *)
        resolved="${resolved%/}/$part"
        if [[ -e "$resolved" || -L "$resolved" ]]; then
          resolved=$(cd "$resolved" && pwd -P) || return 1
        fi
        ;;
    esac
  done
  printf '%s\n' "$resolved"
}

MEDIA_DIR=${MEDIA_DIR-"$HOME/Library/Application Support/DesktopShell/media"}
[[ -n "$MEDIA_DIR" && "$MEDIA_DIR" != *$'\n'* ]] || fail 'MEDIA_DIR 必须是非空、单行的目录路径。'
MEDIA_DIR=$(resolve_directory "$MEDIA_DIR") || fail 'MEDIA_DIR 不是有效目录路径。'
ASSETS_DIR=$(cd assets && pwd -P)
[[ "$MEDIA_DIR" != "$ASSETS_DIR" && "$MEDIA_DIR" != "$ASSETS_DIR/"* ]] || fail 'MEDIA_DIR 应位于 assets 之外。'

# Bash 3.2 arrays keep the conversion plan and credits in the same stable order.
# Numeric source names are enumerated numerically; other names use C-locale order.
sources=()
outputs=()
kinds=()
groups=()
credits=''
add() {
  local source=$1 output=$2 kind=$3 group=$4 line
  [[ -f "$source" && ! -L "$source" ]] || fail "缺少常规素材文件：$source"
  sources+=("$source")
  outputs+=("$output")
  kinds+=("$kind")
  groups+=("$group")
  if [[ "$group" == 3 ]]; then
    printf -v line '%s\t%s\n' "${output##*/}" "$source"
    credits+="$line"
  fi
}

add assets/video/Wallpaper.webm video/aemeath.mp4 video 0
for n in {1..54}; do add "assets/voice/($n).mp3" "voice/$n.mp3" copy 1; done
for n in {1..30}; do add "assets/avatars/$n.png" "avatars/$n.png" copy 2; done
for n in {1..56}; do
  printf -v name 'backgrounds/start-%02d.jpg' "$n"
  add "assets/backgrounds/start-menu/$n.png" "$name" jpeg 3
done
shopt -s nullglob
for category in folder settings; do
  files=(assets/backgrounds/"$category"/*.png)
  [[ ${#files[@]} -gt 0 ]] || fail "没有 PNG 素材：assets/backgrounds/$category"
  n=0
  for source in "${files[@]}"; do
    [[ "$source" != *$'\t'* && "$source" != *$'\n'* ]] || fail "素材路径包含制表符或换行：$source"
    n=$((n + 1))
    printf -v name 'backgrounds/%s-%02d.png' "$category" "$n"
    add "$source" "$name" png 3
  done
done
add assets/ornaments/heart.png ornaments/heart.png heart 4

labels=(video voice avatars backgrounds ornaments)
generated=(0 0 0 0 0)
skipped=(0 0 0 0 0)

# Refuse symlinked category directories rather than accidentally writing to assets
# or elsewhere. Each completed file is published atomically from our own staging
# directory; a failed conversion leaves the previous usable output untouched.
for directory in "${labels[@]}"; do
  target="$MEDIA_DIR/$directory"
  [[ ! -L "$target" ]] || fail "输出子目录是符号链接：$target"
  [[ ! -e "$target" || -d "$target" ]] || fail "输出子目录被文件占用：$target"
done
for output in "${outputs[@]}" backgrounds/CREDITS.txt; do
  target="$MEDIA_DIR/$output"
  [[ ! -L "$target" && ( ! -e "$target" || -f "$target" ) ]] || fail "输出目标不是常规文件：$target"
done
mkdir -p "$MEDIA_DIR"/{video,voice,avatars,backgrounds,ornaments}
STAGING=$(mktemp -d "$MEDIA_DIR/.prepare-media.XXXXXX")
trap 'rm -rf -- "$STAGING"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

credits_fresh=true
for ((i = 0; i < ${#sources[@]}; i++)); do
  source=${sources[i]}
  output="$MEDIA_DIR/${outputs[i]}"
  group=${groups[i]}
  if [[ "$group" == 3 && ! "$MEDIA_DIR/backgrounds/CREDITS.txt" -nt "$source" ]]; then
    credits_fresh=false
  fi
  if [[ "$FORCE" == false && -f "$output" && "$output" -nt "$source" ]]; then
    skipped[group]=$((skipped[group] + 1))
    continue
  fi
  printf '生成 %s\n' "${outputs[i]}"
  temporary="$STAGING/${output##*/}"
  case "${kinds[i]}" in
    video)
      ffmpeg -loglevel error -y -i "$source" -an \
        -vf "setparams=color_primaries=bt709:color_trc=bt709:colorspace=bt709,scale=2560:1440:flags=lanczos" \
        -c:v libx265 -preset slow -crf 22 -pix_fmt yuv420p -tag:v hvc1 \
        -color_primaries bt709 -color_trc bt709 -colorspace bt709 \
        -x265-params log-level=error -movflags +faststart \
        "$temporary"
      ;;
    copy) cp "$source" "$temporary" ;;
    jpeg|png)
      dimensions=$(sips -g pixelWidth -g pixelHeight "$source")
      width=''
      height=''
      while read -r property value; do
        case "$property" in
          pixelWidth:) width=$value ;;
          pixelHeight:) height=$value ;;
        esac
      done <<< "$dimensions"
      [[ "$width" =~ ^[1-9][0-9]*$ && "$height" =~ ^[1-9][0-9]*$ ]] || fail "读取素材尺寸失败：$source"

      # sips -Z also enlarges small images; only supply it above the limit.
      image_args=("$source" --out "$temporary")
      if ((width > 2400 || height > 2400)); then
        image_args=(-Z 2400 "${image_args[@]}")
      fi
      if [[ "${kinds[i]}" == jpeg ]]; then
        sips -s format jpeg -s formatOptions 90 "${image_args[@]}" >/dev/null
      elif ((width > 2400 || height > 2400)); then
        sips "${image_args[@]}" >/dev/null
      else
        cp "$source" "$temporary"
      fi
      ;;
    heart)
      sips -c 800 4800 "$source" --out "$temporary" >/dev/null
      sips -Z 2400 "$temporary" >/dev/null
      ;;
  esac
  mv -f "$temporary" "$output"
  generated[group]=$((generated[group] + 1))
done

output="$MEDIA_DIR/backgrounds/CREDITS.txt"
if [[ "$FORCE" == false && "$credits_fresh" == true && -f "$output" && "$(< "$output")" == "${credits%$'\n'}" ]]; then
  skipped[3]=$((skipped[3] + 1))
else
  printf '%s' "$credits" > "$STAGING/CREDITS.txt"
  mv -f "$STAGING/CREDITS.txt" "$output"
  generated[3]=$((generated[3] + 1))
fi

# Probe before reporting success: an unreadable video must fail the script.
video_info=$(ffprobe -v error -select_streams v:0 \
  -show_entries stream=codec_name,codec_tag_string,width,height,r_frame_rate:format=duration \
  -of default=noprint_wrappers=1 "$MEDIA_DIR/video/aemeath.mp4")
printf '\n素材目录：%s\n汇总（backgrounds 含 CREDITS.txt）：\n' "$MEDIA_DIR"
for ((i = 0; i < ${#labels[@]}; i++)); do
  printf '  %-12s 生成 %d，跳过 %d\n' "${labels[i]}" "${generated[i]}" "${skipped[i]}"
done
printf '视频信息：\n%s\n' "$video_info"
