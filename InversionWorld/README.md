# InversionWorld

An Iris shader pack for Minecraft Java Edition 26.2. It applies a localized,
camera-anchored inversion around a configurable sphere: points inside the sphere
appear beyond it, while the sphere itself stays fixed. A smooth transition shell
then restores ordinary Euclidean space instead of compacting the entire world
into the sphere.

The map is visual only. Collision, block coordinates, entities, and chunk
loading remain ordinary Minecraft. The camera receives the same deformation as
the scene, so the player remains at the visual origin and distant loaded terrain
does not turn into an empty exterior. A core radius and maximum scale make the
mathematical singularity finite; clouds, sky, and first-person hands remain
Euclidean as stable visual references. **Effect reach** controls where the
transition finishes, as a multiple of the sphere radius.

Use **Subtle** for a large, gentle inversion sphere, **Inversion** for the
default effect, and **Inside Out** for the strongest protected distortion.
Because transformed geometry can return from outside vanilla's view, the pack
disables frustum and occlusion culling. Start with a 6-10 chunk render distance.
