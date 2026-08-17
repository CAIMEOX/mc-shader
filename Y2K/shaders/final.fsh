#version 120

// Overall color treatment.
#define Y2K_INTENSITY 0.75 // [0.00 0.25 0.50 0.75 1.00]
#define Y2K_TINT 0.55 // [0.00 0.25 0.35 0.55 0.75 1.00]
#define SATURATION 1.10 // [0.80 1.00 1.10 1.20 1.35 1.50]
#define CONTRAST 1.08 // [0.90 1.00 1.04 1.08 1.16 1.25]

// Compact nine-tap bloom and early-digital lens character.
#define BLOOM_STRENGTH 0.18 // [0.00 0.08 0.18 0.32 0.50 0.75]
#define BLOOM_RADIUS 2.0 // [1.0 2.0 3.0 4.0 6.0]
#define CHROMATIC_ABERRATION 1.25 // [0.00 0.50 1.25 2.50 4.00 6.00]
#define BARREL_DISTORTION 0.020 // [0.000 0.010 0.020 0.040 0.060 0.100]
#define VIGNETTE_STRENGTH 0.16 // [0.00 0.08 0.16 0.28 0.40 0.60]

// Display texture. These operate in physical screen pixels.
#define SCANLINE_STRENGTH 0.08 // [0.00 0.03 0.08 0.16 0.25 0.40]
#define PIXEL_GRID_STRENGTH 0.04 // [0.00 0.04 0.10 0.18 0.30]
#define NOISE_STRENGTH 0.018 // [0.000 0.008 0.018 0.035 0.060 0.100]

// Occasional horizontal tracking errors, kept subtle in the default profile.
#define GLITCH_ENABLED
#define GLITCH_STRENGTH 0.10 // [0.00 0.10 0.30 0.50 1.00]
#define GLITCH_SPEED 1.00 // [0.25 0.50 1.00 1.50 2.00 3.00]

varying vec2 texcoord;

uniform sampler2D colortex0;
uniform float viewWidth;
uniform float viewHeight;
uniform float frameTimeCounter;

const float PI = 3.14159265359;

