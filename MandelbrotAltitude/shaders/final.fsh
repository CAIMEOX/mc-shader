#version 120

// User-facing shader options. Iris discovers the values in square brackets.
#define START_ALTITUDE 64.0 // [0.0 32.0 64.0 96.0 128.0] Height where zoom x1 begins
#define BLOCKS_PER_DOUBLING 24.0 // [8.0 12.0 16.0 24.0 32.0 48.0 64.0] Vertical blocks per 2x zoom
#define PAN_PERIOD 2000.0 // [500.0 1000.0 1500.0 2000.0 3000.0 5000.0 10000.0] Blocks per horizontal navigation cycle
#define PAN_RANGE 0.65 // [0.00 0.25 0.40 0.55 0.65 0.80 1.00] Maximum sky-plane displacement
#define MAX_ITERATIONS 128 // [64 96 128 160 192 256] Fractal detail and GPU cost
#define MAX_ZOOM 131072.0 // [1024.0 4096.0 16384.0 65536.0 131072.0 262144.0] Float precision safety limit
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
const vec2 DEEP_ZOOM_CENTER = vec2(-0.743643887, 0.131825904);

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

    float altitudeSteps = max(eyeAltitude - START_ALTITUDE, 0.0)
        / max(BLOCKS_PER_DOUBLING, 1.0);
    float zoom = min(exp2(altitudeSteps), MAX_ZOOM);

    // The unshifted X/Z coordinates navigate a smooth, bounded loop. The
    // bounded sine mapping keeps the fractal visible even far from world origin.
    vec2 worldXZ = vec2(float(cameraPositionInt.z), float(cameraPositionInt.x))
        + vec2(cameraPositionFract.z, cameraPositionFract.x);
    vec2 panPhase = mod(worldXZ, vec2(PAN_PERIOD)) * (TAU / PAN_PERIOD);
    vec2 playerPan = sin(panPhase) * PAN_RANGE;
    vec2 complexCoordinate = DEEP_ZOOM_CENTER + (skyPlane * 2.55 + playerPan) / zoom;

    int iterationBudget = int(min(
        float(MAX_ITERATIONS),
        72.0 + 7.0 * log(zoom) / log(2.0)
    ));
    vec3 fractalColor = mandelbrotColor(complexCoordinate, iterationBudget);

    // Every clear-depth pixel is part of the procedural sky. This deliberately
    // fills the otherwise visible strip beyond Minecraft's loaded terrain.
    float blendAmount = FRACTAL_OPACITY;
    vec3 finalColor = mix(vanillaColor, fractalColor, blendAmount);
    gl_FragColor = vec4(finalColor, 1.0);
}
