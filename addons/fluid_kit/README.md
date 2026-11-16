# Fluid Kit

Water and gas for 2D pixel games, as a self-contained Godot 4 addon: a 1D
shallow-water solver, a conservative 2D cell fluid, a GPU 2D Navier-Stokes gas
field with three densities, and the scene nodes to author, emit, disturb and
light both.

- **Water** `WaterField` — conservative column water, spill gates, waterfalls,
  splashes, buoyancy/swimming hooks.
- **Grid water** `WaterGrid` — 2D cell fluid: fill a region, let tile walls hold
  it, watch it fall, level, spill and drain. Same query surface as `WaterField`.
- **Gas** `Atmosphere` — incompressible Navier-Stokes (semi-Lagrangian advection,
  buoyancy forces, Jacobi pressure projection), three gas channels (heavy,
  neutral, light), viscosity, decay, vents, trail emitters, one-shot blasts,
  moving interactors, lighting and a CPU fallback.
- **Demos** in `demos/` — runnable scenes, no images required.

Everything is plain nodes and resources; the addon has no dependency on the
template's player, tiles or UI. It integrates through the room-extension surface
(`bind_room_with_origin`, `clear_room`, `bind_player`, `bind_settings_source`)
that anything can implement, or you can drive the fields manually.

## Install

1. Copy `addons/fluid_kit/` into the project and enable **Fluid Kit** in
   *Project Settings → Plugins* (the plugin has no editor UI, it only keeps the
   runtime classes registered).
2. Add a `WaterField` and/or an `Atmosphere` node to your world.
3. Feed them the room geometry at runtime (see *Integration*).

## Nodes

| Node | Role |
| :--- | :--- |
| `WaterField` | Owns the pools of one room, the water quad, the simulated falling streams and splash requests. |
| `WaterGrid` | Owns the 2D cell fluid of one room: the cell texture, the surface quad, the room scan. |
| `FluidRegion` | Room marker: rectangle that starts filled with water; walls inside it remove volume. |
| `Atmosphere` | Owns the gas field of one room, the gas quad, vents, lights and the GPU pipeline. |
| `WaterBasin` | Room marker: pool rectangle; its top edge is the initial surface. |
| `WaterGate` | Room marker: holds water back until opened. |
| `GasVent` | Static nozzle emitting one gas channel with a jet. |
| `GasField` | Room marker: per-room ambient density, decay, diffusion, refill. |
| `GasInteractor` | Attach to any entity: push (drag the gas), emit (trail) or blast. |
| `GasTrailWalker` | Demo helper: a 1x1-cell walker that loops a square and emits a trail. |
| `FogLight` | Point light that brightens the gas (up to 3 static + the player light). |

## Integration

