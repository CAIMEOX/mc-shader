# SphericalWorld

SphericalWorld is an Iris shader pack for Minecraft Java Edition 26.2. It wraps
the camera-relative horizontal plane onto the inside of a sphere. A geodesic
distance of pi times the selected radius reaches the antipode overhead; two pi
times the radius closes the great-circle path back at the camera. Vertical
geometry can follow the rotating inward sphere normal, so distant towers point
toward the sphere's center and eventually hang from the ceiling.

This is a visual embedding. Collision, block coordinates, redstone, entities,
and server-side chunk topology remain Euclidean, and unrendered chunks cannot
appear through the shader. Frustum and occlusion culling are disabled to keep
wrapped visible chunks from disappearing; start at 6-10 chunks render distance.

Profiles:

- **Gentle**: a broad sphere and partial vertical following.
- **Spherical**: the intended inner-shell world.
- **Closed**: a small radius that places the antipode inside normal view range.
