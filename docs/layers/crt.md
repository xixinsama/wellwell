# CRT 屏幕效果（CanvasLayer 128）

这一层的全部内容：`scenes/ui/crt_overlay.tscn`（一个 `CanvasLayer` + 一张全屏 `ColorRect`）和 `scripts/shaders/crt_screen.gdshader`（一个 `canvas_item` 片元着色器）。开关只有一个：视频设置里的 `crt_enabled`。

## 它在整个画面里的位置

世界先在 `SubViewport` 里画完（主场景 322×182，`scenes/app/main.tscn:56-62`），再由 `SubViewportContainer` 按 `stretch_shrink = 4` 放大（`scenes/app/main.tscn:44-53`）；`CrtOverlay` 是 `CanvasLayer`、`layer=128`（`scenes/app/main.tscn:78`、`scenes/ui/crt_overlay.tscn:9`），排在放大之后的最上层。

所以它工作在**最终画面像素**上：shader 用 `SCREEN_UV`（`scripts/shaders/crt_screen.gdshader:25`），画布固定 1280×720（`project.godot:30-33` 的 `stretch/mode="viewport"`，与实际窗口大小无关），一个设计像素 = 4 个画布像素。它不接收鼠标（`mouse_filter = 2`，`scenes/ui/crt_overlay.tscn:19`）。

它不只在主场景里：关卡 runner 也自己挂一份，`scenes/levels/test_world/runners/light_lab_runner.tscn:44` 实例化 `scenes/ui/crt_overlay.tscn`（那个场景的子视口是 320×180，`runners/light_lab_runner.tscn:30-34`）。

`source_size` 用来把扫描线/掩罩/色偏的周期折回设计像素。**它没有被覆盖**：两份 `ShaderMaterial` 都只写了 `shader`（`scenes/ui/crt_overlay.tscn:6-7`、`scenes/app/main.tscn:19-20`），一个 `shader_parameter/...` 都没有；`scripts/ui/crt_overlay.gd` 只改 `visible`（`:20-24`），全项目没有别处写这个 uniform。于是它一直是 shader 默认的 `vec2(322.0, 182.0)`（`crt_screen.gdshader:14`）——正好等于主场景子视口的尺寸（322×182），而窗口里**看得见的是 320×180**（容器偏移 −4 px，`scenes/app/main.tscn:48-51`）。后果见下面掩罩那一节。

## 它做了什么

按 shader 里的顺序（`crt_screen.gdshader:24-64`）：

1. **色偏**：R 取 `uv + shift`、B 取 `uv - shift`，G 不动（`:34-36`）。`shift = 0.35 / 322` 再乘 `0.35 + |uv-0.5| * 1.4`（`:27-31`）：中心 0.49 画布像素，四角 1.86 像素，只有水平方向。
2. **荧光光晕**：上下左右各取 1.2 个设计像素（≈4.8 画布像素）的邻居取平均，减去 `bloom_threshold` 再归一化（`:39-44`），所以只有平均亮度高于 0.6 的邻域才发光；最后加色 `glow * 0.55 * (0.35 + 0.65 * keep)`（`:61`）。
3. **扫描线**：`fract(uv.y * scanline_rows)` 取行相位，cos 成 0..1，`mix(1.0, scan, 0.2)`（`:47-48`）：720/180 = 4 画布像素一个周期，正好一行设计像素。
4. **槽式掩罩**：`cos(uv.x * source_size.x * 2π)` 取竖直条纹，`mix(1.0, 0.6 + 0.4 * slot, 0.1)`（`:49-50`）：按 322 算周期是 1280/322 = 3.975 画布像素，约一个设计像素。
5. **暗角**：`1 - vignette * dot(edge,edge) * 2`（`:53`）：中心 1.0，四角 0.75。
6. **合成 shade**：扫描线 × 掩罩 × 暗角（`:50-54`），中心最好 0.768，四角最坏 0.576。
7. **提升**：`col += vec3(lift)`（`:62`），0.015 ≈ 3.8/255，黑不会压成纯黑。
8. **亮部保持亮度**：`lum = max(r,g,b)`、`keep = smoothstep(0.45, 0.95, lum)`（`:57-58`），shade 只按 `1 - keep` 参与乘法（`:60`）：亮度 ≥0.95 的像素完全不吃扫描线/掩罩/暗角，只拿光晕和 lift。

