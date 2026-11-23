# 地形高光描边（`TerrainHighlight`）

贴着**实心地形（`SolidTiles`）的内侧边缘**画一圈 1–2px 的高光，而且**只照亮 hero 所在的那一侧**：hero 进不去的密闭空间（封闭房间、墙里的空腔）内部保持全黑。

## 它读的是什么

- 只读 `Terrain/SolidTiles` 这一层（`layer_path` 可改），不读背景层和装饰层。
- 形状来自**每块瓦片的碰撞多边形**（扫描线填充，按瓦片中心坐标）：
  - 斜砖 = 三角形、半砖 = 半格矩形 → 描边跟着真实几何走；
  - 备选瓦片（alternative）用自己的多边形（编辑器已按备选朝向存好，**不再二次翻转**）；
  - **没有碰撞多边形的瓦片**（梯子、藤蔓、贴花）不算地形 → 完全不进遮罩；
  - 斜边多覆盖一个像素，和瓦片美术的画法一致。
- 遮罩是**一像素一个 texel**（R8），所以任何缩放下都清晰。

## 只照亮 hero 那一侧

1. 新增一张**可达图**：以瓦片（8px）为单位的 R8 纹理。
2. hero 所在瓦片变化时（不是每帧）从 hero 的瓦片做 4 连通 flood fill，穿过没有碰撞的瓦片，得到"hero 能到达的空气"。
3. 着色器在 4 个方向找最近的空气时，**只有那块空气是可达的**才把这方向算作描边方向；四个方向都不可达 → 这个像素不亮。

所以：

- 密闭空腔的内壁：四面空气都不可达 → 全黑（实测 `room_03_00` 里的封闭小屋内部 0 个高光像素）；
- 同一个房间的开放区域：亮的都是朝向 hero 可达空气的那一面；
- 墙的"背面"（朝密闭空间那面）不会亮，即使离 hero 很近。

`hero_side_only = false` 可以关掉这套逻辑，退回"整圈都亮"。

## 什么时候重算

- 房间加载/重烘焙（`world_ready`）；
- hero 走进另一个瓦片（每 8px 一次，实测开销可忽略：一次几百格的 flood fill + 一张 40×45 的 1 字节纹理上传）。
- 没有 player 时（编辑器预览），可达图默认全亮，方便摆关卡。

## 参数（`TerrainHighlight` 节点）

| 参数 | 默认 | 作用 |
| :--- | :--- | :--- |
| `layer_path` | `Terrain/SolidTiles` | 用哪一层瓦片做轮廓 |
| `rim_color` | 淡青白 `(0.78, 0.96, 1.0)` | 高光颜色 |
| `rim_strength` | 1.0 | 亮度 |
| `rim_width` | 1.0 | 从轮廓边缘往里延伸几像素（1–4，半步可调） |
| `rim_softness` | 0.6 | 带内衰减，0 = 硬边，1 = 渐隐 |
| `rim_grain` | 0.18 | 按像素抖动，避免看起来像矢量画的直线 |
| `rim_inside` | true | true = 描在实心体内侧，false = 描在外侧空气里 |
| `hero_side_only` | true | 只照亮 hero 可达的那一侧 |
| `draw_order` | 1 | z 顺序（在地形之上、雾/水/气体之下） |
| `light_floor` / `light_gain` | 0.55 / 1.0 | 描边被光照图门控：最暗处保留 `light_floor`，亮处乘 `light_gain` |
| `solid_needs_collision` | true | 只把**有碰撞多边形**的瓦片当实心（梯子、贴花这类装饰瓦片不进遮罩） |

## 接线

`scenes/runtime/world_root.tscn` 里已经有 `TerrainHighlight` 节点（和 `BackdropField` 同级）。它在 `world_ready` 时给每间已加载的房间挂一条 quad；房间重新烘焙后会重建，房间里没有实心瓦片时会把 quad 删掉。hero 位置默认取 `../Player`。

直接挂在源房间场景里时，把 `layer_path` 设成 `RoomContent/Terrain/SolidTiles`。

## 检查遮罩 / 可达图

```gdscript
var mask: Image = highlight.build_mask(room.get_node("Terrain/SolidTiles"))
mask.resize(mask.get_width() * 3, mask.get_height() * 3, Image.INTERPOLATE_NEAREST)
mask.save_png("user://terrain_mask.png")

var entry: Dictionary = highlight.get("_entries")[0]
var reach: PackedByteArray = highlight.compute_reach(entry, Vector2i(20, 10))  # 瓦片坐标
```

## 性能

一间房一条 quad，片元着色器每像素最多 4 个方向 × `rim_width` 次遮罩采样 + 一次可达采样，没有逐帧 CPU 工作（可达图只在换瓦片时重算）。遮罩在房间加载时烘一次。

## 相关

- 气体裁剪墙体的剪影：`Atmosphere._build_solid_mask()`（按瓦片格，比这里的像素级遮罩粗）。
- 背面/背景的整屏底板：`game/world/backdrop_field.gd`。
