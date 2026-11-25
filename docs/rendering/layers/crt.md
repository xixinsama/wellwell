# CRT 屏幕效果（CanvasLayer 128）

这一层的全部内容：`scenes/ui/crt_overlay.tscn`（一个 `CanvasLayer` + 一张全屏 `ColorRect`）和 `game/shaders/crt_screen.gdshader`（一个 `canvas_item` 片元着色器）。开关：视频设置里的 `crt_enabled`；颗粒类型：视频设置里的 **CRT Grain**（`crt_mode`）。

两种模式共用同一套像素对齐与能量归一化：

| 模式 | 效果 |
| :--- | :--- |
| **Scanlines**（`scanline`） | 每个游戏像素行一条扫描线，中心亮、行边界暗；之前调好的那版，保留 |
| **Phosphor Dots**（`dot`，默认） | 每个游戏像素一颗**横向椭圆**的柔和光斑，X 半径大于 Y 半径，点间有暗格 |

两种模式都不做屏幕弯曲。

## 它在整个画面里的位置

世界先在 `SubViewport` 里画完（主场景 322×182），再由 `SubViewportContainer` 按 `stretch_shrink = 4` 放大；`CrtOverlay` 是 `CanvasLayer`、`layer=128`，排在放大之后的最上层，所以它工作在**窗口像素**上。

`project.godot` 的窗口缩放：

```ini
window/stretch/mode="viewport"
window/stretch/aspect="keep"
window/stretch/scale_mode="integer"
```

根画布恒为 1280×720，窗口按整数倍放大、多余部分留黑边。根画布 1 个像素 = 窗口 1 个物理像素，点阵/扫描线不会被非整数缩放重新采样。

## 两条契约

### 像素对齐

- 所有纹理采样都落在窗口像素中心：`uv = (floor(pixel) + 0.5) / screen_pixels`。
- 相位从**整数放大后的游戏像素网格**算起：`grid_origin` 是 320×180 安全区左上角在窗口里的位置（容器位置 + 视口边框 × 放大倍数），`pixel_scale` 是整数放大倍数（默认 4）。
- `screen_pixels` / `grid_origin` / `pixel_scale` 由 `game/ui/crt_overlay.gd` 在布局变化时推给 shader。
- 色偏只按整窗口像素移动，不会采到两个像素之间。

### 亮度不变

- **Scanlines**：beam 的相位是 `fract((pixel.y - grid_origin.y) / pixel_scale)`，一个游戏像素行一个周期；按平均透过率 `1 - scanline_strength * 0.5 * (1 - lit)` 归一化，亮像素展宽 beam。
- **Phosphor Dots**：在游戏像素内取中心坐标 `cell ∈ [-0.5, 0.5]²`，`cell.y *= dot_aspect`（>1 压缩 Y → **X 半径更大**），按 `r = |cell| / (0.5 · dot_size)` 算径向距离，`core = 1 - smoothstep(1 - dot_softness, 1, r)` 生成柔和椭圆光斑；平均覆盖率 `dot_average` 由 `CrtOverlay` 在 CPU 上按同一组采样算好推给 shader，按 `1 / (1 - dot_strength * (1 - average_shape))` 归一化。
- 亮像素（`peak` 高）会展宽点/beam，高光和 UI 文字保持实心。
- 没有加色 bloom、没有 `lift`、暗角默认 0。

## 参数

场景里没有 `shader_parameter`；点阵参数暴露在 `CrtOverlay` 的 inspector 上，由脚本推给 shader：

