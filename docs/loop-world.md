# The Loop Cistern (回环水窖)

Four rooms in a ring. No sliding puzzle: this world is about water, crumbling
planks, falling platforms and one well-earned dash that takes you back to the
platform you started on.

Select **回环水窖 · The Loop Cistern** in the world menu, or run
`res://scenes/levels/loop/loop_runner.tscn` directly with the debug overlay on.

## The route

```text
        loop_gallery (1,-1)  <-- lift, belt, dash pickup
              ^  north
              |
loop_relay (-)-- loop_entry -- east --> loop_split
(0,-1)  |    shaft drop            swim / falling platforms
        v  south
     loop_entry (0,0)  <-- you land back on the spawn platform
```

1. **loop_entry** — start on the small platform. Zig-zag down the one-way
   ledges. The only way east is a **crumbling bridge** over a pool: it gives way
   under you and drops you into the water (a splash, not a death). Swim to the
   ladder, climb out, walk east. There is a checkpoint on the dry floor.
2. **loop_split** — four **falling platforms** bridge a pool. They sink the
   moment you stand on them, so it is a rhythm crossing. Miss one and you swim
   the low road: the pool is safe, and a ladder at the far wall takes you back
   up. The ceiling opening leads north.
3. **loop_gallery** — step onto the **elevator**: it only moves when a rider is
   on it, so it never wanders off. It carries you up the room. At the top a
   **conveyor** pushes you back east while you walk west; fight it to the
   **dash pickup** and out the west opening.
4. **loop_relay** — the other **conveyor** guards the edge of a **dash gap**.
   Run west, jump and dash across; land, then walk off into the shaft. You fall
   back into **loop_entry** and land on the very platform the run started on.
   Falling into the pit instead respawns you at the relay checkpoint.

## Why it works

- Every failure is recoverable: water is swimmable, the falling platforms have a
  low road, the elevator waits for a rider, and the pit has a checkpoint.
- The ring only closes after you collect the dash, so the reward is the route
  itself. The return is a drop into the room you know, from the ceiling, onto
  the first platform.
- Rooms stay resident while nearby, so the bridge you collapsed on the way in is
  still gone when you drop back in: the loop is visible in the world state.

## Authoring pieces

- `scenes/levels/loop/*.tscn` — editable source rooms; paint the middle layer.
- `resources/worlds/loop_world.tres` — the world (rooms, placements, ring
  connections).
- `scenes/levels/loop/loop_runner.tscn` — direct launcher with the debug HUD
  and overlay enabled.
- Water: `WaterBasin` markers under `RoomContent/Entities` (column field).
- Falling platforms: `PlatformBody2D` + `FallMotionComponent2D` + a rider
  trigger that activates the fall.
- Elevator: `PlatformBody2D` + `ElevatorMotionComponent2D` + a rider trigger
  with `trigger_once = false`.
- Conveyors: `PlatformBody2D` + `ConveyorSurfaceComponent2D`.
- Checkpoints: `save_point.tscn`; the pit uses a `Killzone`.

## Tuning notes

- The hero clears 3.5 tiles of height; every vertical step in the ring is 2-3
  rows except the bridge drop and the shaft, which are one-way descents.
- The dash gap is 8 cells (64 px): a plain jump (~56 px) falls short, jump +
  dash clears it.
- The elevator travels 14 cells at 56 px/s and idles at the bottom until a rider
  steps on it.

## Tests

- `tests/platformer_kit/platforms/test_elevator_motion.gd` — idle until a
  rider, rises to its travel offset, waits, returns, re-arms.
- The loop world itself is validated by `WorldValidation` on start (rooms,
  placements, entrances, spawns); the suite starts the world in
  `test_world_*` style and the runner exercises it in the editor.
