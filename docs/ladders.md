# 楼梯与 Hero 动画

## 放置楼梯瓦片

在源房间任意地形 `TileMapLayer` 中放置 `primordial_tileset.tres` 的 **(0,7)**：

- 备选 0：原始样式。
- 备选 1：transpose 横置样式。
- 两种备选及后续翻转备选共用相同移动逻辑，不需要实体碰撞多边形。

`RoomContent/Terrain/LadderAreaBuilder` 会在运行时把每个匹配瓦片转换为一个 8×8 `LadderZone`。它只在 `ladder_zone` 组中检测，不会把存档点等其他 trigger 当成楼梯。

不要手动编辑 `scenes/rooms/generated/` 中的地形或运行时场景。修改源房间后重新烘焙：

```powershell
godot --headless --path . -s res://scripts/tools/rebake_room.gd -- res://scenes/levels/room_01_00.tscn
```

该工具只处理命令行指定的一个源房间。

## 操作规则

- **A / D 或左右键**：左右攀爬。
- **W / 上**：向上攀爬。
- **S / 下**：向下攀爬，并播放 `climb`。
- **无输入**：在区域内悬停，不受重力。
- **跳跃**：获得正常起跳速度；区域内可连续按跳跃快速向上。
- **按住跳跃**：保留上升弧线；松开后恢复自由攀爬。
- **S + 跳跃**：退出攀爬并持续快速下落，直到落地、离开楼梯、按 W 或重生。
- **离开楼梯**：恢复普通重力和地面/空中跳跃规则。

斜向输入会归一化，避免斜向速度比直线更快。默认 `climb_speed = 72`，可在 `MovementProfile` 或角色调校资源中调整。

## Hero 动画接口

`PlayerController` 提供：

```gdscript
signal climb_animation_requested(active: bool, direction: Vector2)
func is_on_ladder() -> bool
```

`active = true` 表示自由攀爬状态，`direction` 是归一化输入方向；无输入时为 `Vector2.ZERO`。跳跃、快速下落、离开和重生时会发出 `active = false`。信号只在状态或方向改变时发出。

默认 `HeroAnimationController` 已连接此接口，无需手动连接即可使用用户提供的 Hero 帧图。要替换表现时，可连接同一公共接口驱动自己的动画节点。

## Hero 帧图与动画优先级

资源位于：

- `assets/generated/hero.png`：80×100，每帧 10×10。
- `resources/player/hero_sprite_frames.tres`：20 个 AtlasTexture 帧。
- `scripts/tools/build_hero_sprite_frames.gd`：可重复生成 SpriteFrames。

修改图片后先导入 Godot，再运行：

```powershell
godot --headless --path . -s res://scripts/tools/build_hero_sprite_frames.gd
```

动画行序：

| 行 | 动画 | 帧数 | 播放 |
| --- | --- | --- | --- |
| 0 | idle | 2 | 2 fps 呼吸循环 |
| 1 | walk | 4 | 8 fps 循环 |
| 2 | run | 4 | 12 fps 循环 |
| 3 | jump | 2 | 上升时播放，连续跳跃重播 |
| 4 | fall | 2 | 6 fps 循环 |
| 5 | climb | 2 | 8 fps 循环 |
| 6–9 | look_up / look_down / look_left / look_right | 各 1 | 静止方向帧 |

选择优先级：

1. 自由攀爬且按 W/S：`climb`。
2. 离地或楼梯跳跃/下落锁存：按垂直速度选择 `jump` / `fall`。
3. 地面按 W/S：`look_up` / `look_down`。
4. 实际水平移动：低于 85 px/s 用 `walk`，达到 85 px/s 用 `run`。
5. 静止不足 2 秒：按朝向使用 `look_left` / `look_right`。
6. 静止达到 2 秒：`idle` 呼吸。

普通循环动画通过 `flip_h` 翻转；look 专用方向帧不翻转。`SpriteRoot.scale` 保持正 X，避免双重翻转。楼梯内无输入不会误选 fall，静止 2 秒后也会进入呼吸。

## 测试

```powershell
godot --headless --path . -s res://tests/run_test_script.gd -- res://tests/platformer_kit/character/test_ladder_motion.gd
godot --headless --path . -s res://tests/run_test_script.gd -- res://tests/world/test_ladder_tiles.gd
godot --headless --path . -s res://tests/run_test_script.gd -- res://tests/player/test_hero_animation.gd
```

在 `scenes/levels/room_01_00.tscn` 源场景按 **F6** 可检查实际瓦片、移动和动画；重新烘焙后可验证正式世界运行时结果。
