# SolWorld

SolWorld is an Iris shader pack for Minecraft Java Edition 26.2 inspired by
Thurston's Sol geometry. Relative height applies reciprocal exponential scales
to two horizontal principal axes: one expands exactly as the other contracts.
A bounded saddle term approximates the opposite bending of long geodesics, so
even flat terrain develops a woven, direction-dependent shape.

The first-person hand and HUD stay Euclidean. Collision, block coordinates,
redstone, entity simulation, and server-side chunk topology also remain
unchanged; this pack is a visual embedding. Iris frustum and occlusion culling
are disabled because nonlinear vertex displacement can bring nominally hidden
chunks back into the view. Start with a render distance of 6-10 chunks.

Profiles:

- **Gentle**: broad scale and restrained bending for ordinary play.
- **Sol**: the intended anisotropic default.
- **Impossible**: strong exponential stretch and saddle curvature for captures.
