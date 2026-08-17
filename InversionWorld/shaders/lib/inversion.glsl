#ifndef INVERSION_TRANSFORM_GLSL
#define INVERSION_TRANSFORM_GLSL

vec3 inversionCenterRelative(vec3 cameraAbsolute) {
    return vec3(INVERSION_X, INVERSION_Y, INVERSION_Z) - cameraAbsolute;
}

float inversionInfluence(vec3 delta) {
    float distanceFromCenter = length(delta);
    float outerRadius = INVERSION_RADIUS * max(INVERSION_REACH, 1.01);
    return 1.0 - smoothstep(INVERSION_RADIUS, outerRadius, distanceFromCenter);
}

vec3 inversionDisplacement(vec3 absolutePosition) {
    vec3 centerAbsolute = vec3(INVERSION_X, INVERSION_Y, INVERSION_Z);
    vec3 delta = absolutePosition - centerAbsolute;
    float coreRadiusSquared = INVERSION_CORE_RADIUS * INVERSION_CORE_RADIUS;
    float safeDistanceSquared = max(dot(delta, delta), coreRadiusSquared);
    float rawScale = (INVERSION_RADIUS * INVERSION_RADIUS) / safeDistanceSquared;
    float boundedScale = min(rawScale, MAX_INVERSION_SCALE);
    vec3 invertedAbsolute = centerAbsolute + delta * boundedScale;
    return (invertedAbsolute - absolutePosition) * inversionInfluence(delta);
}

vec3 inversionPosition(vec3 relativeWorldPosition, vec3 cameraAbsolute) {
    vec3 absoluteWorldPosition = cameraAbsolute + relativeWorldPosition;
    vec3 pointDisplacement = inversionDisplacement(absoluteWorldPosition);
    vec3 cameraDisplacement = inversionDisplacement(cameraAbsolute);
    return relativeWorldPosition
        + (pointDisplacement - cameraDisplacement)
        * clamp(INVERSION_BLEND, 0.0, 1.0);
}

#endif
