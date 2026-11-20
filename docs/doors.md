# Doors: Portals and Shuttle Doors

`WorldDoor` (`addons/platformer_kit/world/entities/world_door.gd`, scene
`world_door.tscn`) is a paired door. Contact activates it — the same feel as a
save point: it changes colour, the state is saved, and the trip happens at once.

There are two kinds:

| Kind | Travels | Data it needs |
| --- | --- | --- |
| `PORTAL` | to another door in the **same** world | `target_room_id` + `target_door_id` |
| `SHUTTLE` | to another door in **another** world | `target_world` + `target_room_id` + `target_door_id` |

## Authoring a pair

1. Drop `world_door.tscn` under a room source's `Entities` node (the same place
   as checkpoints and pickups), then bake the room.
2. Set `entity_id` to an id unique in that room, e.g. `cistern_door`.
3. Set `target_room_id` and `target_door_id` to the partner door's room and
   `entity_id`. The partner points back at this door, so every pair is
   bidirectional by construction.
4. A `SHUTTLE` door also needs `target_world` (the other `WorldData` resource).
   Put one door in each world; each names the other.
5. Keep `ArrivalSpawn` clear of `ActivationArea`. The default sits 20px to the
   right of the door, outside the 20px-wide sensor. The actor is placed on that
   marker, so if it overlapped the sensor the actor would arrive standing in the
   door and be sent straight back.
6. `activation_mode = INTERACT` swaps contact for the interact key (E / pad X)
   and exposes the door's `Interactable` area.

## What happens at runtime

`PORTAL` — `WorldRuntime.travel_to_door(room_id, door_id)` stages the target room
with the normal residency rules, places the actor on the partner's
`ArrivalSpawn`, disarms the arrival door and emits `current_room_changed`, so the
camera bounds, fog and map react exactly as on a room entrance transition.

`SHUTTLE` — `WorldSession.travel_to_world(world, room_id, door_id)` writes the
destination into the **same** save snapshot (`world_id`, `current_room_id`,
respawn identity), restarts the session on the new world, lands the actor on the
partner's `ArrivalSpawn`, queues a save commit and emits `world_ready` (which
rebuilds the map) plus `world_travel_completed(from_world_id, to_world_id)`.
Every loaded room of the old world flushes its entity state before it unloads,
so a crumbled bridge in world A is still crumbled when you come back.

Both kinds disarm the door they send from and the door they arrive at. A
disarmed door re-arms as soon as no actor is inside its sensor, so a door can
never bounce the actor straight back — but walking out and in again travels
again.

## Editor support

- Doors are `D` markers on the world canvas and appear in the room inspector's
  annotation list.
- **PORTAL arrows**: the flat canvas draws a teal arc with an arrowhead between
  the two doors of every same-world pair; an unmatched door gets a short red
  dashed stub labelled `unpaired`. Room entrance → spawn connections stay on the
  canvas as dim dashed lines, so layout plumbing never reads as a teleport.
- **3D stack view** (`3D` in the command bar): every world in the stack is a
  parallel horizontal slice, with its rooms and doors on it, portal arcs inside a
  slice and shuttle arcs between slices. Left drag orbits, middle/right drag (or
  Shift+left) pans, the wheel zooms. The floor plan is drawn the same way as the
  2D view — world `+y` goes down the plan, so a room sits where it does in 2D —
  and the stack axis is `z`, pointing up. A small axis gizmo in the top-right
  turns with the camera and carries the pointer's `x / y / z`. Clicking a slice
  opens that world in the flat 2D editor immediately.
- **Layer panel**: while the 3D view is on, the left column lists the stack
  resource instead of the rooms — one row per world with its `Z` index, `▲ ▼` to
  change its height, `✕` to remove it and `+ World` to add another. Layer 0 is the
  bottom slice; the world being edited is highlighted. The stack is a real
  resource (`WorldStack`, e.g. `resources/worlds/<world>_stack.tres`) referenced
  from `WorldData.world_stack`; the view draws exactly its layers and nothing
  else. Adding the first layer creates and saves that resource next to the world.
- Unmatched links are red dashed in both views and also produce one
  `... link ... is unmatched` warning in the Output panel.

## Tests

- `tests/world/test_world_door.gd` — scene contract, activation and save state,
  arrival/sensor clearance, disarming and re-arming, both travel paths.
- `tests/world/test_world_travel.gd` — portal travel end to end on a real room
  fixture (position, camera room switch, disarm), the bidirectional return trip,
  and the cross-world session swap including rollback when the target world is
  unusable.
