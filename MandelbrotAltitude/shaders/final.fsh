#version 120

// User-facing shader options. Iris discovers the values in square brackets.
#define START_ALTITUDE 64.0 // [0.0 32.0 64.0 96.0 128.0] Height where zoom x1 begins
#define BLOCKS_PER_DOUBLING 24.0 // [8.0 12.0 16.0 24.0 32.0 48.0 64.0] Vertical blocks per 2x zoom
#define VOID_TWIST_PERIOD 384.0 // [128.0 192.0 256.0 384.0 512.0 768.0 1024.0] Downward blocks per spiral turn
#define PAN_PERIOD 2000.0 // [500.0 1000.0 1500.0 2000.0 3000.0 5000.0 10000.0] Blocks per horizontal navigation cycle
#define PAN_RANGE 0.65 // [0.00 0.25 0.40 0.55 0.65 0.80 1.00] Maximum sky-plane displacement
#define MAX_ITERATIONS 128 // [64 96 128 160 192 256] Fractal detail and GPU cost
#define MAX_ZOOM_STEPS 96 // [17 24 40 60 80 96] Maximum binary zoom exponent
#define FRACTAL_OPACITY 0.90 // [0.50 0.65 0.75 0.85 0.90 0.95 1.00] Blend over vanilla sky

varying vec2 texcoord;

uniform sampler2D colortex0;
uniform sampler2D depthtex0;

uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;

uniform float eyeAltitude;
uniform ivec3 cameraPositionInt;
uniform vec3 cameraPositionFract;
uniform bool hasSkylight;
uniform bool hasCeiling;
uniform int isEyeInWater;

const float TAU = 6.28318530718;
const vec2 DEEP_ZOOM_CENTER = vec2(
    -0.743643887037158704752191506114774,
    0.131825904205311970493132056385139
);

vec3 palette(float t) {
    vec3 base = vec3(0.42, 0.36, 0.48);
    vec3 amplitude = vec3(0.48, 0.42, 0.52);
    vec3 frequency = vec3(1.00, 1.08, 0.86);
    vec3 phase = vec3(0.02, 0.20, 0.38);
    return base + amplitude * cos(TAU * (frequency * t + phase));
}

bool insideMainBodies(vec2 c) {
    float x = c.x;
    float y2 = c.y * c.y;
    float q = (x - 0.25) * (x - 0.25) + y2;
    bool inCardioid = q * (q + x - 0.25) <= 0.25 * y2;
    bool inPeriodTwoBulb = (x + 1.0) * (x + 1.0) + y2 <= 0.0625;
    return inCardioid || inPeriodTwoBulb;
}

vec3 mandelbrotColor(vec2 c, int iterationBudget) {
    if (insideMainBodies(c)) {
        return vec3(0.008, 0.012, 0.030);
    }

    vec2 z = vec2(0.0);
    float escapedAt = float(iterationBudget);
    float radiusSquared = 0.0;

    for (int i = 0; i < MAX_ITERATIONS; i++) {
        if (i >= iterationBudget) {
            break;
        }

        z = vec2(z.x * z.x - z.y * z.y, 2.0 * z.x * z.y) + c;
        radiusSquared = dot(z, z);

        if (radiusSquared > 256.0) {
            escapedAt = float(i);
            break;
        }
    }

    if (escapedAt >= float(iterationBudget)) {
        return vec3(0.008, 0.012, 0.030);
    }

    float logRadius = 0.5 * log(radiusSquared);
    float smoothIteration = escapedAt + 1.0 - log(logRadius / log(2.0)) / log(2.0);
    float colorPosition = 0.035 * smoothIteration;
    vec3 color = palette(colorPosition);

    // Slightly compress highlights so the vanilla sun, moon and clouds remain legible.
    return pow(clamp(color, 0.0, 1.0), vec3(1.18));
}

#include "/lib/mandelbrot_reference.glsl"

vec3 viewRayToWorldDirection(vec2 uv) {
    vec2 ndc = uv * 2.0 - 1.0;
    vec4 viewPosition = gbufferProjectionInverse * vec4(ndc, 1.0, 1.0);
    vec3 viewDirection = normalize(viewPosition.xyz / max(abs(viewPosition.w), 0.000001));
    return normalize(mat3(gbufferModelViewInverse) * viewDirection);
}

