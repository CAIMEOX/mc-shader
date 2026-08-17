#ifndef HYPERBOLIC_TRANSFORM_GLSL
#define HYPERBOLIC_TRANSFORM_GLSL

const float HYPERBOLIC_PI = 3.14159265359;

vec2 rotateChart(vec2 value, float degrees) {
    float angle = degrees * HYPERBOLIC_PI / 180.0;
    float cosine = cos(angle);
    float sine = sin(angle);
    return vec2(
        cosine * value.x - sine * value.y,
        sine * value.x + cosine * value.y
    );
}

// Cayley transform (z-i)/(z+i), mapping the upper half-plane to the open
// Poincare disk. x/y store the real/imaginary components of z.
vec2 upperHalfPlaneToDisk(vec2 halfPlane) {
    float x = halfPlane.x;
    float y = halfPlane.y;
    float denominator = x * x + (y + 1.0) * (y + 1.0);
    return vec2(
        (x * x + y * y - 1.0) / denominator,
        -2.0 * x / denominator
    );
}

vec3 hyperbolicPosition(vec3 relativeWorldPosition) {
    float safeRadius = max(CURVATURE_RADIUS, 1.0);
    vec2 chartPosition = rotateChart(relativeWorldPosition.xz, CHART_ROTATION);
    vec2 halfPlane = vec2(
        chartPosition.x / safeRadius,
        exp(clamp(chartPosition.y / safeRadius, -12.0, 12.0))
    );
    vec2 disk = upperHalfPlaneToDisk(halfPlane);
    float diskRadiusSquared = min(dot(disk, disk), 0.9999);

    // Near the camera this has derivative one; every finite point remains
    // inside the ideal boundary at 2R.
    vec2 mappedChart = vec2(-disk.y, disk.x)
        * (2.0 * CURVATURE_RADIUS);
    vec2 mappedWorld = rotateChart(mappedChart, -CHART_ROTATION);
    vec2 warpedXZ = mix(
        relativeWorldPosition.xz,
        mappedWorld,
        clamp(WARP_STRENGTH, 0.0, 1.0)
    );

    // In the Poincare model equal hyperbolic objects occupy progressively
    // smaller Euclidean height near the boundary.
    float boundaryScale = max(0.04, 1.0 - diskRadiusSquared);
    float verticalScale = mix(
        1.0,
        boundaryScale,
        clamp(VERTICAL_COMPRESSION * WARP_STRENGTH, 0.0, 1.0)
    );
    return vec3(warpedXZ.x, relativeWorldPosition.y * verticalScale, warpedXZ.y);
}

#endif
