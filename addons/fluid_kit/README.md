# Fluid Kit

Water and gas for 2D pixel games, as a self-contained Godot 4 addon: a 1D
shallow-water solver, a GPU 2D Navier-Stokes gas field with three densities, and
the scene nodes to author, emit, disturb and light both.

- **Water** `WaterField` — conservative column water, spill gates, waterfalls,
  splashes, buoyancy/swimming hooks.
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
| `splash_radius_base` / `splash_radius_scale` | 8 / 10 | Impact disturbance radius. |

| `splash_scene` | null | Optional effect scene spawned on every splash; the field also emits `splash_requested(world_position, power)`. |

The falling water at a spill lip is a water column quad in the pool palette
(`water_fall.gdshader`), not a texture and not particles. Up to four spills get
their own quad; each one is placed in the open columns just after the lip and is
at most two columns wide, so it never paints over a solid tile, and its height is
the real drop between the two surfaces. The volume itself stays in the height
field (the transfer is instant and conservative). Splashes are random droplets and
mist only: side-view games must not show round ripples, those read as top-down.

The simulation runs at 120 Hz over 8 px columns; the surface texture is uploaded
at most 60 times a second because the upload forces a GPU sync. Still pools sleep
and cost nothing.

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
| `demos/gas_plumes_demo.tscn` | Three vents, three densities, platform rows. |
| `demos/gas_effects_demo.tscn` | Jets, explosion, moving pillar (cycles). |
| `demos/gas_trail_demo.tscn` | Empty room, square walker, dissolving trail. |

The demo scenes instance the template's test world runners (they need the
template's tiles and player); the runtime itself does not.

## Tests

```powershell
godot --headless --path . -s res://tests/run_test_script.gd -- res://tests/world/test_water_simulation.gd
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
- The pressure solve is Jacobi: it removes ~93% of the divergence in open cells
  and leaves a small residual next to walls (no-flux boundary). More
  `pressure_iterations` tightens it; a multigrid V-cycle would be the next step.
- Density is a passive scalar with sources and sinks (ambient, vents, decay,
  player thinning), not a conserved quantity.
- Viscosity is explicit diffusion, clamped for stability; values above ~10 start
  to look like honey at 30 Hz.
- The gas grid is capped at 80x45 per room (4 px cells); water columns are 8 px.
