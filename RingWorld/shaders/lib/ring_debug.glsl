#ifndef RING_DEBUG_GLSL
#define RING_DEBUG_GLSL

const float RING_DEBUG_PI = 3.14159265359;

vec2 ringDebugPlaneCoordinates(vec3 position, vec3 normal) {
    vec3 normalWeight = abs(normal);
    if (normalWeight.y >= normalWeight.x
        && normalWeight.y >= normalWeight.z) {
        return position.xz;
    }
    if (normalWeight.x >= normalWeight.z) {
        return position.yz;
    }
    return position.xy;
}

float ringDebugLineMask(float coordinate, float spacing, float thickness) {
    float scaledCoordinate = coordinate / max(spacing, 0.001);
    float cellDistance = abs(fract(scaledCoordinate - 0.5) - 0.5);
    float pixelFootprint = max(fwidth(scaledCoordinate), 0.0001);
    float filterWidth = pixelFootprint * max(thickness, 0.25);
    float lineCoverage = 1.0 - smoothstep(
        filterWidth * 0.25,
        filterWidth,
        cellDistance
    );
    float resolutionFade = 1.0 - smoothstep(0.35, 0.75, pixelFootprint);
    return lineCoverage * resolutionFade;
}

float ringDebugGridMask(vec2 coordinates, float spacing, float thickness) {
    return max(
        ringDebugLineMask(coordinates.x, spacing, thickness),
        ringDebugLineMask(coordinates.y, spacing, thickness)
    );
}

vec2 ringDebugCylinderCoordinates(vec3 localPosition) {
#if CURVE_AXIS == 0
    return vec2(localPosition.x, localPosition.z);
#else
    return vec2(localPosition.z, localPosition.x);
#endif
}

vec3 applyRingDiagnostic(
    vec3 sceneColor,
    vec3 sourcePosition,
    vec3 localPosition,
    vec3 sourceNormal
) {
#if RING_DEBUG_MODE == 0
    return sceneColor;
#else
    float opacity = clamp(DEBUG_OPACITY, 0.0, 1.0);
    vec3 result = sceneColor;
    vec2 planeCoordinates = ringDebugPlaneCoordinates(
        sourcePosition,
        sourceNormal
    );

#if RING_DEBUG_MODE == 1 || RING_DEBUG_MODE == 4
    float gridMask = ringDebugGridMask(
        planeCoordinates,
        DEBUG_GRID_SPACING,
        DEBUG_LINE_WIDTH
    );
    vec3 gridColor = vec3(0.14, 0.84, 1.00);
    result = mix(result, gridColor, gridMask * opacity * 0.72);
#endif

#if RING_DEBUG_MODE == 2 || RING_DEBUG_MODE == 4
    float chunkMask = ringDebugGridMask(
        planeCoordinates,
        16.0,
        DEBUG_LINE_WIDTH * 1.75
    );
    vec2 chunkCell = floor(planeCoordinates / 16.0);
    float chunkParity = mod(chunkCell.x + chunkCell.y, 2.0);
    vec3 chunkTint = mix(
        vec3(0.16, 0.08, 0.22),
        vec3(0.06, 0.16, 0.20),
        chunkParity
    );
    result = mix(result, result * 0.72 + chunkTint * 0.28, opacity * 0.16);
    result = mix(result, vec3(1.00, 0.43, 0.13), chunkMask * opacity);
#endif

#if RING_DEBUG_MODE == 3 || RING_DEBUG_MODE == 4
    vec2 cylinderCoordinates = ringDebugCylinderCoordinates(localPosition);
    float safeCurvature = max(CURVATURE, 0.000001);
    float circumference = 2.0 * RING_DEBUG_PI / safeCurvature;
    float helixSlope = DEBUG_HELIX_PITCH / circumference;
    float axialMask = ringDebugLineMask(
        cylinderCoordinates.x,
        DEBUG_GEODESIC_SPACING,
        DEBUG_LINE_WIDTH
    );
    float ringMask = ringDebugLineMask(
        cylinderCoordinates.y,
        DEBUG_GEODESIC_SPACING,
        DEBUG_LINE_WIDTH
    );
    float positiveHelixMask = ringDebugLineMask(
        cylinderCoordinates.y - helixSlope * cylinderCoordinates.x,
        DEBUG_GEODESIC_SPACING,
        DEBUG_LINE_WIDTH * 0.85
    );
    float negativeHelixMask = ringDebugLineMask(
        cylinderCoordinates.y + helixSlope * cylinderCoordinates.x,
        DEBUG_GEODESIC_SPACING,
        DEBUG_LINE_WIDTH * 0.85
    );
    float horizontalSurface = smoothstep(0.45, 0.82, abs(sourceNormal.y));
    result = mix(
        result,
        vec3(0.18, 1.00, 0.58),
        axialMask * horizontalSurface * opacity
    );
    result = mix(
        result,
        vec3(0.68, 0.32, 1.00),
        ringMask * horizontalSurface * opacity
    );
    result = mix(
        result,
        vec3(1.00, 0.76, 0.18),
        positiveHelixMask * horizontalSurface * opacity * 0.88
    );
    result = mix(
        result,
        vec3(1.00, 0.24, 0.52),
        negativeHelixMask * horizontalSurface * opacity * 0.88
    );
#endif

#if RING_DEBUG_MODE == 4
    float layerAmount = smoothstep(
        0.0,
        24.0,
        abs(localPosition.y)
    ) * clamp(DEBUG_LAYER_TINT, 0.0, 1.0);
    vec3 layerColor = localPosition.y < 0.0
        ? vec3(1.00, 0.18, 0.12)
        : vec3(0.16, 0.72, 1.00);
    result = mix(result, result * (0.74 + layerColor * 0.36), layerAmount);
#endif

    return result;
#endif
}

#endif
