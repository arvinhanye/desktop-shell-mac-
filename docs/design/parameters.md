# M3.5 参数表：美化包皮肤配置整理

> 来源：`~/Downloads/鸣潮-爱弥斯美化包.zip` 里的 `Skins/Ageo`、`Skins/Aemeath`、`Skins/prototype`、`Skins/Lano-VisualizerL`。只读取了 `.ini` / `.inc` 配置和字体文件，没有运行任何程序或脚本。
> Rainmeter 的 `FontSize` 是磅（pt），在 Windows 96 DPI 下 1 pt ≈ 1.33 px。原皮肤是按约 1920 宽的屏幕设计的，本机屏幕是 1792 × 1120 点（Retina 2 倍），尺寸大致可以按 1 pt → 1.33 CSS px 换算，再按实际效果微调。

## 1. 颜色

| 用途 | 原值（RGB, A/255） | 十六进制 / CSS | 出处 |
|---|---|---|---|
| 正文 | 255,255,255 | `#FFFFFF` | Ageo `Color1`，prototype `ColorText` / `ColorText2` |
| 强调色（角色名、大号日期渐变） | 250,192,207 | `#FAC0CF` | Ageo `Color2` |
| 卡片底色 | 230,138,161 @ 80 | `rgb(230 138 161 / 0.31)` | prototype `ColorBG` |
| 叠加白 | 255,255,255 @ 140 | `rgb(255 255 255 / 0.55)` | prototype `ColorBG2` |
| 律动条 | 173,225,255 | `#ADE1FF` | Lano-Visualizer `Color` |
| 细线 / 进度条 | 255,255,255；底轨 alpha 100 | `#FFFFFF` / `rgb(255 255 255 / 0.39)` | Ageo `MeterLine`，prototype `MeterRAMBar` |

壁纸主色（视频帧目测，见效果图页面里的取色）：深海军蓝夜空、靛紫、玫瑰粉长发、淡紫白、冰蓝光点。粉色 `#FAC0CF` 和冰蓝 `#ADE1FF` 都能在壁纸里找到对应。

## 2. 字体

| 字体 | 文件 | 原皮肤用途 |
|---|---|---|
| 思源宋体 SemiBold（Source Han Serif SC） | `Ageo/@Resources/Fonts/SourceHanSerifSC-SemiBold.otf` | 问候语、祝福语 |
| Gobold Bold | `Ageo/@Resources/Fonts/Gobold Bold.otf` | 超大号日期数字（只有拉丁字符） |
| Porter | `Ageo/@Resources/Fonts/Porter.otf` | 月份、时间、竖排星期（只有拉丁字符） |
| Google Sans Regular / Bold | `prototype/@Resources/Fonts/GoogleSans-*.ttf` | 卡片里的文字、CPU / 内存数值 |
| Emilea | `prototype/@Resources/Fonts/Emilea.otf` | 头像卡上的签名名字（手写体） |
| 备选：方正清刻本悦宋简体、东叔花园宋体、阿里巴巴普惠体 Heavy、思源黑体 ExtraLight | 同上 | 原皮肤没有直接用到 |

中文正文在原皮肤里没有专门的字体（Windows 默认是微软雅黑），Mac 上用系统的苹方（PingFang SC）。

## 3. 各皮肤的版式参数（原始数值）

### 问候语（Ageo / Time Of Day，`Scale=0.65`）

- 两行，**右对齐**，右边缘 x = 650。
- 第一行：`"<时段问候>, <名字>"`，思源宋体 30×0.65 = 19.5 pt，白色，名字用强调色 `#FAC0CF`。
- 第二行：祝福语，思源宋体 24×0.65 = 15.6 pt，白色，行距 10×0.65。
- 文案：00–05 深夜了 / 06–11 早上好 / 12–17 下午好 / 18–19 傍晚了 / 20–22 晚上好 / 23 深夜了；祝福语四种（见 `AGENTS.md` 配置示例）。

### 日期时间（Ageo / Time and Date，`Scale=1`）

- 日（`%d`）：Gobold Bold **250 pt**，文字本身透明，用强调色做 90° 竖向渐变：顶部 alpha 1/255 → 10% 处 220/255 → 50% 处保持（下半部分实、上半部分渐隐）。
- 月份：Porter 56 pt，白色，压在日期数字上（x 95, y 170）。
- 星期：Porter 12 pt，大写，字间距 7，**逆时针旋转 90° 竖排**，放在日期左边（x 45, y 435）。
- 时间：Porter 16 pt（x 100, y 260）；下面一条白色细线 85 × 1.5（x 100, y 300）。

### 头像卡（prototype / Profile）

- 粉色半透明矩形 115 × 150（x 23, y 22），描边 3 同色。
- 头像图 240 × 150 缩放成 **179 × 112**，放在 (−15, −3)，压在矩形上方：图片左边是手写签名、右边是圆形头像，圆形头像正好落在卡片的右上部。**原皮肤是整张显示，不裁切。**
- 名字：Emilea 9 pt，大写，字间距 1，右对齐；下面一行"Wuthering"，Emilea 8 pt。配置里的名字是 `Waves`。

### 面板（prototype / CPU & RAM、Menu、Links）

- 形状：矩形，**圆角 1**（几乎直角），填充 `ColorBG`，描边 5 同色（等于把底色向外扩 5 当作内边距）。
- CPU / 内存：图标 25 × 25；标题 Google Sans 11 pt；数值 Google Sans Bold 11 pt；进度条 100 × 3，前景白色、底轨白色 alpha 100。
- 菜单：图标 30 × 30，横排（258 × 50）或竖排（125 × 158）。
- 链接：Google Sans Bold 9 pt，大写。

### 心形装饰条（Aemeath）

- 图片 `1.png`，显示 540 × 540（原图是方形画布，心和翅膀在中间一条）；运行时素材已裁成 2400 × 400 的 `ornaments/heart.png`。

### 律动条（Lano-VisualizerL）

- 每侧 12 根，柱宽 10，间距 3，最高 134；颜色 `#ADE1FF`。
- FFT 4096、重叠 2048、上升 100 ms、衰减 60 ms、20–16500 Hz、灵敏度 18（`AGENTS.md` 已采用）。

## 4. 背景图库

- `start-01` … `start-56`（JPEG）：整幅插画，多为竖幅（例如 1917 × 2217），粉、白、蓝色调。
- `folder-01` … `folder-06`（PNG，透明背景）：726 × 660 的角色立绘，中间一条粉色"Aemeath"横幅。
- `settings-01`（PNG）：2400 × 1784，偏淡的水印风格。

## 5. 本机条件

- 屏幕 1792 × 1120 点（3072 × 1920 像素，2 倍），菜单栏 30，程序坞 85，可用区域 1792 × 1005。
- 桌面 70 个项目，图标 64 点、网格间距 54、按添加日期排列，访达从右上角往下、往左排。