void main() {
    vec3 vanillaColor = texture2D(colortex0, texcoord).rgb;
    float depth = texture2D(depthtex0, texcoord).r;

    // Match only an exact clear value for conventional or reversed-Z buffers.
    // Using an epsilon here can accidentally classify far terrain as empty sky.
    bool isClearDepth = depth == 0.0 || depth == 1.0;
    bool canDrawSky = isClearDepth && hasSkylight && !hasCeiling && isEyeInWater == 0;

    if (!canDrawSky) {
        gl_FragColor = vec4(vanillaColor, 1.0);
        return;
    }

    vec3 worldDirection = viewRayToWorldDirection(texcoord);

    // Stereographic projection puts the complex-plane origin at the zenith and
    // maps the horizon to a stable unit circle without a seam.
    vec2 skyPlane = vec2(worldDirection.z, worldDirection.x)
        / max(1.0 + worldDirection.y, 0.08);

    // Falling below the reference plane adds a seamless corkscrew motion. It
    // continues after the configured zoom depth, preserving endless motion.
    float descentBlocks = max(START_ALTITUDE - eyeAltitude, 0.0);
    float voidAngle = mod(descentBlocks, VOID_TWIST_PERIOD) * (TAU / VOID_TWIST_PERIOD);
    float cosVoidAngle = cos(voidAngle);
    float sinVoidAngle = sin(voidAngle);
    skyPlane = mat2(cosVoidAngle, -sinVoidAngle, sinVoidAngle, cosVoidAngle) * skyPlane;

    // Distance from the reference plane drives zoom in either direction:
    // flying upward and falling below zero both dive deeper into the fractal.
    float altitudeSteps = abs(eyeAltitude - START_ALTITUDE)
        / max(BLOCKS_PER_DOUBLING, 1.0);
    float requestedSteps = min(altitudeSteps, float(MAX_ZOOM_STEPS));
    bool referenceValid = mandelbrotReferenceIsValid();
    // A missing/not-yet-published mod texture remains a usable FP32 pack. The
    // logarithmic cap avoids ever constructing a huge, overflowing zoom value.
    float effectiveSteps = referenceValid
        ? requestedSteps
        : min(requestedSteps, 17.0);
    float inverseZoom = exp2(-effectiveSteps);

    // The unshifted X/Z coordinates navigate a smooth, bounded loop. The
    // bounded sine mapping keeps the fractal visible even far from world origin.
    int panPeriodInt = int(PAN_PERIOD);
    ivec2 cameraXZInt = ivec2(cameraPositionInt.z, cameraPositionInt.x);
    ivec2 panQuotient = cameraXZInt / panPeriodInt;
    ivec2 panRemainder = cameraXZInt - panQuotient * panPeriodInt;
    vec2 worldXZ = vec2(panRemainder)
        + vec2(cameraPositionFract.z, cameraPositionFract.x);
    // Double modulo makes negative coordinates explicit and stable across
    // drivers: wrappedXZ is always in [0, PAN_PERIOD).
    vec2 wrappedXZ = mod(mod(worldXZ, vec2(PAN_PERIOD)) + vec2(PAN_PERIOD), vec2(PAN_PERIOD));
    vec2 panPhase = wrappedXZ * (TAU / PAN_PERIOD);
    vec2 playerPan = sin(panPhase) * PAN_RANGE;
    vec2 deltaC = (skyPlane * 2.55 + playerPan) * inverseZoom;
    vec2 complexCoordinate = DEEP_ZOOM_CENTER + deltaC;

    int iterationBudget = int(min(
        float(MAX_ITERATIONS),
        72.0 + 7.0 * effectiveSteps
    ));
    vec3 fractalColor;
    if (!referenceValid || effectiveSteps <= 12.0) {
        fractalColor = mandelbrotColor(complexCoordinate, iterationBudget);
    } else if (effectiveSteps >= 13.0) {
        fractalColor = mandelbrotPerturbationColor(deltaC, effectiveSteps);
    } else {
        // Both paths are well-conditioned in this one-step handoff band. The
        // branch is uniform across the frame, so ordinary pixels do not diverge.
        vec3 directColor = mandelbrotColor(complexCoordinate, iterationBudget);
        vec3 perturbationColor = mandelbrotPerturbationColor(deltaC, effectiveSteps);
        float deepBlend = smoothstep(12.0, 13.0, effectiveSteps);
        fractalColor = mix(directColor, perturbationColor, deepBlend);
    }

    // Every clear-depth pixel is part of the procedural sky. This deliberately
    // fills the otherwise visible strip beyond Minecraft's loaded terrain.
    float blendAmount = FRACTAL_OPACITY;
    vec3 finalColor = mix(vanillaColor, fractalColor, blendAmount);
    gl_FragColor = vec4(finalColor, 1.0);
}
