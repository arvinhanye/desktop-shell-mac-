# M4-11: 播放语音时的头像光环

- **状态**：todo（**暂缓**：用户 2026-10-19 决定先跳过，等用户说做再交给 Codex；不阻塞 M4-08、M4-09）
- **里程碑**：M4
- **依赖**：M4-07（已合并：本任务改它新建的 `character.js`、`character.css`）
- **分支**：task/M4-11

<!-- ===== 以下需求部分由 Claude Code 编写，Codex 不修改 ===== -->

## 目标

点头像播放语音时，只沿**圆形头像外圈**亮起一圈冰蓝色的光环并缓慢呼吸，签名和头像图里其他地方不再零散发光。放完光环淡出。

## 背景与约束

- **为什么改**：M4-07 复审时用户发现播放语音时头像"边缘随机发光"。原定稿用 `filter: drop-shadow` 给整张头像组合图做脉冲光，`drop-shadow` 沿图片的透明度轮廓发光，而头像素材本身有不少半透明的部分（签名柔边、圆框内侧的半透明斑块、圆外的淡光晕和星星），光从这些地方透出来就显得零散。用户 2026-10-19 确认改成光环，定稿已更新（`main` 上的 `40f2891`）。
- **新的定稿**（先读）：
  - `docs/design/tokens.css`：`--glow-voice` 改成光环用的 `box-shadow`（细亮边加柔光）；新增 `--avatar-ring-x`、`--avatar-ring-y`、`--avatar-ring-size`（圆形头像在 240 × 150 组合图里的位置和直径，30 张头像的圆都在这里）、`--voice-ring-dim`、`--ease-breathe`；`--duration-voice-pulse` 改成 1600ms。
  - `docs/design/design.css` 的 `character.css` 一节：去掉 `.avatar-button.playing img` 的动画；新增 `.avatar-ring` 和 `.avatar-button.playing .avatar-ring`，`@keyframes voice-pulse` 改成只变透明度。
  - `docs/design/index.html`：头像按钮里在 `img` 后面加了 `<span class="avatar-ring" aria-hidden="true"></span>`。
  - 效果图（`http://127.0.0.1:8765/design/index.html`）的控制栏有"播放语音"，可以一直保持播放中的样子对照。
- 播放状态的逻辑不变：仍然是角色卡订阅 `voicePlaying`、切换 `.avatar-button` 的 `playing` class。语音组件（`voice.js`）不动。
- 暂停动画（`:root[data-paused]`）时 CSS 动画会停住；光环在播放中默认全亮、动画只负责变暗，所以暂停时停在当时的亮度（至少 35%），不会消失。这是定稿的设计，不用另外处理。

### 1. 样式

- `docs/design/tokens.css` 原样复制成 `web/styles/tokens.css`。
- `docs/design/design.css` 里 `character.css` 那一节原样复制成 `web/widgets/character.css`。

### 2. 角色卡 DOM（`web/widgets/character.js`）

- 在头像按钮里、`img` 后面加一个 `span.avatar-ring`，`aria-hidden="true"`，和定稿 `index.html` 一样。只是装饰，不放文字，不加事件。

### 3. 测试

- 在角色卡的测试里（M4-07 放在 `Tests/web/appearance.test.mjs` 的 `character:` 几条；也可以新建 `Tests/web/character.test.mjs`）：头像按钮里有且只有一个 `span.avatar-ring`，`aria-hidden` 为 `"true"`，在 `img` 后面；`voicePlaying` 变化时 `playing` class 照常切换。

## 允许修改的文件

- `web/styles/tokens.css`、`web/widgets/character.css`、`web/widgets/character.js`（修改）
- `Tests/web/appearance.test.mjs`（修改）或 `Tests/web/character.test.mjs`（新建）
- 本任务单的"交付记录"和"状态"

## 不许做

- 遵守 AGENTS.md "不要做的事"。
- 不改 `voice.js`、`appearance.js` 和别的组件；不改 `docs/design/`。
- 不用 `filter: drop-shadow` 做语音光；不在 JS 里算光环的位置或尺寸（都在 tokens 里）。

## 验收标准

**可执行的检查**（Codex 自测，Claude Code 复验）：

- [ ] `cmp docs/design/tokens.css web/styles/tokens.css` 没有输出
- [ ] 下面的命令没有输出：

  ```bash
  awk -v t=web/widgets/character.css 'index($0, "/* ====") == 1 { f = (index($0, t) > 0); next } f' docs/design/design.css | diff -B - web/widgets/character.css
  ```

- [ ] `grep -rn "drop-shadow(var(--glow-voice))" web/` 没有输出
- [ ] `scripts/test-web.sh` 全部通过，包含上面的新测试
- [ ] `git diff --name-only main...task/M4-11` 只包含"允许修改的文件"
- [ ] （Claude Code 复验）浏览器打开 `http://127.0.0.1:8765/`，给头像按钮加上 `playing`：`.avatar-ring` 相对头像图片在 (91, 1)、145 × 145，`box-shadow` 和效果图一致，动画是 `voice-pulse 1.6s`；去掉 `playing` 后透明度回到 0

**用户手动验证**（`scripts/bundle.sh --open`）：

- [ ] 点头像播放语音 → 只有圆形头像外圈一圈冰蓝色光环在缓慢呼吸，签名和圆里面不发光；放完光环淡出
- [ ] 在外观面板里换几张头像（包括 2 号这种圆外有星星的、28–30 号这种圆里是白色图标的）再点头像 → 光环都正好套在圆上
- [ ] 菜单栏"暂停动画"后点头像 → 有声音，光环亮着（不呼吸）

<!-- ===== 以下由 Codex 填写 ===== -->

## 交付记录

- **改动摘要**：
- **自测结果**：
- **疑问 / 偏离**：

<!-- ===== 以下由 Claude Code 填写 ===== -->

## 审查记录

- **结论**：
- **意见**：
