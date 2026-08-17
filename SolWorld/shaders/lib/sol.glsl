#ifndef SOL_TRANSFORM_GLSL
#define SOL_TRANSFORM_GLSL

const float SOL_PI = 3.14159265359;

vec2 rotateSolAxes(vec2 value, float degrees) {
    float angle = degrees * SOL_PI / 180.0;
    float cosine = cos(angle);
    float sine = sin(angle);
    return vec2(
        cosine * value.x - sine * value.y,
        sine * value.x + cosine * value.y
    );
}

vec2 solHorizontalScales(float relativeHeight) {
    float safeScale = max(SOL_SCALE, 1.0);
    float stretchExponent = clamp(
        relativeHeight * ANISOTROPY / safeScale,
        -4.0,
        4.0
    );
    // Reciprocal factors preserve horizontal area while changing its shape.
    return vec2(exp(stretchExponent), exp(-stretchExponent));
}

vec3 solPosition(vec3 relativeWorldPosition) {
    float safeScale = max(SOL_SCALE, 1.0);
    vec2 axisPosition = rotateSolAxes(
        relativeWorldPosition.xz,
        AXIS_ROTATION
    );
    vec2 horizontalScales = solHorizontalScales(relativeWorldPosition.y);
    vec2 mappedAxes = axisPosition * horizontalScales;

    float horizontalDistance = length(axisPosition);
    float saddleHeight = (
        axisPosition.x * axisPosition.x
        - axisPosition.y * axisPosition.y
    ) / (safeScale + horizontalDistance) * GEODESIC_BEND * 0.35;

    vec2 mappedXZ = rotateSolAxes(mappedAxes, -AXIS_ROTATION);
    vec3 mappedPosition = vec3(
        mappedXZ.x,
        relativeWorldPosition.y + saddleHeight,
        mappedXZ.y
    );
    return mix(
        relativeWorldPosition,
        mappedPosition,
        clamp(WARP_STRENGTH, 0.0, 1.0)
    );
}

#endif
