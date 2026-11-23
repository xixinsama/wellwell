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
| `GasBrush` | Paints gas at the cursor: hold the left button to pour, right to shove, 1/2/3 for the channel. |
| `FogLight` | Point light that brightens the gas (up to 3 static + the player light). |

## Trying it in a room bigger than the screen

`scenes/levels/test/gas_field_lab_runner.tscn` is a 2x2 chunk room (640x360) crossed
by corridors, with one `GasBrush` and no other gas source. Run it and paint:

| Input | Effect |
| :--- | :--- |
| hold left button | pours gas at the cursor; move while holding to fling it (the gas inherits the cursor's velocity) |
| right button | a one-shot blow at the cursor: moves gas without adding any |
| 1 / 2 / 3 | heavy (sinks) / neutral (drifts) / light (rises) |
| mouse wheel | cycles the channel |

The room exists because every other room is exactly one screen: there the camera
never moves, so a field anchored to the room and a field anchored to the view look
identical. Here the camera scrolls over a 160x90 cell field, which is where "the gas
belongs to the world" becomes visible:

* paint a puff, then walk to the other half of the room - the puff is still there,
  in the same world position;
* the gas keeps being simulated while it is off screen (measured: a puff painted
  entirely off screen reads 0.0% of the opacity layer in the first frame and 6.4%
  after the camera scrolls onto it);
* the solver step costs 0.094 ms at 160x90 against 0.063 ms at the 80x45 of a
  one-screen room, i.e. four times the cells for 1.5x the submit cost, and the whole
  2x2 room still renders in 1.29 ms/frame uncapped.

`scripts/tools/build_gas_field_lab.gd` regenerates the room and its world resource
(it refuses to overwrite the source scene without `--force`). There is no vent and no
ambient gas in it on purpose: everything you see there is gas you put there.

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
water_grid.request_splash_at(player.global_position, impact_speed)  # exact body
water_grid.request_splash(world_x, impact_speed)                   # x only
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
| `cell_pixels` | 4 | Cell size. The grid runs smaller time steps on a finer grid, so the water falls and spills at the same px/s at any size. |
| `sim_hz` | 60 | Steps per second. |
| `lateral_rate` | 24 | Row-to-row transfer coefficient (1/s), tuned for 8 px cells. |
| `fall_rate` | 1 | Cells a falling cell may dump per step. |
| `overflow_rate` | 30 | Extra spill rate for a full, backed-up cell. |
| `level_rate` | 96 | Column leveling coefficient (1/s); two sweeps per step on a fine grid, three on 8 px. |
| `ripple_amplitude` | 3.6 | Visual surface ripple at an impact (px). Purely shader-side: an impact never displaces the body. |
| `ripple_speed` | 64 | How fast the ripple ring travels outwards (px/s). Lower is a slower, heavier swell. |
| `ripple_damping` | 1.1 | Ripple damping per second; lower keeps the swell alive longer. |
| `shallow_color` / `deep_color` / `crest_color` / `foam_color` | water palette | Render colours. |

The renderer uploads an RGBA cell texture at 30 Hz: fill, depth above the cell,
motion, and a cell kind (water / wall / empty). The surface is a height field
interpolated between cell centres, so a pool reads as a continuous line and a
falling stream gets soft edges instead of a staircase of whole cells. A splash is
drawn, not simulated: the shader adds a decaying ring to the top cell of the
affected columns, peaking at the impact point and travelling outwards from it.
The ripple is anchored to the surface it was made on (it fades with the vertical
distance to that surface), so jumping in a pool at the bottom of a room never
wobbles a pool higher up; pass the impact *point* (`request_splash_at`) rather
than only its x, because a column can hold more than one body of water.
`demos/grid_water_demo.tscn` is the runnable demo and starts the hero inside the
left pool; `docs/water-authoring.md` has the authoring rules.

### Why the grid water is CPU-only

A GPU version of this grid was built and measured, and it loses for this kind of
game, so it is not shipped:

- gameplay asks the water questions every frame — the hero's buoyancy needs the
  surface under the body, enemies need `is_water_at` — and a GPU simulation has to
  read that answer back. Reading a viewport back to the CPU is a pipeline stall:
  **11 ms** for one full room in the water demo, against **1.6 ms** for the whole
  CPU simulation of the same room.
- without the read back the GPU wins easily (the simulation is one draw per
  sub-step, well under 0.1 ms), which is exactly why the *gas* has a GPU backend:
  nothing on the CPU ever needs to read the gas field back, it is only drawn.
- the CPU water also scales with the wet area rather than the map, sleeps when it
  settles, and its coefficients are tuned so 4 px and 8 px behave the same.

If you need GPU water anyway, the shape is: keep the simulation on the GPU, read
back one summary row per column at a low rate (5-15 Hz) and accept a stale
surface for queries, or move the queries that matter (swimming) into a GPU-driven
path so the CPU never asks.


## Gas: the solver

Per fixed step (`sim_hz`, 10..60):

1. semi-Lagrangian self-advection of the velocity, plus forces: buoyancy of the
   three densities (`gas_buoyancy`, px/s²), vent jets, the interactor push, the
   one-shot blast and the trail emitter;
2. viscosity: velocity diffusion towards the four neighbours (`gas_viscosity`,
   1/s, explicit and clamped to stay stable);
3. **vorticity confinement** (`gas_vorticity`): the trace-back averages the field
   every step, which is what makes a plume smear into a soft blob. The confinement
   force `ε·(N × ω)` pushes each vortex inwards along the gradient of `|curl|`, so
   the small eddies survive. Measured on the light lab over 0.8 s: curl energy
   `0.348 → 0.210` (−40%) with it off, `0.347 → 0.404` (+16%) at 10;
4. divergence of the intermediate velocity (backward difference);
5. pressure Poisson solve: `laplacian(p) = divergence`, `pressure_iterations`
   Jacobi passes, warm started from the previous step;
6. projection: `u = u* - grad(p)` (forward difference, the exact adjoint of the
   divergence, so the discrete divergence is zero);
7. the three densities are advected by the projected velocity, then diffused,
   refilled towards the room ambient, injected by vents/emitters, faded by
   `gas_decay` and thinned around the player.

The gas is a passive scalar set on a divergence-free field: it cannot pile up,
only swirl and fade.

### The detail tracer

The wisp pattern used to be a screen-space noise multiplied over the mist, which is
why the gas read as a texture sliding across the room. It is now the gas's own
detail: the **blue channel of the velocity field** carries a passive scalar that is
traced back with the velocity and stirred where the dye is thick
(`detail_refresh`, `detail_hz`). The mist samples it (`detail_amount`,
`detail_contrast`), so the strokes stretch, curl and dissolve with the gas.

It is deliberately *not* stored in the density field's alpha channel: those passes
render into a transparent `SubViewport`, and the canvas blend premultiplies the
colour by the written alpha, so a buffer written with `alpha = 0.5` comes back with
half the density — and because they ping-pong, that halves the gas every step.
Measured: the field's mean density fell from `0.022` to `0.0004` over 172 steps when
the tracer lived in the alpha channel. The velocity passes write `alpha = 1.0`, so
their blue channel is free.

### Volumetric shading and the stylised threshold

The mist is drawn by one quad with two extra pieces of work per pixel:

* **self-shadowing** (`volume_shadow`, `volume_weight`): the density is marched
  towards the key light (the hero lantern) in six taps, and
  `transmittance = exp(-Σρ·k)` darkens the air that has more gas between it and the
  lamp. The term is gated by the layer's own opacity, so a nearly transparent veil
  (which is optically thin) does not lose brightness — measured on the light lab,
  faint gas changed by −4.6% while a dense puff got 43% darker and gained a depth
  gradient;
* **the stylised threshold** (`stipple_mode`, `stipple_steps`): the opacity is
  quantised into steps, and which step a pixel lands on is decided by a per-pixel
  threshold. The shipped kernel is a 64×64 tiling blue-noise tile
  (`resources/textures/blue_noise_64.png`, baked by
  `scripts/tools/bake_blue_noise.gd`), because an ordered Bayer tile is a *lattice*:
  at the opacity a fading mist passes through, the tile becomes a 2×2 checkerboard
  and every column of the 4× screen turns into a dashed line. Measured on one
  frozen gas state per kernel (`gas_diagnostic.gd --stipple=0,1`): lattice energy
  15.7% → 0.12% on the gas lab and 5.1% → 0.6% on the light lab, vertical runs of
  exactly one design pixel 79.5% → 55.7%, mean opacity −1.1% (gas lab) and
  −0.003% (light lab) — the fade keeps its thickness and loses the grid.
  `stipple_mode` 0 keeps the ordered tile and 2 uses white noise, for A/B captures;
  `--stipple=0,1,2` on the diagnostic tool does exactly that.

### Recorded, not implemented

Two gas *lighting* features are deliberately left out; the plan, the hook points and the
cost arithmetic live in `docs/todo.md` under "渲染：已记录、暂不实现".

* **The gas does not cast a shadow on the world.** The light map is lights plus tile
  occluders, and the gas only ever *reads* it (`set_light_field`). Casting would be one
  more layer inside the light viewport: `light *= exp(-density * k)` (one tap, no
  direction) or the same six-tap march the mist already uses, towards the key light
  (directional). The two caveats are that the mist reads that map for its own `lit`
  (so dense gas would be darkened twice, by its own volume pass and again through the
  map) and that it needs a darkness cap or the room goes muddy.
* **No Tyndall shafts.** The volume march already computes `T = exp(-Σρ)`, which is the
  *absorption* term; `1 - T` along the same ray is exactly the light scattered towards
  the viewer, i.e. the 2D shape of a shaft. It would have to be an **additive** pass
  (the mist's own `COLOR` is multiplied by alpha when it blends, so it cannot add
  light), it needs a direction per light, and it needs to respect the light map's
  shadow term so smoke behind a wall does not glow.

### The simulation domain

`Atmosphere.gas_cell_pixels` is how many world pixels one cell covers (default 4) and
the grid ceiling (`GasSim.MAX_CELLS`, 1024 per axis) is a guard rail, not a resolution
policy: the field's origin is the room origin, which is always a multiple of the world
chunk (320×180) and therefore of the cell, so the field never changes scale or phase
because the camera moved. The gas belongs to the world, not to the view. That is
deliberate — a view-anchored field would make the mist swim when the camera scrolls
and would throw gas away at the edge of the screen.

Every force in the solver is divided by the cell size, so the same tuning describes
the same *physical* behaviour at any resolution. What does not scale on its own, and
has to be re-tuned when `gas_cell_pixels` changes:

| Parameter | How it scales | Why |
| :--- | :--- | :--- |
| `gas_diffusion` | ∝ 1 / cell² | it is a four-neighbour blend per step, so at 1 px it covers 1/16 of the distance it covers at 4 px. Measured with a still brush: the same gesture leaves a puff of 880 / 804 / 724 px² above 0.1 density at 4 / 2 / 1 px cells |
| `pressure_iterations` | ↑ with the cell count | Jacobi propagates information ~√N cells, so a 640-wide field at 16 iterations enforces incompressibility only over a few cells |
| `gas_vorticity` | roughly self-cancelling | the discrete curl grows as 1/cell while the force is applied in cells/s; measure it rather than assume |
| `detail_hz` / `detail_refresh` | unchanged | the tracer is refreshed in *cell* space, so finer cells simply give finer grain (which is the point of going to 1 px) |

Cost, measured on this machine with everything else in the room unchanged
(`gas_diagnostic.gd --cell=N --timing`, min of two runs, uncapped):

| Room | 4 px | 2 px | 1 px |
| :--- | :--- | :--- | :--- |
| one screen (320×180) | 80×45 = 3600 cells | 160×90 = 14400 | 320×180 = 57600 |
| 2×2 chunks (640×360) | 160×90 = 14400 | 320×180 = 57600 | 640×360 = 230400 |
| CPU submit per step (2×2) | 0.09 ms | 0.076 ms | 0.084 ms |
| frame time (2×2, uncapped) | 1.55 ms | 1.79 ms | 1.45 ms |
| HDR buffers (22 × cells × 8 B) | 2.5 MB | 10 MB | 41 MB |

So on this GPU a one-pixel field is *not* the cost problem at this project's room
sizes: 16× the cells changes nothing the frame time can resolve (the noise is ±0.15 ms
and the room's 640×360 light map dominates), and the submit side is flat because it is
20 uniform writes and 20 viewport kicks either way. The costs that do grow are VRAM
(41 MB for a 2×2 room at 1 px) and the re-tuning in the table above.
viewports.

## Gas backends (`Atmosphere.backend`)

The gas field ships both implementations:

| `backend` | What runs | When to use |
| :--- | :--- | :--- |
| `AUTO` (default) | `GasSim` (GPU) when a `RenderingDevice` exists, else `FogGrid` (CPU) | Normal projects. |
| `GPU` | `GasSim`, and if it cannot start it warns once and degrades to `FogGrid` | You want the GPU cost, or you are testing that path. |
| `CPU` | `FogGrid` always, even on a GPU host | Headless servers, the compatibility renderer, or debugging. |

`get_debug_state()` reports `backend` (what is running: `"gpu"`, `"cpu"`,
`"none"`), `requested_backend` and `fallback` (GPU asked for but CPU running).
`set_enabled(false)` parks either backend without tearing it down, so
re-enabling resumes instead of rebuilding.

## Gas parameters (`Atmosphere`)

| Parameter | Default | Meaning |
| :--- | :--- | :--- |
| `sim_hz` | 30 | Steps per second; the master speed knob. |
| `gas_cell_pixels` | 4 | World pixels per simulation cell. 1 resolves the mist to the pixel grid; see *The simulation domain* for what has to be re-tuned with it. |
| `pressure_iterations` | 16 | Jacobi iterations of the pressure solve. |
| `gas_viscosity` | 0.0 | Kinematic viscosity (1/s): thicker gas, calmer plumes. |
| `gas_vorticity` | 10.0 | Vorticity confinement strength: scales the small eddies the trace-back smooths away. 0 = plain dissipative solver. |
| `detail_amount` | 1.0 | How much the advected detail tracer modulates the mist. 0 = smooth field. |
| `detail_refresh` / `detail_hz` | 4.0 / 6.0 | How fast fresh detail is stirred in, and how often its source noise is re-drawn. |
| `stipple_mode` / `stipple_steps` | 1 / 32 | Stylised threshold kernel (0 ordered, 1 blue noise, 2 white noise) and how many opacity steps. |
| `volume_shadow` / `volume_weight` | 0.9 / 0.55 | Depth of the raymarched self-shadow, and how much of it is applied. |
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
| `noise_amount` | 0.45 | Wispy detail strength (it modulates the advected tracer; the CPU fallback uses screen-space noise instead). |
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
godot --headless --path . -s res://tests/run_test_script.gd -- res://tests/world/test_gas_solver.gd
```

All of them also run in `tests/runtime_suite.gd`. Headless has no `RenderingDevice`,
so the gas falls back to the CPU `FogGrid` and the same tests cover that path — which
is also why the GPU solver's own rules are checked structurally (shader data layout,
uniform plumbing, resolution policy) rather than by running the shaders.

### Measuring the gas

`scripts/tools/gas_diagnostic.gd` captures the inputs and the output of the mist for
the same gas state, which is how every number above was obtained:

```powershell
godot --path . --resolution 1280x720 -s res://scripts/tools/gas_diagnostic.gd -- \
  --scene res://scenes/levels/test/gas_lab_runner.tscn --out C:/tmp/gas \
  --settle 4 --frames 3 --interval 0.4 --stipple=0,1,2 --uniform=vorticity=10
```

It writes the raw 80×45 density field, the projected velocity (RG) with the detail
tracer (B), the mist's opacity as its own transparent capture, the window frame with
and without the CRT pass, and `info.txt` with the exported tuning. `--stipple` and
`--uniform` repeat the same gas state under several settings, which is the only fair
way to A/B a kernel: the field itself has to be identical between the captures.

## Performance and limits

- Gas: ~0.06 ms of CPU per step for 20 GPU passes on an 80x45 grid. The whole gas
  layer, including the volumetric pass and the blue-noise sample, costs less than
  the run-to-run noise of a frame: hiding `Atmosphere` on the light lab measures
  1.162 against 1.165 ms/frame uncapped, and on the gas lab (dense plumes) 1.100
  against 1.096. The 120 fps frame budget (8.3 ms) makes it drop ~1% of frames,
  60 fps is flat. Water: a sleeping pool costs nothing; the surface upload is
  capped at 60 Hz.
- Grid water: a 320x180 room with the whole room in motion costs about 0.9 ms per
  60 Hz step at 8 px cells and 1.6 ms at 4 px cells (four times the cells, two
  inner steps, two leveling sweeps). Measured end to end in `water_grid`: p95
  frame 10.7 ms at 4 px against 8.3 ms with no water, both inside a 60 fps budget.
  The passes walk the wet rect only, the leveling pass is inlined, lateral
  transfers only re-visit the cells they wrote, and the texture rebuilds just the
  cells that changed since the last upload, so none of it scales with map size.
- The pressure solve is Jacobi: it removes ~93% of the divergence in open cells
  and leaves a small residual next to walls (no-flux boundary). More
  `pressure_iterations` tightens it; a multigrid V-cycle would be the next step.
- Density is a passive scalar with sources and sinks (ambient, vents, decay,
  player thinning), not a conserved quantity.
- Viscosity is explicit diffusion, clamped for stability; values above ~10 start
  to look like honey at 30 Hz.
- The gas grid is capped at 80x45 per room (4 px cells); water columns are 8 px.
