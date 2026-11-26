# Benchmark: solver rooms

`solver-bench`（暂名：16 个房间的求解基准）

`tools/benchmark/` 是一个只跑求解器（栅格 + 动作模拟 + A\*）的基准：每个房间是一道题，两个路径点
（起点/终点），按房间授予或卸下冲刺/爬墙，按房间给帧数预算，超时算失败。

## 跑一次

```powershell
godot --headless --path . -s res://tools/benchmark/run_benchmark.gd
godot --headless --path . -s res://tools/benchmark/run_benchmark.gd -- --bias=4 --verbose
```

退出码 0 表示全部通过；有房间失败时非 0。`--bias` 打开 A\* 的稳定度代价（见下），
`--verbose` 打印每道题实际选中的动作序列。

## 房间表

房间尺寸与正式房间一致（40 × 23 格 = 320 × 184 px），地形用矩形描述，`benchmark_rooms.gd`
把它们展开成 `AutopilotGrid.build_from_rows` 吃的行。

| 房间 | 考什么 | dash | climb | 预算 |
| --- | --- | --- | --- | --- |
| `flat` | 一屏平地直走 | | | 720 |
| `steps` | 三处一格台阶 | | | 1080 |
| `one_way_up` | 从下往上穿过单向平台 | | | 1080 |
| `ladder` | 爬梯到侧边平台 | | | 1320 |
| `gap_run` | 跑跳过 6 格缺口 | | | 1080 |
| `gap_dash` | 冲刺过 12 格缺口 | ✓ | | 1080 |
| `dash_ledge` | 跳+冲刺上高台 | ✓ | | 1200 |
| `climb_shaft` | 贴墙爬竖井 | | ✓ | 1320 |
| `wall_jump` | 登墙跳出井口 | | ✓ | 1440 |
| `no_climb` | 没爬墙能力时靠台阶绕上去 | | | 1680 |
| `one_way_slot` | 冲刺穿过单向平台下的缝 | ✓ | | 1200 |
| `low_ceiling` | 低矮通道只能短跳 | | | 1200 |
| `staircase` | 六级楼梯 | | | 1440 |
| `narrow_landings` | 一格宽落脚点连跳 | | | 1440 |
| `mixed` | 梯子 + 冲刺 + 单向平台 | ✓ | ✓ | 1680 |
| `stable_choice` | 隧道与屋顶两条路：同代价时选稳的 | | | 1440 |

预算单位是物理帧（120 Hz），失败判据：规划不出路线，或路线模拟长度超过预算。

## 稳定度代价（`--bias`）

`AutopilotPlanner.stability_bias` 会按落点周围"空余格数"（左右上，最多 3 格）给每条腿加一点
排序权重。它只进入**优先级**，不进入 `g`（`g` 仍是纯帧数），并且总量被 `STABILITY_CAP` 截住，
所以它只是"同代价附近优先选稳的"，不改变可行性判据——这一点是基准测出来的，不是设计时假设的。

实测（`--bias=0` vs `--bias=4`）：

| 指标 | bias 0 | bias 4 |
| --- | --- | --- |
| `stable_choice` 路线 | 隧道，19 段，274 帧，平均余量 **0.63** | 屋顶，5 段，328 帧，平均余量 **3.00** |
| `one_way_slot` | 206 帧 / 余量 2.50 | 232 帧 / 余量 3.00 |
| `no_climb` | 通过 | **失败**（深路线上被排序挤出扩张预算） |

结论：稳定度代价确实把"贴着天花板钻过去"换成了"从上面走"，代价是 50 帧左右的长度；但在
最深的一条路线上它会破坏可达性，所以**默认关闭**（`stability_bias = 0.0`），等把"排序不应
影响可达性"这件事彻底解决（例如把先到先得换成可替换节点）再默认开启。

## 加一道题

在 `benchmark_rooms.gd` 的 `specs()` 里追加一项：

```gdscript
rooms.append({
	"id": "my_room",
	"title": "what it tests",
	"start": Vector2i(2, 19),      # 会被吸附到最近落脚点
	"goal": Vector2i(37, 19),
	"seconds": 8.0,                # 预算 = 秒 × 120 帧
	"dash": false,                 # 本房间是否允许冲刺
	"climb": false,                # 本房间是否允许贴墙爬
	"solid": [Rect2i(0, 20, 40, 3)],
	"one_way": [],
	"ladder": [],
})
```

坐标是格：`Rect2i(x, y, w, h)`；地表矩形所在行就是可站立行（身体在它上方）。
