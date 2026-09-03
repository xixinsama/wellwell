# Extension Guide

`wellwell` is meant to branch easily. Add mechanics by composing around the player controller instead of expanding it into a large game-specific coordinator.

## Recommended Boundaries

- Keep player movement in `scripts/player/player_controller.gd`.
- Put world triggers in `scripts/world/`.
- Put debug-only tools in `scripts/tools/`.
- Use Resource files for tuning values.
- Keep visual feedback free to scale, flash, or animate, but do not move `SpriteRoot.position` away from `Vector2.ZERO`.

## SubViewport Safety Border

The game uses a 322x182 `SubViewport` while treating 320x180 as the safe design frame. The extra 1 pixel on each side prevents edge artifacts during camera smoothing and small screen shakes.

The integer scale is calculated from the 320x180 safe frame, not the larger 322x182 viewport. At 1280x720 this gives 4x scale, so the displayed viewport is 1288x728 and is centered at `(-4, -4)`. The outer window clips the hidden safety border.

If you change the viewport size, preserve the same idea:

- Decide the safe gameplay size first.
- Add a small hidden border.
- Integer-scale the larger viewport.
- Round the final camera position to source pixels.

## Adding Mechanics

Good first extensions:

- Checkpoints.
- Moving platforms.
- Ladders.
- Simple hazards.
- Room transition tests.
- Dash as a separate component.

Avoid adding save systems, combat frameworks, or metroidvania progression until the base movement and camera feel are stable.