The fields are written for a room-based game (the template's `WorldSession`), but
they only need a few calls:

```gdscript
# when a room becomes active
atmosphere.bind_room_with_origin(room_data, room_root, origin_chunk)
water_field.bind_room_with_origin(room_data, room_root, origin_chunk)

# when the player spawns
atmosphere.bind_player(player)
water_field.bind_player(player)

# optional: read a settings object with is_atmosphere_enabled()
atmosphere.bind_settings_source(settings)

# when leaving
atmosphere.clear_room()
water_field.clear_room()
```

`bind_room_with_origin` returns `true` when the field has nothing to do (for
example a room without pools). Rooms are described by a resource with
`room_id`, `size_pixels` (or a `Vector2` size) and a terrain root whose
`SolidTiles` layer holds the collision tiles; the mask is scanned from it, so an
authored tile map is all the geometry you need.

Water and gas are drawn through a `MeshInstance2D + QuadMesh` with a
`canvas_item` shader. World position comes from the quad UV (`uv.y` flipped);
never use `VERTEX + offset` in these shaders, it is not reliable in the fragment
stage.

## Water

See `docs/water-authoring.md` for a step-by-step guide to drawing a water room
(terrain rules, `WaterBasin` markers, initial water, and how the falling columns
hug the lower pool and widen with the flow).

```gdscript
# in a room with WaterBasin / WaterGate markers
water_field.request_splash(world_x, impact_speed)   # hero entered the pool
water_field.get_surface_y_at(world_x)               # for buoyancy
water_field.is_ready()
```

| WaterField parameter | Default | Meaning |
| :--- | :--- | :--- |
| `max_depth` | 64 | Maximum depth per column (px), the capacity. |
| `flow_rate` | 54 | Column-to-column transfer; stability limit is `SIM_HZ / 2`. |
| `waterfall_min_drop` | 5 | Smallest surface drop that gets a falling column (px). |

| `splash_scene` | null | Optional effect scene spawned on every splash; the field also emits `splash_requested(world_position, power)`. **Keep it cheap**: one is spawned per impact, and a baked PixelFX effect is cached per option set, so a continuous `power` re-bakes a 300 ms effect for every distinct impact speed. `game/water/effects/water_splash_pixels.tscn` is a hand-drawn splash that costs nothing to spawn. |

The falling water at a spill lip is a water column quad in the pool palette
(`water_fall.gdshader`), not a texture and not particles. Up to four spills get
their own quad; each one is placed in the open columns just after the lip and is
at most two columns wide, so it never paints over a solid tile, and its height is
the real drop between the two surfaces. The volume itself stays in the height
field (the transfer is instant and conservative). A splash is a cheap droplet
effect plus a shader-only surface ripple: an impact never displaces the body, so
entering, hopping out or swimming adds no volume and wakes no waves. Side-view
games must not show round ripples, those read as top-down.

The simulation runs at 120 Hz over 8 px columns; the surface texture is uploaded
at most 60 times a second because the upload forces a GPU sync. Still pools sleep
and cost nothing.

## Water: the 2D grid (`WaterGrid`)

`WaterField` is a 1D height field: one surface per column, which is perfect for
pools, dams and waterfalls but cannot describe water flowing around a rock inside
a pool, or a second pool above another one. `WaterGrid` is the full 2D variant:
the room becomes a grid of `cell_pixels` (8 px by default) tanks, each holding up
to one cell of water, and the water flows between them.

Authoring is two things only:

1. tile walls in `SolidTiles`, exactly like any other terrain;
2. a `FluidRegion` marker per body of water. Its rectangle is *filled*: every
   open cell inside it starts full, and a wall inside the rectangle keeps its
   own volume out of the fluid.

The grid simulates the whole room from there: water falls, levels out, spills
over ledges and drains through holes. Nothing is authored per frame.

```gdscript
# WaterGrid implements the same queries as WaterField, so the swimming
# component works unchanged; the 2D variants are exact.
water_grid.is_ready()
water_grid.get_surface_y_at_point(player.global_position)
water_grid.get_flow_velocity_at_point(player.global_position)
water_grid.add_water(point, radius, volume)      # a spring, leaked pipe, ...
water_grid.remove_water(point, radius, volume)   # a drain
water_grid.request_splash(world_x, impact_speed)
```

How a step works (fixed `sim_hz`, 60 by default):

1. **gravity**: every cell pours at most one cell of water into the cell below
   while that one has room, so a fall is a visible falling column;
2. **leveling**: neighbouring column surfaces trade water from the higher one to
   the lower one, swept four times, which keeps a wide basin flat while it
   drains;
3. **lateral flow**: standing cells in the same row exchange water by surface
   height, with an extra overflow rate for a full cell backed up on a ledge so it
   pours over the edge instead of seeping.

Water never moves upward, only down or sideways: that is what keeps a pool in
its basin and a waterfall a column instead of a sheet. Every transfer goes
through a scratch array and is limited by the donor's water and the receiver's
free space, so total volume is conserved exactly and no cell ever leaves
`[0, cell_pixels]`.

| WaterGrid parameter | Default | Meaning |
| :--- | :--- | :--- |
| `cell_pixels` | 8 | Cell size. 8 matches the tile grid; 4 is finer at 4x the cells. |
| `sim_hz` | 60 | Steps per second. |
| `lateral_rate` | 24 | Row-to-row transfer coefficient (1/s). |
| `fall_rate` | 1 | Cells a falling cell may dump per step. |
| `overflow_rate` | 30 | Extra spill rate for a full, backed-up cell. |
| `level_rate` | 96 | Column leveling coefficient (1/s), swept 4x per step. |
| `ripple_amplitude` | 1.8 | Visual surface ripple at an impact (px). Purely shader-side: an impact never displaces the body. |
| `shallow_color` / `deep_color` / `crest_color` / `foam_color` | water palette | Render colours. |

The renderer uploads an RGBA cell texture at 30 Hz: fill, depth above the cell,
motion, and a cell kind (water / wall / empty). The surface is ramped
horizontally between cells and a falling cell is drawn at full height, so a thin
stream reads as a continuous column. A splash is drawn, not simulated: the
shader adds a decaying ring offset to the top cell of the affected columns and
the particle scene adds the droplets, so jumping in the water never moves the
body. `demos/grid_water_demo.tscn` is the runnable demo and starts the hero
inside the left pool; `docs/water-authoring.md` has the authoring rules.


## Gas: the solver

Per fixed step (`sim_hz`, 10..60):

1. semi-Lagrangian self-advection of the velocity, plus forces: buoyancy of the
   three densities (`gas_buoyancy`, px/s²), vent jets, the interactor push, the
   one-shot blast and the trail emitter;
2. viscosity: velocity diffusion towards the four neighbours (`gas_viscosity`,
   1/s, explicit and clamped to stay stable);
3. divergence of the intermediate velocity (backward difference);
4. pressure Poisson solve: `laplacian(p) = divergence`, `pressure_iterations`
   Jacobi passes, warm started from the previous step;
5. projection: `u = u* - grad(p)` (forward difference, the exact adjoint of the
   divergence, so the discrete divergence is zero);
6. the three densities are advected by the projected velocity, then diffused,
   refilled towards the room ambient, injected by vents/emitters, faded by
   `gas_decay` and thinned around the player.

The gas is a passive scalar set on a divergence-free field: it cannot pile up,
only swirl and fade. `GAS_FIELD_CELL` is 4 px and the grid is capped at 80x45 per
room; the whole pipeline is 20 GPU passes (16 pressure + 4) on HDR viewports.

## Gas parameters (`Atmosphere`)

| Parameter | Default | Meaning |
| :--- | :--- | :--- |
| `sim_hz` | 30 | Steps per second; the master speed knob. |
| `pressure_iterations` | 16 | Jacobi iterations of the pressure solve. |
| `gas_viscosity` | 0.0 | Kinematic viscosity (1/s): thicker gas, calmer plumes. |
| `gas_wind` | (7, -1.5) | Constant drift in px/s, added on top of the solved field. |
| `gas_buoyancy` | (240, 0, 300) | Heavy/light buoyancy acceleration (px/s²). |
| `gas_dissipation` | 0.4 | Velocity damping per second. |
| `gas_diffusion` | 0.25 | Density diffusion. |
| `gas_refill` | 0.35 | Re-fill towards the ambient density. |
| `gas_decay` | 0.0 | Exponential fade per second (`0.5` ≈ 1.4 s half life). |
| `gas_ambient` | (0.28, 0.22, 0.32) | Ambient density per channel. |
| `push_radius` / `push_strength` | 34 / 1.4 | Player disturbance radius (px) and strength. |
| `gas_alpha` | (0.5, 0.42, 0.4) | Per-channel opacity. |
| `base_alpha` / `light_alpha` | 0.6 / 0.9 | Opacity without/with light. |
| `noise_amount` | 0.45 | Wispy noise strength. |
| `heavy_color` / `neutral_color` / `light_color` | rust / cyan / yellow | Channel colours. |
| `player_light_radius` / `energy` | 74 / 1.0 | Player lantern. |

`GasField` overrides `ambient`, `decay`, `diffusion` and `refill` per room: an
empty room with trails is `ambient = (0,0,0)`, `refill = 0`, `decay = 0.32`.

## Generating gas

```gdscript
# static nozzle placed in the room (GasVent node): rate per second, jet in px/s
vent.rate = 3.2
vent.jet_speed = 460.0
vent.channel = GasVent.Channel.HEAVY

# the Atmosphere collects the room's vents (up to 4), re-read after editing:
atmosphere.refresh_vents()

# one-shot explosion at a world position
atmosphere.trigger_explosion(world_position, 34.0, 190.0, 1.1)  # radius, px/s, density

# a moving trail source: gas pushed backwards from the emitter
atmosphere.set_gas_emitter(world_position, 13.0, 6.0, -direction * 105.0, 1.0)
atmosphere.clear_gas_emitter()
```

## Entities that interact with the gas

Drop a `GasInteractor` on any `Node2D` and pick a mode:

| Mode | What it does | Typical use |
| :--- | :--- | :--- |
| `PUSH` | Drags the gas along the node's box using its measured velocity. | Pillars, pistons, moving platforms, big enemies. |
| `EMIT` | Injects gas with a backward initial velocity. | Characters, exhausts, walkers. |
| `BLAST` | One-shot radial blast (`blast()` or `blast_on_ready`). | Explosions, impacts. |

The interactor reads the `Atmosphere` from the `atmosphere` group, so it works in
any room without wiring. The gas field provides one push slot and one emit slot;
`GasVent` nozzles are separate and support four at once. For custom behaviour call
the Atmosphere API directly (`set_gas_mover`, `set_gas_emitter`,
`trigger_explosion`) or add a `GasField` per-room configuration.

## Demos

| Scene | Shows |
| :--- | :--- |
| `demos/water_demo.tscn` | Pools, gate, waterfall, splashes, floating, lit gas. |
| `demos/grid_water_demo.tscn` | 2D grid fluid: a filled region, a dam, a waterfall, a drain hole. |
| `demos/gas_plumes_demo.tscn` | Three vents, three densities, platform rows. |
| `demos/gas_effects_demo.tscn` | Jets, explosion, moving pillar (cycles). |
| `demos/gas_trail_demo.tscn` | Empty room, square walker, dissolving trail. |

The demo scenes instance the template's test world runners (they need the
template's tiles and player); the runtime itself does not.

## Tests

```powershell
godot --headless --path . -s res://tests/run_test_script.gd -- res://tests/world/test_water_simulation.gd
godot --headless --path . -s res://tests/run_test_script.gd -- res://tests/world/test_water_grid.gd
godot --headless --path . -s res://tests/run_test_script.gd -- res://tests/world/test_water_grid_room.gd
godot --headless --path . -s res://tests/run_test_script.gd -- res://tests/world/test_water_buoyancy.gd
godot --headless --path . -s res://tests/run_test_script.gd -- res://tests/world/test_atmosphere_fog.gd
godot --headless --path . -s res://tests/run_test_script.gd -- res://tests/world/test_atmosphere_settings.gd
godot --headless --path . -s res://tests/run_test_script.gd -- res://tests/world/test_water_room_contract.gd
```

All five also run in `tests/runtime_suite.gd`. Headless has no `RenderingDevice`,
so the gas falls back to the CPU `FogGrid` and the same tests cover that path.

## Performance and limits

- Gas: ~0.06 ms of CPU per step for 20 GPU passes on an 80x45 grid; the 120 fps
  frame budget (8.3 ms) makes it drop ~1% of frames, 60 fps is flat. Water: a
  sleeping pool costs nothing; the surface upload is capped at 60 Hz.
- Grid water: 0.8 ms per 60 Hz step for a 320x180 room fully in motion at 8 px
  cells (920 cells); a normal basin is a fraction of that and a settled pool
  sleeps. `cell_pixels = 4` quadruples the cell count.
- The pressure solve is Jacobi: it removes ~93% of the divergence in open cells
  and leaves a small residual next to walls (no-flux boundary). More
  `pressure_iterations` tightens it; a multigrid V-cycle would be the next step.
- Density is a passive scalar with sources and sinks (ambient, vents, decay,
  player thinning), not a conserved quantity.
- Viscosity is explicit diffusion, clamped for stability; values above ~10 start
  to look like honey at 30 Hz.
- The gas grid is capped at 80x45 per room (4 px cells); water columns are 8 px.
