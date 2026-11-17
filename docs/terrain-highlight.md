# 地形高光描边（`TerrainHighlight`）

贴着**实心地形（`SolidTiles`）的内侧顶面**画一条 1–2px 的高光，像光从上方打在台阶边缘。用到的轮廓就是气体着色器一直在用的那层碰撞剪影，只是这里按瓦片精度取出来单独画一条线。

## 它读的是什么

- 只读 `Terrain/SolidTiles` 这一层（`layer_path` 可改），**不读背景层和装饰层**。
- 轮廓被烘成「一格瓦片一个 texel」的遮罩（R8，8px 一格），所以描边严格落在瓦片边界上，任何缩放下都不会糊。
- 顶点像素按 UV 换算成房间像素坐标，所以一条 quad 就画完整间房。

## 为什么是"内侧顶面"

- 只在实心像素的**上表面**往下 1–2px 发光：上面是空气的那一排砖会亮，墙面、砖内部不会亮；
- 垂直墙面不发光，所以看起来像"顶面反光"而不是"描边"；
- 加法混合（`blend_add`），所以是在原来的砖色上加亮，不会盖掉贴图细节。

## 参数（`TerrainHighlight` 节点）

| 参数 | 默认 | 作用 |
| :--- | :--- | :--- |
| `layer_path` | `Terrain/SolidTiles` | 用哪一层瓦片做轮廓 |
| `rim_color` | 淡青白 | 高光颜色 |
| `rim_strength` | 0.85 | 亮度 |
| `rim_width` | 2 | 从上表面往下延伸几像素 |
| `rim_softness` | 0.6 | 带内衰减，0 = 硬边，1 = 渐隐 |
| `rim_grain` | 0.18 | 按像素抖动，避免看起来像矢量画的直线 |
| `draw_order` | 1 | z 顺序（在地形之上、雾/水/气体之下） |

## 接线

`scenes/runtime/world_root.tscn` 里已经有 `TerrainHighlight` 节点（和 `BackdropField` 同级）。它在 `world_ready` 时给每间已加载的房间挂一条 quad；房间重新烘焙后会重建，房间里没有实心瓦片时会把 quad 删掉。

想在别的世界根上用，把节点挂到世界根下、确保它旁边有 `TerrainRoot`（房间作为 TerrainRoot 的子节点）即可。直接挂在房间场景里时，把 `layer_path` 设成 `RoomContent/Terrain/SolidTiles`（源场景的路径）。

## 性能

一间房一条 quad，片元着色器每像素做 2–4 次遮罩采样加一个 ≤2 次的循环，没有逐帧 CPU 工作、没有额外 pass。实测开关这条高光对帧时间没有可测影响。

## 相关

- 气体裁剪墙体的剪影：`Atmosphere._build_solid_mask()`（同样是 `SolidTiles`，一格 texel）。
- 背面/背景的整屏底板：`scripts/world/backdrop_field.gd`。
