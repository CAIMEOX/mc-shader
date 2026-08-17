#ifndef NIL_GRID_GLSL
#define NIL_GRID_GLSL

vec2 nilGridPlaneCoordinates(vec3 position, vec3 normal) {
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

vec3 nilGridPlaneColor(vec3 normal) {
    vec3 normalWeight = abs(normal);
    if (normalWeight.y >= normalWeight.x
        && normalWeight.y >= normalWeight.z) {
        return vec3(0.12, 0.82, 1.00);
    }
    if (normalWeight.x >= normalWeight.z) {
        return vec3(1.00, 0.32, 0.18);
    }
    return vec3(0.72, 0.26, 1.00);
}

float nilGridAxisMask(vec2 coordinates, float spacing, float thickness) {
    vec2 scaledCoordinates = coordinates / max(spacing, 0.001);
    vec2 cellDistance = abs(
        fract(scaledCoordinates - 0.5) - 0.5
    );
    vec2 pixelFootprint = max(fwidth(scaledCoordinates), vec2(0.0001));
    vec2 filterWidth = pixelFootprint * max(thickness, 0.25);
    vec2 axisMask = vec2(1.0) - smoothstep(
        filterWidth * 0.25,
        filterWidth,
        cellDistance
    );
    // Once a pixel spans most of a cell, filtering cannot resolve the lines.
    // Fade that grid level instead of letting its enlarged filter fill the face.
    vec2 resolutionFade = vec2(1.0) - smoothstep(
        vec2(0.35),
        vec2(0.75),
        pixelFootprint
    );
    axisMask *= resolutionFade;
    return max(axisMask.x, axisMask.y);
}

vec3 applyNilGrid(
    vec3 sceneColor,
    vec3 sourcePosition,
    vec3 sourceNormal
) {
#if GRID_MODE == 0
    return sceneColor;
#else
    vec2 planeCoordinates = nilGridPlaneCoordinates(
        sourcePosition,
        sourceNormal
    );
    float minorMask = nilGridAxisMask(
        planeCoordinates,
        GRID_SPACING,
        GRID_THICKNESS
    );
    float majorMask = nilGridAxisMask(
        planeCoordinates,
        GRID_SPACING * GRID_MAJOR_EVERY,
        GRID_THICKNESS * 1.65
    );
    float lineMask = max(minorMask * 0.62, majorMask);
    vec3 planeColor = nilGridPlaneColor(sourceNormal);
    vec3 majorColor = vec3(1.00, 0.96, 0.72);
    vec3 lineColor = mix(planeColor, majorColor, majorMask);
    float opacity = clamp(GRID_OPACITY, 0.0, 1.0);

#if GRID_MODE == 2
    float luminance = dot(sceneColor, vec3(0.2126, 0.7152, 0.0722));
    vec3 diagnosticBase = mix(
        sceneColor * 0.42,
        vec3(luminance) * 0.28,
        0.55
    );
    return mix(diagnosticBase, lineColor, lineMask * opacity);
#else
    return mix(sceneColor, lineColor, lineMask * opacity);
#endif
#endif
}

#endif
