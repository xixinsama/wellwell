# CRT 屏幕效果（CanvasLayer 128）

这一层的全部内容：`scenes/ui/crt_overlay.tscn`（一个 `CanvasLayer` + 一张全屏 `ColorRect`）和 `game/shaders/crt_screen.gdshader`（一个 `canvas_item` 片元着色器）。开关只有一个：视频设置里的 `crt_enabled`。

## 它在整个画面里的位置

世界先在 `SubViewport` 里画完（主场景 322×182），再由 `SubViewportContainer` 按 `stretch_shrink = 4` 放大；`CrtOverlay` 是 `CanvasLayer`、`layer=128`，排在放大之后的最上层，所以它工作在**窗口像素**上。

从这次修复起，`project.godot` 的窗口缩放改成像素艺术的标准组合：

```ini
window/stretch/mode="viewport"
window/stretch/aspect="keep"
window/stretch/scale_mode="integer"
```

根画布因此**恒为 1280×720**（窗口多大都不变），窗口按整数倍放大、多余部分留黑边。这样根画布的 1 个像素 = 窗口的 1 个物理像素，扫描线不会被非整数缩放重新采样。之前用 `aspect="expand"` + 默认的分数缩放时，窗口会被拉成 1367×768 之类的任意尺寸，根画布变成 1281×720，CRT 图案在最后一层被非整数放大——那是"没有像素对齐"的根源。

## 两条契约

### 像素对齐

- 所有纹理采样都落在窗口像素中心：`uv = (floor(pixel) + 0.5) / screen_pixels`，与 CRT-Hyllian 的做法一致。
- 扫描线的相位不是按窗口高度算的，而是从**整数放大后的游戏像素网格**算起：`row = (pixel.y - grid_origin.y) / pixel_scale`。`grid_origin` 是 320×180 安全区左上角在窗口里的位置（容器位置 + 1 个视口边框像素 × 放大倍数），`pixel_scale` 是整数放大倍数（默认 4）。
- `screen_pixels` / `grid_origin` / `pixel_scale` 由 `game/ui/crt_overlay.gd` 在窗口或容器尺寸变化时推给 shader；shader 不再用写死的 322×182。
- 色偏只按整窗口像素移动（`floor(aberration * pixel_scale + 0.5)`），不会采到两个像素之间。

### 亮度不变

- 只保留扫描线这一种乘性调制，不再叠加任何加色光晕、`lift`、暗角（默认 0）。
- 每个像素按自己的 beam 平均值做能量归一化：`col / (1 - scanline_strength * 0.5 * (1 - lit))`，屏幕平均亮度因此与输入一致。
- 亮像素让 beam 展宽（`lit = smoothstep(0.45, 0.92, peak)`，beam 趋向 1），高光既不被压暗，也不会被染色或加亮。
- 旧的"亮部跳过 shade + 加色 bloom"正好相反：光照区域越亮，加得越多，所以灯笼/泛光会发白。这一版删掉了那条路径。

## 它做了什么

1. 按窗口像素中心采样（最近邻等效）。
2. 水平色散：R/B 各偏移整数个窗口像素，G 不动。
3. 扫描线：一个游戏像素行一个周期，行边界最暗、行中心最亮；亮像素展宽 beam。
4. 能量归一化：除以该像素的平均透过率，保持均值和对比。
5. 可选暗角与整体增益：默认 `vignette = 0`、`brightness = 1.0`，不参与"提亮"。

## 参数

场景里没有任何 `shader_parameter`，所以全部取 shader 默认值：

| uniform | 默认值 | 作用 |
| :--- | :--- | :--- |
| `screen_pixels` | (1280, 720) | 运行时由脚本推入：窗口（根画布）像素尺寸 |
| `grid_origin` | (0, 0) | 运行时推入：游戏像素 (0,0) 在窗口里的位置 |
| `pixel_scale` | 4.0 | 运行时推入：一个游戏像素 = 几个窗口像素 |
| `scanline_strength` | 0.12 | 行边界压暗比例（能量归一化会补回均值） |
| `aberration` | 0.35 | 水平色散强度，取整到窗口像素 |
| `vignette` | 0.0 | 四角压暗；默认关，避免整体变暗 |
| `brightness` | 1.0 | 整体增益，只用于手动微调 |

## 实测（1280×720 根画布，4× 游戏网格）

用根窗口截图对比 CRT 开/关：

| 场景 | 指标 | 结果 |
| :--- | :--- | :--- |
| 50% 平灰测试层 | 平均亮度 | 0.4980 → 0.4980，**+0.000%** |
| 50% 平灰测试层 | RGB 通道均值 | 三者均为 127.00（无染色、无竖条） |
| 50% 平灰测试层 | 扫描线周期 | 4 像素，`y % 4` 相位均值 122 / 132 / 132 / 122 |
| 50% 平灰测试层 | 自相关 | lag 2 = −1.000，lag 4 = +1.000（严格 4 周期） |
| `the_world` 实机 | 平均亮度 | 0.0602 → 0.0597，**−0.92%** |
| `the_world` 实机 | p95 / p99 | 0.346 / 0.346、0.607 / 0.596（没有整体提亮） |
| `the_world` 实机 | 最大亮度 | 0.912 → 0.916（+0.4%） |

实机那组是两次截图之间隔了几帧，雾/光/水在动，所以均值以外的逐像素差没有参考价值；平灰测试层是静止的，能看到精确结果。

## 怎么自己看

```powershell
# 真实窗口，同一帧各抓一次：有 CRT / 没 CRT
godot --path . --resolution 1280x720 -s res://tools/gas_diagnostic.gd -- \
  --scene res://scenes/levels/test_world/runners/light_lab_runner.tscn --out C:/tmp/crt --settle 1.0 --frames 1
```

`gas_diagnostic.gd` 的 `window_*.png` 来自根窗口，`window_nocrt_*.png` 是同一帧把 overlay 关掉再抓；两张相减就是这个层的贡献。要在游戏里手动对比：设置 → 视频设置 → `CRT 滤镜`。

## 容易忘的点

- **它是全局层**：HUD、主菜单、设置界面都在 layer 0，扫描线也盖在 UI 上。要让 UI 不受影响，只能把 UI 挪到 128 之上。
- **`render_inspector.gd` 的 `full.png` 不含 CRT**：它抓的是世界 SubViewport，既没放大也没有 CRT；CRT 结论只能来自根窗口抓图。
- **开关只走信号**：`crt_overlay.gd` 连 `settings_changed`，`_refresh()` 读一次 `crt_enabled`。值存在 `user://settings.json`，如果上次关过，抓图前要先在设置里打开。
- **窗口缩放设置是一对**：`aspect="keep"` + `scale_mode="integer"` 保证根画布不被非整数拉伸；如果 fork 改回 `expand` 或分数缩放，CRT 的扫描线会重新落回小数像素，这不是 shader 能修的。
- **改了容器布局**：`crt_overlay.gd` 通过 `../SubViewportContainer` 找容器、用 `stretch_shrink` 当放大倍数；把 overlay 放到别处时要改这个路径或走 fallback（按 320×180 居中计算）。
- 两份 `ShaderMaterial`（`scenes/app/main.tscn`、`scenes/ui/crt_overlay.tscn`）都不带参数；要调参就改 shader 默认值，或在两处都加 `shader_parameter/...`。
