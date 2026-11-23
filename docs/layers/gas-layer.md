# 气体层（`Atmosphere/GasLayer`，z 5）

气体层是"一张覆盖整个房间的 quad"，但它读的东西有五个，所以这一层最容易看糊涂。求解器本身
（速度场、压力、涡量约束、细节 tracer 的注入）在 `addons/fluid_kit/README.md`，这里只讲**渲染这一层**。

---

## 1. 它读什么

| 输入 | 从哪来 | 用来干什么 |
| :--- | :--- | :--- |
| `gas_texture` | `Atmosphere` 的求解器输出，`房间像素 / gas_cell_pixels`（一屏 80×45，2×2 房间 160×90；可调到 1px 一格） | RGB = 重/中/轻三种气体的密度；A 恒为 1.0（**故意不用**，见第 6 节） |
| `detail_tex` | 同一个求解器的**速度场蓝通道**：被流场平流带走、并在原地被搅入新噪声的细节 tracer | 雾的"细纹"：`gas *= mix(1-0.45, 1+0.45, wisp)`，对比度补偿 ×3.5 |
| `solid_texture` | `SolidTiles` 生成的 8px 遮罩 | 墙体处直接 `discard`，气体被硬切在碰撞轮廓上 |
| `light_tex` | `LightField` 每帧渲染的光照图 | 雾被灯照亮、被墙影压暗（与全场用同一张图） |
| `stipple_tex` | `resources/textures/blue_noise_64.png`（烘焙） | 不透明度量化时的逐像素阈值 |

---

## 2. 一个像素经历什么（按 shader 顺序）

1. `quad_uv` → 世界坐标 `world`；用 8px 遮罩判断实心 → `discard`；
2. 取密度和三气通道，乘上细节 tracer 的调制（±45%）；
3. 三气合成：`opacity = heavy·0.62 + neutral·0.5 + light·0.48`，颜色按三气加权（重=暖锈、中=青、轻=淡金）；
4. 受光：4 盏作者灯（衰减 `pow(1-d/r, 1.6)`）+ 光照图取 `max`（`map_weight 0.5`），颜色朝 `lit_tint×1.6` 混合；
5. `alpha = clamp(opacity × (0.78 + 0.9·min(lit,1.5)), 0, 0.92)`；
6. **体积自遮挡**：朝主光源（提灯）6 次步进、每步 7px，`T = exp(-Σρ·0.9)`，`color *= mix(1, 0.45+0.55T, 0.55)`，按该层自身不透明度门控（`clamp(alpha·6,0,1)`）；
7. **风格化阈值**：`alpha = floor(alpha·32 + stipple_at(world)) / 32`，`alpha ≤ 0.02` 丢弃；
8. `COLOR = vec4(color, alpha)`，`blend_mix`。

**整层只做了一次抖动，而且只抖 alpha。** RGB 不抖、密度不抖。

---

## 3. 为什么这样做可以

* **密度 → 不透明度是线性的**，所以三种气体可以各给一个 alpha 权重再相加；颜色按浓度加权平均，混色不会出现"三种颜色同时叠加变灰"。
* **细节跟着流走**（tracer 存在速度场里、被平流），所以雾的纹理会随流拉伸卷曲，而不是一张噪声贴在屏幕上。对比度要 ×3.5 补偿，因为 trace-back 本身是模糊的（实测不补偿时雾比原来**更平**：不透明度梯度 0.0046 vs 0.0065）。
* **体积自遮挡必须门控**：几乎透明的薄雾在光学上是薄的、不该变暗。不门控时整层掉三分之一亮度（straight-colour 亮度 0.764 → 0.514），而"淡雾"正是噪点/条纹最容易暴露的区间。
* **蓝噪声阈值不改变均值**：阈值在 [0,1) 均匀，一片常数不透明度里点亮的比例正好等于它，所以量化只换颗粒形态、不换厚度（实测均值差 −1.1%）。
* **阈值锚在世界像素**（`floor(world)`）且房间原点总是 4 的倍数，所以相机移动时抖动不会"游"，换房间相位也一致。

---

## 4. 实测数字

同一帧冻结的气体、只换阈值核（`gas_diagnostic.gd --stipple=0,1`）：

