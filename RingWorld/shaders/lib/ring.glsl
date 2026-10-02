#ifndef RING_TRANSFORM_GLSL
#define RING_TRANSFORM_GLSL

const float RING_PI = 3.14159265359;

float ringSplitPhase(
    int cameraInteger,
    float cameraFraction,
    float circumference
) {
    const int phaseChunk = 4096;
    int quotient = cameraInteger / phaseChunk;
    int remainder = cameraInteger - quotient * phaseChunk;
    float coarsePeriod = circumference / float(phaseChunk);
    float coarsePhase = mod(float(quotient), coarsePeriod);
    return mod(
        coarsePhase * float(phaseChunk)
            + float(remainder)
            + cameraFraction,
        circumference
    );
}

vec2 ringCameraPhase(ivec3 cameraInteger, vec3 cameraFraction) {
    float safeCurvature = max(CURVATURE, 0.000001);
    float circumference = 2.0 * RING_PI / safeCurvature;
    return vec2(
        ringSplitPhase(cameraInteger.x, cameraFraction.x, circumference),
        ringSplitPhase(cameraInteger.z, cameraFraction.z, circumference)
    );
}

float ringHeightFollow(float relativeHeight) {
    float follow = clamp(HEIGHT_FOLLOW, 0.0, 1.0);
#if BURIAL_GUARD == 1
    follow = 1.0;
#endif
    return follow;
}

float ringWarpStrength() {
#if BURIAL_GUARD == 1
    return 1.0;
#else
    return clamp(WARP_STRENGTH, 0.0, 1.0);
#endif
}

vec2 ringRadiusState(float radius, float height, float heightFollow) {
    float scaledHeight = height * heightFollow;
    if (scaledHeight < 0.0) {
        return vec2(radius - scaledHeight, -heightFollow);
    }
    float denominator = 0.9 * radius + scaledHeight;
    float numerator = 0.81 * radius * radius;
    float pointRadius = 0.1 * radius + numerator / denominator;
    float derivative = -numerator * heightFollow
        / (denominator * denominator);
    return vec2(pointRadius, derivative);
}

vec3 ringPosition(vec3 relativeWorldPosition, vec2 cameraPhase) {
    if (CURVATURE <= 0.000001) {
        return relativeWorldPosition;
    }

    float safeCurvature = max(CURVATURE, 0.000001);
    float radius = 1.0 / safeCurvature;
    float heightFollow = ringHeightFollow(relativeWorldPosition.y);
    float pointRadius = ringRadiusState(
        radius,
        relativeWorldPosition.y,
        heightFollow
    ).x;
    float residualHeight = relativeWorldPosition.y * (1.0 - heightFollow);

#if CURVE_AXIS == 0
#if ROLL_WITH_PLAYER == 1
    float pointAngle = relativeWorldPosition.x / radius;
    float cameraAngle = 0.0;
#else
    float pointAngle = (cameraPhase.x + relativeWorldPosition.x) / radius;
    float cameraAngle = cameraPhase.x / radius;
#endif
    vec3 mappedPosition = vec3(
        pointRadius * sin(pointAngle) - radius * sin(cameraAngle),
        radius * cos(cameraAngle) - pointRadius * cos(pointAngle)
            + residualHeight,
        relativeWorldPosition.z
    );
#else
#if ROLL_WITH_PLAYER == 1
    float pointAngle = relativeWorldPosition.z / radius;
    float cameraAngle = 0.0;
#else
    float pointAngle = (cameraPhase.y + relativeWorldPosition.z) / radius;
    float cameraAngle = cameraPhase.y / radius;
#endif
    vec3 mappedPosition = vec3(
        relativeWorldPosition.x,
        radius * cos(cameraAngle) - pointRadius * cos(pointAngle)
            + residualHeight,
        pointRadius * sin(pointAngle) - radius * sin(cameraAngle)
    );
#endif

    return mix(
        relativeWorldPosition,
        mappedPosition,
        ringWarpStrength()
    );
}

