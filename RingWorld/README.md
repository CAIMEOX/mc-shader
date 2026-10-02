# RingWorld

RingWorld bends one horizontal Minecraft direction around a configurable
cylinder. Set `CURVE_AXIS=0` to wrap X and leave Z as the cylinder axis, or set
`CURVE_AXIS=1` to wrap Z and leave X as the axis. The bend uses
`radius = 1 / CURVATURE`, so zero curvature is the flat Euclidean view.

The default uses a complete concentric cylinder: Minecraft height becomes the
radial direction, so higher layers stay inward and lower layers stay outward.
`HEIGHT_FOLLOW` and `WARP_STRENGTH` are experimental Hybrid-mode controls;
strict burial protection overrides both to one. `ROLL_WITH_PLAYER` is enabled
by default: the cylinder's
tangent frame rolls with the player so the local ground does not rotate out of
view while crossing an absolute phase boundary. Disable it only to inspect the
fixed global-cylinder embedding. Surface normals use the same local Jacobian
approximation, so lighting follows the bend. The Hybrid profile can keep part
of the height aligned with Minecraft's global Y axis for playability.

`BURIAL_GUARD` is enabled by default. Because a terrain shader cannot reliably
tell buildings, ground, and cave walls apart, strict protection puts every
height layer on a concentric radius and uses the complete cylindrical map.
Surface layers then stay inward and cave layers stay outward for the full
circle. The **Hybrid** profile restores upright heights and partial warp for
experiments, but it can expose caves on the upper arc.

When the camera looks down the unwrapped cylinder axis, the final pass draws a
colored circular sky cap with an adjustable radius and rim. The vanilla sun and
moon are hidden so the cap remains legible; stars and the ordinary sky provide
the background outside it.

Diagnostics are carried in source coordinates through the same cylinder
transform and are limited to terrain and water:

- **Grid**: cyan block-space grid on each dominant source plane.
- **Chunks**: orange 16-block chunk-section boundaries with alternating cells.
- **Geodesics**: green axial lines, violet circumference rings, and yellow/pink
  helical families. In the unwrapped cylinder plane all four families are
  straight; the diagonal families become helices after wrapping.
- **All**: combines the above and tints below-camera layers warm and
  above-camera layers cool for burial-order debugging.

`DEBUG_HELIX_PITCH` is the axis distance advanced over one complete cylinder
circumference. Normal profiles explicitly restore `RING_DEBUG_MODE=0`, so a
diagnostic overlay cannot stick after profile switching. Diagnostic profiles
change only overlay options; the current X/Z axis, curvature, burial mode, sky,
and fog are preserved so enabling diagnostics does not change the bug being
observed. Geodesic families are centered on the player's rolling local frame,
so they act as a local geodesic compass and slide over world blocks as the
player moves.

Profiles:

- **Flat**: Euclidean baseline with the circular cap disabled.
- **Ring X**: X wraps, so Z is the cylinder axis and the circular sky is seen along Z.
- **Ring Z**: Z wraps, so X is the cylinder axis and the circular sky is seen along X.
- **Tube**: height follows the cross-section fully, producing a more tubular ring.
- **Tight**: stronger curvature for screenshots and experiments.
- **Hybrid**: upright-height experiment; cave layers may become visible on the upper arc.
- **Debug Grid / Chunks / Geodesics / All**: focused diagnostic presets.

The first-person hand stays Euclidean. Collision, block coordinates, redstone,
entity simulation, and server-side chunk topology remain unchanged; this is a
visual embedding. Frustum and occlusion culling are disabled because the
nonlinear displacement can move nominally hidden chunks into view.
