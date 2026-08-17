#ifndef SPHERICAL_TRANSFORM_GLSL
#define SPHERICAL_TRANSFORM_GLSL

vec3 sphericalGroundPosition(vec2 horizontalPosition) {
    float safeRadius = max(SPHERE_RADIUS, 1.0);
    float horizontalDistance = length(horizontalPosition);
    vec2 direction = horizontalPosition / max(horizontalDistance, 0.00001);
    float arcAngle = horizontalDistance / safeRadius;
    float horizontalRadius = safeRadius * sin(arcAngle);
    return vec3(
        direction.x * horizontalRadius,
        safeRadius * (1.0 - cos(arcAngle)),
        direction.y * horizontalRadius
    );
}

vec3 sphericalVerticalDirection(vec2 horizontalPosition, float height) {
    float safeRadius = max(SPHERE_RADIUS, 1.0);
    float horizontalDistance = length(horizontalPosition);
    vec2 direction = horizontalPosition / max(horizontalDistance, 0.00001);
    float arcAngle = horizontalDistance / safeRadius;
    return vec3(
        -direction.x * sin(arcAngle) * height,
        cos(arcAngle) * height,
        -direction.y * sin(arcAngle) * height
    );
}

vec3 sphericalPosition(vec3 relativeWorldPosition) {
    vec3 groundPosition = sphericalGroundPosition(relativeWorldPosition.xz);
    vec3 euclideanVertical = vec3(0.0, relativeWorldPosition.y, 0.0);
    vec3 sphericalVertical = sphericalVerticalDirection(
        relativeWorldPosition.xz,
        relativeWorldPosition.y
    );
    vec3 mappedPosition = groundPosition + mix(
        euclideanVertical,
        sphericalVertical,
        clamp(VERTICAL_FOLLOW, 0.0, 1.0)
    );
    return mix(
        relativeWorldPosition,
        mappedPosition,
        clamp(WARP_STRENGTH, 0.0, 1.0)
    );
}

#endif
