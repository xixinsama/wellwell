# Fluid Kit demos

Each demo is a runnable scene: open it in the editor and press **F6**, or run it
from the command line with `godot --path . res://examples/fluid_demos/<name>.tscn`.

| Scene | Shows |
| :--- | :--- |
| `water_demo.tscn` | The three-pool cascade: a high pool on the left spills into a middle pool, which spills into a low pool on the right (two falling water columns), plus the hero floating and swimming and entry splashes that scale with impact speed. Gas is disabled so only water shows. |
| `gas_plumes_demo.tscn` | Three wall vents, one per gas density (heavy sinks, neutral drifts, light rises) and three platform rows to stand on. The hero pushes the plumes around. |
| `gas_effects_demo.tscn` | Cycles three scenarios on the gas lab: vents blasting at 4x rate / 3x jet speed, a point explosion, and a 1x4-cell pillar sweeping through the plumes. |
| `gas_trail_demo.tscn` | An empty room (no ambient gas): a 1x1-cell walker loops a square path and leaves a backward-moving trail that fades out (`GasField.decay`). |

The demos instance the template's test-world runners, because they need the
template's tiles, player and camera. The fluid runtime itself has no dependency on
the template: see `../README.md` for the integration guide.
