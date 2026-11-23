# CRT 屏幕效果（CanvasLayer 128）

这一层的全部内容：`scenes/ui/crt_overlay.tscn`（一个 `CanvasLayer` + 一张全屏 `ColorRect`）和 `game/shaders/crt_screen.gdshader`（一个 `canvas_item` 片元着色器）。开关只有一个：视频设置里的 `crt_enabled`。

它模拟的是**点阵式 CRT**：一个游戏像素 = 一颗柔和的椭圆磷光点，点与点之间有暗格，没有屏幕弯曲。点不是硬方块，而是中心亮、边缘平滑衰减的径向光斑（`1 - smoothstep(...)`，和 Detour/Popochiu 的 CRT 点阵同一套公式）。默认 `dot_strength = 0.75`、`dot_size = 0.95`、`dot_softness = 0.45`。

## 它在整个画面里的位置

世界先在 `SubViewport` 里画完（主场景 322×182），再由 `SubViewportContainer` 按 `stretch_shrink = 4` 放大；`CrtOverlay` 是 `CanvasLayer`、`layer=128`，排在放大之后的最上层，所以它工作在**窗口像素**上。

`project.godot` 的窗口缩放是像素艺术的标准组合：

```ini
window/stretch/mode="viewport"
window/stretch/aspect="keep"
window/stretch/scale_mode="integer"
```

根画布因此**恒为 1280×720**（窗口多大都不变），窗口按整数倍放大、多余部分留黑边。这样根画布的 1 个像素 = 窗口的 1 个物理像素，点阵不会被非整数缩放重新采样。之前用 `aspect="expand"` + 分数缩放时，窗口会被拉成 1367×768 之类的尺寸，根画布变成 1281×720，CRT 图案在最后一层被非整数放大——那是"没有像素对齐"的根源。

## 三条契约

### 像素对齐

- 所有纹理采样都落在窗口像素中心：`uv = (floor(pixel) + 0.5) / screen_pixels`。
- 点阵相位从**整数放大后的游戏像素网格**算起：`cell = fract((pixel - grid_origin) / pixel_scale) * 2 - 1`。`grid_origin` 是 320×180 安全区左上角在窗口里的位置（容器位置 + 视口边框 × 放大倍数），`pixel_scale` 是整数放大倍数（默认 4）。
- `screen_pixels` / `grid_origin` / `pixel_scale` 由 `game/ui/crt_overlay.gd` 在窗口或容器尺寸变化时推给 shader；shader 不再用写死的 322×182。
- 色偏只按整窗口像素移动，不会采到两个像素之间。

### 一个像素一颗椭圆

- 在游戏像素内取中心坐标 `cell ∈ [-0.5, 0.5]²`，`cell.y *= dot_aspect`，按 `r = |cell| / (0.5 · dot_size)` 计算径向距离，再用 `core = 1 - smoothstep(1 - dot_softness, 1, r)` 生成柔和的椭圆光斑。
- 这个 core 在中心为 1、在椭圆边缘为 0；`mask = 1 - dot_strength * (1 - core)`，所以点外是暗格，点内是灯珠。`dot_softness` 控制边缘羽化，越大越像灯泡而不是圆片。
- 4× 放大时每颗点由 4×4 个窗口像素采样：中心 2×2 最亮，四周一圈是暗格，读起来就是一颗圆点。

### 亮度不变

- 点阵的平均透过率由 `CrtOverlay._dot_average()` 在 CPU 上按**同一组窗口像素采样**算出来，作为 `dot_average` 推给 shader；shader 用 `1 / (1 - dot_strength * (1 - average_shape))` 归一化。
- 因此改 `dot_strength` / `dot_size` / `dot_aspect` 不会改变整帧平均亮度，不需要额外补光。
- 亮像素会按亮度展宽点（`widen = smoothstep(0.78, 1.0, peak) * 0.85`）：高光和 UI 文字保持实心，不会碎成稀疏点阵。
- 没有加色 bloom、没有 `lift`、暗角默认 0。

## 参数

场景里没有任何 `shader_parameter`；点阵参数暴露在 `CrtOverlay` 的 inspector 上，由脚本推给 shader：

