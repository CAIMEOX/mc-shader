# NilWorld

NilWorld is an Iris shader pack for Minecraft Java Edition 26.2 inspired by
Thurston's Nil geometry and the three-dimensional Heisenberg group. Horizontal
X and Z translations do not commute in the mathematical model: their group
commutator changes the central fiber coordinate by the signed enclosed area.

For every vertex, the shader evaluates the central cross term of
`camera^-1 * world`. Camera coordinates use the smooth bounded gauge
`scale * atan(camera / scale)`: it has the correct first derivative at the
origin while avoiding far-coordinate cliffs. The resulting displacement is
also bounded for render stability. A second area-dependent shear exposes the
same connection locally.
It also uses a stable sinc lift of the Nil geodesic exponential map, so layers
rotate and contract around the vertical fiber as their relative height changes.
The final pass lightly colors opposite holonomy sectors and adds helical fiber
highlights.

The optional diagnostic grid is evaluated in the source Euclidean coordinates
and then carried through the Nil vertex transform. Horizontal block faces use
an XZ cyan grid, X-facing walls use a YZ orange grid, and Z-facing walls use an
XY violet grid; warm major lines repeat after a configurable number of cells.
Only terrain and water receive the grid, while entities, particles, clouds, the
first-person hand, and the HUD remain clean. `GRID_MODE=1` overlays the lines on
the normal material and `GRID_MODE=2` dims the material for geometric study.
Derivative antialiasing keeps the line width stable as the grid recedes.
Unresolvable minor lines fade before they can tint an entire distant surface,
and Iris's split integer/fraction camera coordinates preserve the grid phase
near the world border.

The first-person hand and HUD stay Euclidean. Collision, block coordinates,
redstone, entity simulation, and server-side chunk topology remain unchanged;
this is a visual embedding. The shader has no path memory, so an actual player
loop that returns to the same Minecraft coordinates also returns to the same
rendered state. Frustum and occlusion culling are disabled because the nonlinear
displacement can move nominally hidden chunks into view. Start with a render
distance of 6-10 chunks.

Profiles:

- **Gentle**: broad scale and restrained shear for ordinary play.
- **Nil**: the intended noncommutative fiber-space default.
- **Heisenberg**: tight pitch and strong area holonomy for captures.
- **Grid Diagnostic**: the Nil default with an emphasized 8-block reference grid.

The Heisenberg profile intentionally lets the sinc lift approach its first
horizontal collapse at roughly 100 blocks of relative fiber height. This can
overlap triangles and is intended for experiments rather than routine play.