## 为什么这样做可以

(a) **周期都表达成设计像素**：扫描线一行 = 4 画布像素（720/180，整数，任何整数倍放大都对得上网格）；掩罩、光晕步长、色偏都用 `1/source_size`，放大 2/4/8/16 倍时只是同一个图案变粗，不会突然冒出新的拍频。

(b) **shade 只乘进非亮像素**：灯笼核心、泛光、雾里的闪光是画面最亮的东西，让它们按原亮度留在扫描线之外，画面才不会"整体发灰、高光也一起被压"。

(c) **加色光晕 + 阈值**：不需要第二次模糊 pass —— 取 4 个邻居、减阈值、加色，就够读成磷光晕开。

**掩罩数学（跟直觉相反，值得记住）**：`slot` 的周期是 1280/322 = 3.9752 画布像素，**不是** 4。列 x 与 x+4 的相位差是 `322 * 4 / 1280 = 1.00625` 个周期，所以它不是 4 像素周期的图案，而是以 640 画布像素（160 设计列）为周期缓慢滑动（按参数手算：`shade` 在 [0,640) 与 [640,1280) 两段的相关系数 1.000000）。

也正因为不是整周期，四类列 `x % 4` 的平均值才完全相同：按 322 手算，四类的掩罩均值都是 0.980000000000（差 2e-16）；如果把 `source_size.x` 换成 320（严格 4 像素周期），四类会变成 0.994142 / 0.965858 / 0.965858 / 0.994142（差 0.0283，白像素上 7.2/255）—— 那才会真的按列染色。也就是说"竖条不偏列"靠的是 3.9752 与 4 的错位，不是"一个源像素一个周期"本身。

## 实测数字

工具：`scripts/tools/gas_diagnostic.gd` 抓真实窗口，同一帧各存一张 `window_00.png`（含 CRT）和 `window_nocrt_00.png`（把 `CrtOverlay.visible` 关掉再抓，`scripts/tools/gas_diagnostic.gd:465-484`）。场景 `runners/light_lab_runner`，1280×720 窗口，亮度取 RGB 平均（0..1）。

| 指标 | 值 |
| :--- | :--- |
| CRT 对整帧的贡献（平均） | **−0.0145** |
| 标准差 | 0.0699 |
| 范围 | −0.88 … +0.85 |
| 纯黑像素（无 CRT 帧亮度 <0.01，86592 个） | 0.0001 → 0.0175，即 **+0.0174**（这就是 lift + 光晕） |
| 四类列 `x % 4` 的贡献均值 | −0.014519 / −0.014500 / −0.014496 / −0.014664，极差 **0.00017** |

- 极端值不是 CRT：`|Δ|>0.4` 的 6426 个像素几乎全部落在完整的 4×4 画布块里（353 个整块）—— 一块正好一个设计像素，是两次抓图之间在动的单像素（灰尘、雾里的闪光）。
- 亮部实测是变暗的（无 CRT 帧亮度 >0.95 的 3392 个像素平均 −0.15），但同一帧手工算只有 −0.004（0.8–0.95 区间是 +0.018）：那批最亮的像素是灯笼核心和雾闪光，两次抓图之间在动。"亮部不掉亮"要用同一帧手算、或暂停世界再抓才量得准。
- 把同一份无 CRT 帧按 shader 手算一遍（uniform 用场景里的值）跟真实抓图比：稳定像素上相关系数 0.78、平均绝对误差 0.011，代码确实就是行为。
- **此前实测**（同一工具、`window`/`window_nocrt` 对比，另一次运行）：平均 +0.0012、std 0.0408、范围 −0.94…+0.92、`x % 4` 列偏置 0.0000。均值这次是负的、那次是正的：均值的符号取决于画面上有多少纯黑（lift 提亮）和多少中间调（暗角、扫描线压暗），换一帧就换符号；列偏置两次都量到 0。

## 参数

场景里没有任何 `shader_parameter`，所以全部取 shader 默认值（`scripts/shaders/crt_screen.gdshader:14-22`）：

