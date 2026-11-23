# Metroidvania Kit 0.1.0

Optional progression, map discovery, fog, markers, fast travel, and save-bridge
layer for Platformer Kit games. The map is **built from the world that is
actually running** (`WorldData` placements + baked room terrain), so it cannot
drift from the level; nothing about the map is authored by hand.

## Compatibility

| Item | Value |
| --- | --- |
| Godot | 4.7 |
| Platformer Kit | 0.1.0 (`WorldData`, `RoomData`, room runtime, `SaveSnapshot`) |
| Autoloads | none |
| Editor plugin | `addons/metroidvania_kit/plugin.cfg` (no editor UI) |

## Install and wiring

1. Enable `addons/metroidvania_kit/plugin.cfg`.
2. Keep the `FogOfWar` and `MetroidvaniaPersistenceBridge` nodes under the world
   root (`scenes/runtime/world_root.tscn` ships both).
3. Compose the runtime in the game shell (this is exactly what `game/app/main.gd`
   does, typed):

```gdscript
var progression := ProgressionContext.new()
var discovery := MapDiscovery.new()
var markers := MarkerRegistry.new()
var world_state := MetroidvaniaWorldState.new()
var fast_travel := FastTravelRegistry.new()
var definition := MapDefinitionBuilder.from_world(world_root.world_data)

var map_runtime := MapRuntime.new()
map_runtime.configure(definition, discovery, markers)
var tracker := MapTracker.new()
tracker.configure(map_runtime, [RevealAdjacentRooms.new()])
world_runtime.current_room_changed.connect(
    func(room_id: String) -> void: tracker.track_room(StringName(room_id))
)
bridge.configure(progression, discovery, markers, world_state, fast_travel, fog)
bridge.bind_save_manager(SaveManager)
loadout.bind_progression(progression)
```

## Modules

| Area | Files | Public surface |
| --- | --- | --- |
| Progression | `progression/` | `ProgressionContext.grant_ability / has_ability / grant_item / consume_item / set_flag`; conditions `FlagCondition`, `HasAbilityCondition`, `HasItemCondition`, `CompositeCondition` all expose `evaluate(context, world_state)` |
| Gates | `gates/progression_gate.gd` | `allows()`, `request_access()` — a room-side gate that reads a condition |
| Map data | `map/data/` | `MapDefinition` (`get_room`, `get_room_by_world_id`, `get_room_ids`, `get_neighbors`, `get_region_room_ids`), `MapDefinitionBuilder.from_world()`, `MapRoom`, `MapRegion`, `MapConnection`, `RoomTerrainSnapshot` |
| Discovery | `map/discovery/` | `MapDiscovery.get_state / mark_discovered / mark_visited / mark_cleared / to_dictionary`, `FogOfWar` (cell visibility + explored storage), `FogVisibility.compute_visible_cells`, `RevealRule` plus `RevealCurrentRoom`, `RevealAdjacentRooms`, `RevealByRadius`, `RevealRegion`, `RevealAll` |
| Markers | `map/markers/` | `MarkerRegistry.register_marker / get_marker / set_discovered / set_active / set_completed / visible_markers` |
| Runtime | `map/runtime/` | `MapRuntime.configure / enter_room / enter_world_room / get_room_state / exploration_ratio`, `MapTracker.configure / track_room`, `MapExploration` (cell/ratio queries), `MapModel` (legacy flat dictionary builder, kept for 0.1.0 compatibility) |
| Map UI | `map/ui/` | `MapScreen` (full-screen, `open/close/toggle/set_style`), `Minimap`, `MapView`, `MapRenderer`, `MapGridRenderer`, `MapPreciseRenderer` |
| Fast travel | `fast_travel/` | `FastTravelRegistry.register_point / unlock / can_travel / get_destination`, `FastTravelPoint` |
| World state | `world_state/` | `MetroidvaniaWorldState` (dictionary state), `MetroidvaniaSaveAdapter` (capture/restore with rollback), `MetroidvaniaPersistenceBridge` (`configure`, `bind_save_manager`, `bind_fog`, `mark_cell_explored`, `mark_chunk_explored`, `mark_zone_revealed`, `get_fog_version`) |

## Save format

The bridge stores one module entry under `metroidvania_kit` in `SaveSnapshot`:

```text
metroidvania_kit = {
    progression, rooms, markers, world_state, fast_travel,   # component dictionaries
    fog = { cells: [], chunks: [], zones: [] }                # explored ids
}
```

`state_restored` is emitted after a restore (including the empty-state reset), so
the player ability loadout can re-synchronise unlocked abilities. Restoring a
malformed state returns `false` and leaves the live components untouched; the
adapter rolls back partially applied components.

## Tests

```powershell
godot --headless --path . -s res://tests/run_runtime_suite.gd -- --group=metroidvania_kit
godot --headless --path . -s res://tests/run_test_script.gd -- res://tests/metroidvania_kit/test_map_core.gd
godot --headless --path . -s res://tests/run_test_script.gd -- res://tests/metroidvania_kit/test_map_rendering.gd
godot --headless --path . -s res://tests/run_test_script.gd -- res://tests/metroidvania_kit/test_map_runtime_persistence.gd
```

Fog integration has its own large suite in `tests/world/test_fog_visibility.gd`
(run with `--group=world`).

## Known limits

- No pathfinding or navigation: the map is a display/discovery model only.
- Fog reveal is cell flood-fill per room; very large rooms cost proportionally to
  their cell count, not their screen count.
- `RevealByRadius`, `RevealRegion`, `RevealAll` and the condition types are
  extension points; the shipped game only uses `RevealAdjacentRooms`.
- The map UI uses the project theme; it ships no theme of its own.
- Fast travel unlocks are persisted through the bridge, but no travel UI is
  included.