float hash12(vec2 value) {
    vec3 p3 = fract(vec3(value.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

vec2 safeUv(vec2 uv) {
    vec2 halfPixel = 0.5 / vec2(max(viewWidth, 1.0), max(viewHeight, 1.0));
    return clamp(uv, halfPixel, vec2(1.0) - halfPixel);
}

vec2 barrelWarp(vec2 uv) {
    vec2 centered = uv * 2.0 - 1.0;
    float radiusSquared = dot(centered, centered);
    centered *= 1.0 + BARREL_DISTORTION * radiusSquared;
    return centered * 0.5 + 0.5;
}

vec2 glitchOffset(vec2 uv) {
#ifdef GLITCH_ENABLED
    float frame = floor(frameTimeCounter * GLITCH_SPEED * 12.0);
    float band = floor(uv.y * 96.0);
    float bandNoise = hash12(vec2(band, frame));
    float burst = step(0.88, hash12(vec2(frame, 19.17)));
    float activeBand = step(0.955, bandNoise) * burst;
    float largeShift = (hash12(vec2(band + 7.3, frame)) - 0.5)
        * 0.055 * GLITCH_STRENGTH * activeBand;
    float digitalJitter = (hash12(vec2(band, frame + 41.0)) - 0.5)
        * 0.0015 * GLITCH_STRENGTH;
    return vec2(largeShift + digitalJitter, 0.0);
#else
    return vec2(0.0);
#endif
}

vec3 sampleChromatic(vec2 uv) {
    vec2 centered = uv - 0.5;
    float radius = length(centered);
    vec2 radial = centered / max(radius, 0.0001);
    vec2 pixel = 1.0 / vec2(max(viewWidth, 1.0), max(viewHeight, 1.0));
    vec2 separation = radial * pixel * CHROMATIC_ABERRATION
        * (0.35 + radius * 1.65);

    float red = texture2D(colortex0, safeUv(uv + separation)).r;
    float green = texture2D(colortex0, safeUv(uv)).g;
    float blue = texture2D(colortex0, safeUv(uv - separation)).b;
    return vec3(red, green, blue);
}

vec3 extractBloom(vec3 color) {
    float peak = max(color.r, max(color.g, color.b));
    float bright = smoothstep(0.58, 1.0, peak);
    return color * bright;
}

vec3 sampleBloom(vec2 uv) {
    vec2 pixel = BLOOM_RADIUS
        / vec2(max(viewWidth, 1.0), max(viewHeight, 1.0));
    vec3 bloom = extractBloom(texture2D(colortex0, safeUv(uv)).rgb) * 0.20;
    bloom += extractBloom(texture2D(colortex0, safeUv(uv + vec2(pixel.x, 0.0))).rgb) * 0.12;
    bloom += extractBloom(texture2D(colortex0, safeUv(uv - vec2(pixel.x, 0.0))).rgb) * 0.12;
    bloom += extractBloom(texture2D(colortex0, safeUv(uv + vec2(0.0, pixel.y))).rgb) * 0.12;
    bloom += extractBloom(texture2D(colortex0, safeUv(uv - vec2(0.0, pixel.y))).rgb) * 0.12;
    bloom += extractBloom(texture2D(colortex0, safeUv(uv + pixel)).rgb) * 0.08;
    bloom += extractBloom(texture2D(colortex0, safeUv(uv - pixel)).rgb) * 0.08;
    bloom += extractBloom(texture2D(colortex0, safeUv(uv + vec2(pixel.x, -pixel.y))).rgb) * 0.08;
    bloom += extractBloom(texture2D(colortex0, safeUv(uv + vec2(-pixel.x, pixel.y))).rgb) * 0.08;
    return bloom;
}

vec3 y2kGrade(vec3 color) {
    float luminance = dot(color, vec3(0.2126, 0.7152, 0.0722));
    color = mix(vec3(luminance), color, SATURATION);
    color = (color - 0.5) * CONTRAST + 0.5;

    vec3 silverCyan = vec3(0.82, 1.03, 1.08);
    vec3 pearlescentMagenta = vec3(1.09, 0.86, 1.04);
    float highlight = smoothstep(0.28, 0.88, luminance);
    vec3 splitTone = mix(silverCyan, pearlescentMagenta, highlight);
    color *= mix(vec3(1.0), splitTone, Y2K_TINT * 0.62);
    color += vec3(0.012, 0.018, 0.026) * Y2K_TINT;
    return color;
}

void main() {
    vec4 original = texture2D(colortex0, texcoord);
    vec2 warpedUv = barrelWarp(texcoord);
    warpedUv += glitchOffset(warpedUv);
    warpedUv = safeUv(warpedUv);

    vec3 filtered = sampleChromatic(warpedUv);
    filtered += sampleBloom(warpedUv) * BLOOM_STRENGTH;
    filtered = y2kGrade(filtered);

    float scanWave = 0.5 + 0.5 * sin(gl_FragCoord.y * PI);
    filtered *= 1.0 - SCANLINE_STRENGTH * (0.25 + 0.75 * scanWave);

    vec2 gridCell = abs(fract(gl_FragCoord.xy / 3.0) - 0.5) * 2.0;
    float pixelEdge = smoothstep(0.82, 1.0, max(gridCell.x, gridCell.y));
    filtered *= 1.0 - PIXEL_GRID_STRENGTH * pixelEdge;

    float noiseFrame = floor(frameTimeCounter * 60.0);
    float sensorNoise = hash12(gl_FragCoord.xy + vec2(noiseFrame * 17.0, noiseFrame));
    filtered += (sensorNoise - 0.5) * NOISE_STRENGTH;

    vec2 vignetteUv = texcoord * (1.0 - texcoord);
    float vignette = clamp(pow(vignetteUv.x * vignetteUv.y * 16.0, 0.22), 0.0, 1.0);
    filtered *= mix(1.0, vignette, VIGNETTE_STRENGTH);

    vec3 result = mix(original.rgb, filtered, clamp(Y2K_INTENSITY, 0.0, 1.0));
    gl_FragData[0] = vec4(max(result, vec3(0.0)), original.a);
}