| 参数 | 默认值 | 作用 |
| :--- | :--- | :--- |
| `crt_mode` | 1（Phosphor Dots） | 0 = Scanlines，1 = Phosphor Dots；由视频设置 `crt_mode` 决定 |
| `screen_pixels` | (1280, 720) | 运行时：根画布像素尺寸 |
| `grid_origin` | (0, 0) | 运行时：游戏像素 (0,0) 在窗口里的位置 |
| `pixel_scale` | 4.0 | 运行时：一个游戏像素 = 几个窗口像素 |
| `scanline_strength` | 0.12 | 扫描线行边界压暗比例（Scanlines 模式） |
| `dot_strength` | 0.70 | 暗格强度（Dots 模式）；0 = 关，0.8+ 很硬 |
| `dot_size` | 1.0 | 椭圆半径（相对半格）；越小点越紧、暗格越宽 |
| `dot_aspect` | 1.15 | Y 轴压缩；**>1 时 X 半径大于 Y 半径**（横向椭圆），1 = 圆，<1 = 竖椭圆 |
| `dot_softness` | 0.45 | 光斑边缘羽化；0.6+ 更浑圆柔和，0.3 更硬 |
| `dot_average` | 运行时 | 当前放大倍数、当前参数下的平均覆盖率；不要手动覆盖 |
| `aberration` | 0.35 | 水平色散，取整到窗口像素 |
| `vignette` | 0.0 | 四角压暗；默认关 |
| `brightness` | 1.0 | 整体增益，只用于手动微调 |

想改颗粒方向：`dot_aspect` 调大 → 更扁更宽；调小 → 更高。

## 实测（1280×720 根画布，4× 游戏网格）

| 模式 | 场景 | 指标 | 结果 |
| :--- | :--- | :--- | :--- |
| Scanlines | 50% 平灰 | 平均亮度 | 0.4980 → 0.4980，**+0.000%** |
| Scanlines | 50% 平灰 | 4×4 单元 | 每列相同；行相位 122 / 132 / 132 / 122 |
| Dots | 50% 平灰 | 平均亮度 | 0.4980 → 0.4971，**−0.197%** |
| Dots | 50% 平灰 | 4×4 单元 | 中心 223、左右 130、上下 87、四角 67（0..255） |
| Dots | 50% 平灰 | 椭圆方向 | 左右 130 > 上下 87 → **X 半径更大** |
| Dots | `the_world` 实机 | 平均亮度 | 0.0589 → 0.0570，**−3.20%** |
| Dots | `the_world` 实机 | p95 / p99 | 0.339 → 0.343 / 0.604 → 0.679（暗格压暗、灯珠提亮） |
| Dots | `the_world` 实机 | 纯白像素 | 0 → 29（灯珠核心） |

实机那组两次截图间隔几帧，雾/光/水在动，逐像素差只作参考；平灰层是静止的，能看到精确结构。

## 怎么自己看

```powershell
# 真实窗口，同一帧各抓一次：有 CRT / 没 CRT
godot --path . --resolution 1280x720 -s res://tools/gas_diagnostic.gd -- \
  --scene res://scenes/levels/test_world/runners/light_lab_runner.tscn --out C:/tmp/crt --settle 1.0 --frames 1
```

`gas_diagnostic.gd` 的 `window_*.png` 来自根窗口，`window_nocrt_*.png` 是同一帧把 overlay 关掉再抓；两张相减就是这个层的贡献。游戏内切换：设置 → 视频设置 → **CRT 滤镜** 与 **CRT 颗粒**。

## 容易忘的点

- **它是全局层**：HUD、主菜单、设置界面都在 layer 0，颗粒也盖在 UI 上。亮像素会自动展宽点，所以文字仍然清楚；要让 UI 完全不吃 CRT，只能把 UI 挪到 128 之上。
- **`render_inspector.gd` 的 `full.png` 不含 CRT**：它抓的是世界 SubViewport；CRT 结论只能来自根窗口抓图。
- **开关和模式只走信号**：`crt_overlay.gd` 连 `settings_changed`，`_refresh()` 读 `crt_enabled` 与 `crt_mode`。值存在 `user://settings.json`。
- **窗口缩放设置是一对**：`aspect="keep"` + `scale_mode="integer"` 保证根画布不被非整数拉伸；改回 `expand` 或分数缩放会让颗粒重新落到小数像素。
- **改点阵参数后 `dot_average` 会自动重算**：脚本每帧比较 `dot_strength/dot_size/dot_aspect/dot_softness`，变化时重新采样并推送。
- **改了容器布局**：`crt_overlay.gd` 通过 `../SubViewportContainer` 找容器、用 `stretch_shrink` 当放大倍数；把 overlay 放到别处时要改这个路径或走 fallback（按 320×180 居中计算）。