| uniform | 场景实际用的值 | 作用 |
| :--- | :--- | :--- |
| `source_size` | (322, 182)（默认，未覆盖） | 设计像素折算：色偏/光晕步长、掩罩周期 |
| `scanline_rows` | 180 | 扫描线行数；一行 = 720/180 = 4 画布像素 |
| `scanline_strength` | 0.20 | 扫描线把像素压到 0.8–1.0 |
| `mask_strength` | 0.10 | 掩罩把像素压到 0.96–1.0 |
| `aberration` | 0.35 | 水平色偏，中心 0.49、四角 1.86 画布像素 |
| `bloom_strength` | 0.55 | 光晕加色上限（暗像素乘 0.35，亮像素乘 1.0） |
| `bloom_threshold` | 0.60 | 光晕只取平均亮度高于 0.6 的邻域 |
| `vignette` | 0.25 | 四角压暗 25% |
| `lift` | 0.015 | 全画面 +3.8/255，黑不是纯黑 |

`scanline_rows` 要一直等于设计高度 180：这样一行扫描线 = 一行设计像素。它是行数不是像素间距，改窗口大小不用动。

## 怎么自己看

```powershell
# 检查器：抓的是子视口，所以不含 CRT（full.png 只是世界画面）
godot --path . --resolution 1280x720 -s res://scripts/tools/render_inspector.gd -- --scene res://scenes/levels/test_world/runners/light_lab_runner.tscn --out C:/tmp/crt

# 真实窗口，同一帧各抓一次：有 CRT / 没 CRT
godot --path . --resolution 1280x720 -s res://scripts/tools/gas_diagnostic.gd -- --scene res://scenes/levels/test_world/runners/light_lab_runner.tscn --out C:/tmp/crt --settle 1.0 --frames 1
```

- `render_inspector.gd` 的 `full.png` 来自 `_viewport.get_texture()`（`scripts/tools/render_inspector.gd:328`），是子视口，和屏幕上差着放大 + CRT 两步。
- `gas_diagnostic.gd` 的 `window_*.png` 来自根窗口（`root.get_texture()`，`scripts/tools/gas_diagnostic.gd:471`），`window_nocrt_*.png` 是同一帧把 overlay 关掉再抓（`:473-483`）。两张相减就是这个层的贡献。
- 界面开关：设置 → 视频设置 → `CRT 滤镜`（`scripts/save/settings_catalog.gd:221-228`，文案在 `localization/menu.csv:64-65`，默认开）。

## 容易忘的点

- **它是全局层**：HUD、主菜单、设置界面都在 layer 0（`scenes/app/main.tscn:67-76`），扫描线和暗角也盖在 UI 上。要让 UI 不受影响，只能把 UI 挪到 128 之上。
- **`full.png` 不能用来谈 CRT**：`render_inspector.gd:14` 的注释写着 "the frame exactly as the game shows it"，但 `:328` 抓的是子视口，既没放大也没有 CRT；这类结论只能来自窗口抓图。
- **竖条先怀疑这一层**：掩罩是竖直的、周期 ≈3.975 画布像素的条纹（`crt_screen.gdshader:49`），是整个项目里唯一按列改亮度的地方。屏幕上出现竖条带时，先关 `crt_enabled` 对比，再怀疑游戏层的抖动。
- **开关只走信号**：`crt_overlay.gd:14-17` 只连 `settings_changed`，`_refresh()` 读一次 `crt_enabled`（`:20-24`）；`global_settings_manager.gd:233-253` 的 `_apply_value()` 里没有 `crt_enabled` 分支，值要经 `set_value()` → `_save_and_notify()`（`:260-262`）才会发信号。而且它存在 `user://settings.json`：本次量之前那个文件里是 `"crt_enabled": false`，抓图前得先在设置里打开（或临时改这一项），否则 `window_*.png` 里根本没有 CRT。
- 两份 `ShaderMaterial`（`scenes/app/main.tscn:19-20`、`scenes/ui/crt_overlay.tscn:6-7`）都不带参数；以后要调参，两处都得加 `shader_parameter/...`，或者直接改 shader 默认值。
