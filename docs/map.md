# Map System

Three views, one model. Nothing about the map is authored by hand: it is built
from the world the game is actually running (`WorldData` placements and each
room's baked terrain), so it cannot drift from the level.

## What is generated

- **Room blocks**: one `MapRoom` per `WorldData` room. `map_position` comes from
  the room's chunk placement, `map_size` from `room_size_chunks`. There is no
  separate hand-made map resource to keep in sync.
- **Links**: `WorldData.connections` become map links; both ends must exist.
- **Terrain**: `RoomTerrainSnapshot` scans a baked room's terrain scene once
  (cached by file modification time) and records every cell as wall, background,
  one-way, glass, ladder, crumble or vision blocker.
- **Exploration**: the fog's saved `room:x,y` ids are converted back into
  room-local cells by `MapExploration`. A room's ratio is explored cells divided
  by the room's full cell area.
- **Live source**: `MapExplorationSource` merges the persistence bridge (every
  visited room, persisted in the save) with the fog's live cells of the loaded
  room. Previews and the test-world runner work without a save file.

## Precise map

`MapPreciseRenderer` paints one pixel per 8x8 cell at the current zoom (default
3x, wheel zooms the whole map).

- Only explored cells are painted: walls blue-grey, one-way green, glass light
  blue, ladders brown, crumble gold, background dark navy.
- Unexplored cells inside a visited room stay dark.
- Rooms that were never entered are drawn as a dark plate with a border, so the
  world shape is visible without leaking content.
- The current room has a yellow border; the player is a yellow marker.
- The player marker scales **progressively** with the map: at 1x-2x it keeps its
  minimum size (3 px) so it never disappears, from 2x upwards it grows with the
  zoom (at 4x it is 6 px, at 8x it is 12 px) so it stays recognizable on a
  zoomed-in map. Size = `player_icon_px * max(1, zoom / 2)`.
- Zooming does not reset when new cells are revealed; only opening the map fits
  the whole world again.

## Grid map

`MapGridRenderer` draws one block per room, metroidvania style:

- Fill brightness = the room's exploration ratio (dark plate at 0%, full room
  color at 100%). Percent labels are drawn when the block is wide enough.
- Current room: yellow border. Visited rooms: a small green dot.
- Links are drawn as notches across the shared edge of room blocks.
- The player is a yellow dot inside the current block.

## Minimap

`MapMinimap` sits in the top-right corner (196x136 screen pixels) and mirrors the
full map's style:

- Grid style: nearby room blocks and their brightness, centered on the current
  room.
- Precise style: explored terrain around the player.
- Hidden until a world is running, and while the full map is open.

## Controls

| Input | Action |
| :--- | :--- |
| `M` / left stick click | Open or close the full map |
| `Tab` / pad `Y` | Switch precise <-> grid while the map is open |
| `Esc` / `M` | Close the map |
| Mouse wheel | Zoom the full map |

The game pauses while the full map is open and resumes with its previous pause
state when it closes.

## Tests

`tests/metroidvania_kit/test_map_rendering.gd`:

- the definition follows world placements, sizes and connections;
- the terrain snapshot classifies walls, glass, ladders and crumble tiles and is
  cached by file time;
- exploration ids are converted to room-local cells and ratios;
- the precise image paints explored terrain exactly and leaves unexplored cells
  dark;
- the exploration source merges saved and live cells without duplicates;
- the map screen and minimap build their renderers and switch styles.

Run:

```text
godot --headless --path . -s res://tests/run_runtime_suite.gd
```