| 参数 | 默认值 | 作用 |
| :--- | :--- | :--- |
| `screen_pixels` | (1280, 720) | 运行时：根画布像素尺寸 |
| `grid_origin` | (0, 0) | 运行时：游戏像素 (0,0) 在窗口里的位置 |
| `pixel_scale` | 4.0 | 运行时：一个游戏像素 = 几个窗口像素 |
| `dot_strength` | 0.75 | 暗格强度；0 = 关，0.75 = 明显颗粒，0.85+ 非常硬 |
| `dot_size` | 0.95 | 椭圆半径（相对半格）；越小点越紧、暗格越宽 |
| `dot_aspect` | 0.9 | 纵向拉伸系数；<1 是竖椭圆（更像灯珠），1 是圆 |
| `dot_softness` | 0.45 | 光斑边缘羽化；0.6+ 更浑圆柔和，0.25 更硬 |
| `dot_average` | 0.171 | 运行时：当前放大倍数下的平均覆盖率，由脚本计算 |
| `aberration` | 0.35 | 水平色散，取整到窗口像素 |
| `vignette` | 0.0 | 四角压暗；默认关 |
| `brightness` | 1.0 | 整体增益，只用于手动微调 |

想更"老电视"一点：`dot_strength = 0.8`、`dot_size = 0.78`、`dot_aspect = 0.88`；想轻一点：`dot_strength = 0.55`。

## 实测（1280×720 根画布，4× 游戏网格）

| 场景 | 指标 | 结果 |
| :--- | :--- | :--- |
| 50% 平灰测试层 | 平均亮度 | 0.4980 → 0.4980，**+0.000%** |
| 50% 平灰测试层 | 4×4 单元亮度 | 中心 210、边 140/106、角 52（0..255） |
| 50% 平灰测试层 | 点/暗格对比 | **4.0×**（中心 2×2 / 四角），边缘是平滑过渡而不是硬边 |
| 50% 平灰测试层 | 周期 | 横纵都是 4 像素（lag 4 自相关 +1.0，lag 2 −1.0） |
| `the_world` 实机 | 平均亮度 | 0.0598 → 0.0586，**−2.09%** |
| `the_world` 实机 | p95 / p99 | 0.342 → 0.379 / 0.608 → 0.672（暗格压暗、灯珠提亮） |
| `the_world` 实机 | 纯白像素 | 0 → 21（灯珠核心） |

实机那组两次截图间隔几帧，雾/光/水在动，所以逐像素差只作参考；平灰层是静止的，能看到精确的点阵结构。

## 怎么自己看

```powershell
# 真实窗口，同一帧各抓一次：有 CRT / 没 CRT
godot --path . --resolution 1280x720 -s res://tools/gas_diagnostic.gd -- \
  --scene res://scenes/levels/test_world/runners/light_lab_runner.tscn --out C:/tmp/crt --settle 1.0 --frames 1
```

`gas_diagnostic.gd` 的 `window_*.png` 来自根窗口，`window_nocrt_*.png` 是同一帧把 overlay 关掉再抓；两张相减就是这个层的贡献。要在游戏里手动对比：设置 → 视频设置 → `CRT 滤镜`。

## 容易忘的点

- **它是全局层**：HUD、主菜单、设置界面都在 layer 0，点阵也盖在 UI 上。亮像素会自动展宽点，所以文字仍然清楚；要让 UI 完全不吃 CRT，只能把 UI 挪到 128 之上。
- **`render_inspector.gd` 的 `full.png` 不含 CRT**：它抓的是世界 SubViewport，既没放大也没有 CRT；CRT 结论只能来自根窗口抓图。
- **开关只走信号**：`crt_overlay.gd` 连 `settings_changed`，`_refresh()` 读一次 `crt_enabled`。值存在 `user://settings.json`，如果上次关过，抓图前要先在设置里打开。
- **窗口缩放设置是一对**：`aspect="keep"` + `scale_mode="integer"` 保证根画布不被非整数拉伸；改回 `expand` 或分数缩放会让点阵重新落到小数像素，这不是 shader 能修的。
- **改点阵参数后 `dot_average` 会自动重算**：脚本每帧比较 `dot_strength/dot_size/dot_aspect`，变化时重新采样并推送。不要手动在场景里覆盖 `dot_average`，否则平均亮度会漂。
- **改了容器布局**：`crt_overlay.gd` 通过 `../SubViewportContainer` 找容器、用 `stretch_shrink` 当放大倍数；把 overlay 放到别处时要改这个路径或走 fallback（按 320×180 居中计算）。