vec3 ringMappedNormal(
    vec3 relativeWorldPosition,
    vec3 sourceNormal,
    vec2 cameraPhase
) {
    if (CURVATURE <= 0.000001) {
        return sourceNormal;
    }

    float safeCurvature = max(CURVATURE, 0.000001);
    float radius = 1.0 / safeCurvature;
    float heightFollow = ringHeightFollow(relativeWorldPosition.y);
    float strength = ringWarpStrength();
    vec2 radiusState = ringRadiusState(
        radius,
        relativeWorldPosition.y,
        heightFollow
    );
    float pointRadius = radiusState.x;
    float radialDerivative = radiusState.y;

#if CURVE_AXIS == 0
#if ROLL_WITH_PLAYER == 1
    float angle = relativeWorldPosition.x / radius;
#else
    float angle = (cameraPhase.x + relativeWorldPosition.x) / radius;
#endif
    vec3 tangentX = vec3(
        pointRadius * cos(angle) / radius,
        pointRadius * sin(angle) / radius,
        0.0
    );
    vec3 tangentY = vec3(
        radialDerivative * sin(angle),
        -radialDerivative * cos(angle) + (1.0 - heightFollow),
        0.0
    );
    vec3 tangentZ = vec3(0.0, 0.0, 1.0);
#else
#if ROLL_WITH_PLAYER == 1
    float angle = relativeWorldPosition.z / radius;
#else
    float angle = (cameraPhase.y + relativeWorldPosition.z) / radius;
#endif
    vec3 tangentX = vec3(1.0, 0.0, 0.0);
    vec3 tangentY = vec3(
        0.0,
        -radialDerivative * cos(angle) + (1.0 - heightFollow),
        radialDerivative * sin(angle)
    );
    vec3 tangentZ = vec3(
        0.0,
        pointRadius * sin(angle) / radius,
        pointRadius * cos(angle) / radius
    );
#endif

    tangentX = mix(vec3(1.0, 0.0, 0.0), tangentX, strength);
    tangentY = mix(vec3(0.0, 1.0, 0.0), tangentY, strength);
    tangentZ = mix(vec3(0.0, 0.0, 1.0), tangentZ, strength);
    vec3 cofactorX = cross(tangentY, tangentZ);
    vec3 cofactorY = cross(tangentZ, tangentX);
    vec3 cofactorZ = cross(tangentX, tangentY);
    vec3 mappedNormal =
        sourceNormal.x * cofactorX
        + sourceNormal.y * cofactorY
        + sourceNormal.z * cofactorZ;
    float normalLength = length(mappedNormal);
    if (normalLength < 0.00001) {
        return sourceNormal;
    }
    return mappedNormal / normalLength;
}

vec3 ringSkyAxis() {
#if CURVE_AXIS == 0
    return vec3(0.0, 0.0, 1.0);
#else
    return vec3(1.0, 0.0, 0.0);
#endif
}

vec3 applyRingSky(vec3 baseColor, vec3 worldRay) {
    if (CURVATURE <= 0.000001) {
        return baseColor;
    }
    vec3 ray = normalize(worldRay);
    float axisDot = abs(dot(ray, ringSkyAxis()));
    float angularDistance = acos(clamp(axisDot, 0.0, 1.0));
    float circleRadius = clamp(SKY_CIRCLE_RADIUS, 0.10, 1.40);
    float cap = 1.0 - smoothstep(
        max(circleRadius - 0.07, 0.0),
        circleRadius + 0.07,
        angularDistance
    );
    float rim = smoothstep(
        max(circleRadius - 0.055, 0.0),
        circleRadius,
        angularDistance
    ) * (1.0 - smoothstep(circleRadius, circleRadius + 0.055, angularDistance));

    float skyHeight = clamp(0.5 + 0.5 * ray.y, 0.0, 1.0);
    vec3 skyBottom = vec3(0.025, 0.045, 0.11);
    vec3 skyTop = vec3(0.19, 0.42, 0.78);
    vec3 circularSky = mix(skyBottom, skyTop, skyHeight);
    float opacity = clamp(SKY_CIRCLE_OPACITY, 0.0, 1.0);
    vec3 result = mix(baseColor, circularSky, cap * opacity);
    result += vec3(0.55, 0.78, 1.00) * rim * clamp(SKY_RIM, 0.0, 1.0);
    return result;
}

#endif