| 指标 | 4×4 有序抖动 | 64×64 蓝噪声（现役） |
| :--- | :--- | :--- |
| 格点能量（周期 2/4 频点占比） | 5.06%（light_lab）/ 15.7%（gas_lab） | **0.59% / 0.12%** |
| 棋盘格相关 | −0.027 | +0.001 |
| 放大后"正好 1 设计像素"的竖直游程 | 75.4% | **50.8%** |
| 平均不透明度 | 0.06848 | 0.06847 |

体积自遮挡（同一帧，`volume_weight` 0 vs 1）：淡雾颜色亮度 −4.6%，中浓度 −25%，厚烟团 −43% 并出现深度渐变。

成本：整层（含体积 6 次采样和蓝噪声采样）低于帧时间噪声 —— 隐藏 `Atmosphere` 前后 1.162 / 1.165 ms（light_lab）。求解器提交 0.09 ms/步（2×2 房间 160×90）；1px 一格（230400 格）时 0.084 ms/步、帧时间无可分辨变化。

---

## 5. 参数

| 参数（`Atmosphere`） | 默认 | 作用 |
| :--- | :--- | :--- |
| `gas_cell_pixels` | 4 | 每格多少世界像素；1 表示雾细到像素网格 |
| `sim_hz` | 30（`world_root` 用 60） | 每秒求解步数 |
| `gas_alpha` / `base_alpha` / `light_alpha` | (0.62,0.5,0.48) / 0.78 / 0.9 | 三气权重、无光/有光时的透明度 |
| `noise_amount` | 0.45 | 细节 tracer 的调制深度 |
| `detail_amount` / `detail_contrast` / `detail_refresh` / `detail_hz` | 1.0 / 3.5 / 4.0 / 6.0 | 是否用 tracer、对比度、每秒搅入量、噪声源重画频率 |
| `stipple_mode` / `stipple_steps` | 1 / 32 | 阈值核（0 有序、1 蓝噪声、2 白噪声）与量化级数 |
| `volume_shadow` / `volume_weight` | 0.9 / 0.55 | 自遮挡深度与应用比例 |
| `gas_vorticity` / `gas_decay` / `gas_buoyancy` | 10 / 0.12 / (240,0,300) | 求解器参数（详见 addon README） |

---

## 6. 容易忘的点

* **密度纹理的 alpha 恒为 1.0，不要往里塞数据。** 这些 pass 画进透明 SubViewport，canvas 会**预乘**写入的 alpha，而缓冲乒乓 —— 曾经把细节放进 alpha，结果气体**每步掉一半**（实测 172 步平均密度 0.022 → 0.0004）。第四路数据只能放在写 `alpha = 1.0` 的速度场里。
* **场的尺寸是"房间像素 / 格"，不是屏幕尺寸。** 2×2 房间是 160×90（4px 一格）；相机移动不会改变它。细胞的密度是房间矩形上的采样，不是屏幕上的。
* **CPU 回退（`FogGrid`）没有 tracer**，那时 `detail_amount` 被强制为 0，shader 退回屏幕空间的三路 `value_noise`（尺度 0.09/0.17/0.3）。所以在 headless/预览里看到的雾纹理和游戏里不是同一套。
* **只有 alpha 被量化**。想让雾"更像素"应该调 `stipple_steps` 或 `gas_cell_pixels`，不是去抖颜色。

---

## 7. 怎么自己看

```powershell
$godot = "D:\Godot4\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe"

# 只截气体层（含它的 alpha 通道 = 不透明度图）
& $godot --path . --resolution 1280x720 -s res://scripts/tools/gas_diagnostic.gd -- `
  --scene res://scenes/levels/test/light_lab_runner.tscn --out C:/tmp/gas --settle 2 --frames 2

# 同一帧冻结气体，三种阈值核并排对比 + 帧成本
... --out C:/tmp/gas --settle 2 --frames 1 --stipple=0,1,2 --timing
```

`gas_diagnostic` 会写出：`density_XX.png`（原始密度场）、`velocity_XX.png`（RG=速度，B=细节 tracer）、
`alpha_XX.png`（整层不透明度，透明底）、`full_XX.png`、`window_XX.png`（真实窗口，含 CRT）以及 `info.txt`
（含求解器**实际生效**的参数）。
