# HyperbolicWorld

HyperbolicWorld is an Iris shader pack for Minecraft Java Edition 26.2. It
places camera-relative X/Z coordinates in an upper-half-plane chart, applies a
Cayley/Mobius transform into a finite Poincare disk, and compresses vertical
geometry toward the disk's ideal boundary. Nearby blocks retain an almost
Euclidean scale while distant lines curve and accumulate exponentially.

This is a visual embedding, not a new game topology. Collision, block
coordinates, redstone, entities, and server-side chunk loading remain
Euclidean. The pack disables Iris frustum and occlusion culling so transformed
chunks do not vanish unexpectedly; this costs performance, so a render distance
of 6-10 chunks is recommended before increasing it.

Profiles:

- **Gentle** keeps building and movement comfortable.
- **Hyperbolic** is the intended default balance.
- **Escher** uses a small curvature radius and a rotated chart for a much more
  disorienting non-Euclidean appearance.
