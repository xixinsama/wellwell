# 地形高光描边（`TerrainHighlight`）

贴着**实心地形（`SolidTiles`）的内侧边缘**画一圈 1–2px 的高光：顶面、左右墙面、悬挑底面都会亮（`rim_inside = false` 时改成描在外侧的空气里）。轮廓来自瓦片的**美术透明通道**，所以斜砖、半砖、装饰砖都按真实形状描边，而不是按整格方块。

## 它读的是什么

- 只读 `Terrain/SolidTiles` 这一层（`layer_path` 可改），**不读背景层和装饰层**。
- 轮廓烘成**一像素一个 texel** 的遮罩（R8）：把每个瓦片在图集里那一块的 alpha 拷贝进来，并处理 `flip_h` / `flip_v` / `transpose`。半砖、斜砖、甚至带镂空的装饰砖，形状都是精确的。
- 着色器按「到最近空气像素的距离」画带：上下左右各探 `rim_width` 像素，取最小距离，所以整圈都有高光，转角自然收口。
- 一条 quad 覆盖整间房，像素坐标由 UV 换算，不依赖 `VERTEX`。

## 为什么用美术 alpha 而不是碰撞

`SolidTiles` 里放的不全是整格方块：斜砖是三角形、半砖只有半格、还有些装饰砖根本没有碰撞体。如果按「整格」画描边，斜砖会被描成一个方块、半砖会描在空的那一半上——这就是之前的错位来源。用美术 alpha 得到的剪影和眼睛看到的砖块完全一致。

## 参数（`TerrainHighlight` 节点）

| 参数 | 默认 | 作用 |
| :--- | :--- | :--- |
| `layer_path` | `Terrain/SolidTiles` | 用哪一层瓦片做轮廓 |
| `rim_color` | 淡青白 | 高光颜色 |
| `rim_strength` | 0.85 | 亮度 |
| `rim_width` | 2 | 从轮廓边缘往里延伸几像素 |
| `rim_softness` | 0.6 | 带内衰减，0 = 硬边，1 = 渐隐 |
| `rim_grain` | 0.18 | 按像素抖动，避免看起来像矢量画的直线 |
| `rim_inside` | true | true = 描在实心体内侧，false = 描在外侧空气里 |
| `draw_order` | 1 | z 顺序（在地形之上、雾/水/气体之下） |

## 接线

`scenes/runtime/world_root.tscn` 里已经有 `TerrainHighlight` 节点（和 `BackdropField` 同级）。它在 `world_ready` 时给每间已加载的房间挂一条 quad；房间重新烘焙后会重建，房间里没有实心瓦片时会把 quad 删掉。

想在别的世界根上用，把节点挂到世界根下、确保它旁边有 `TerrainRoot`（房间作为 TerrainRoot 的子节点）即可。直接挂在源房间场景里时，把 `layer_path` 设成 `RoomContent/Terrain/SolidTiles`。

## 检查遮罩

`build_mask()` 是公开方法，可以直接把遮罩导出成图片核对：

```gdscript
var mask: Image = highlight.build_mask(room.get_node("Terrain/SolidTiles"))
mask.resize(mask.get_width() * 3, mask.get_height() * 3, Image.INTERPOLATE_NEAREST)
mask.save_png("user://terrain_mask.png")
```

## 性能

一间房一条 quad，片元着色器每像素最多 4 个方向 × `rim_width` 次遮罩采样（默认 4×2），没有逐帧 CPU 工作、没有额外 pass。遮罩在房间加载时烘一次（一像素一次 alpha 读取）。

## 相关

- 气体裁剪墙体的剪影：`Atmosphere._build_solid_mask()`（按瓦片格，比这里的像素级遮罩粗，够用即可）。
- 背面/背景的整屏底板：`scripts/world/backdrop_field.gd`。
