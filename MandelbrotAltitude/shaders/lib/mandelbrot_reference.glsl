#ifndef MANDELBROT_REFERENCE_GLSL
#define MANDELBROT_REFERENCE_GLSL

#ifndef MANDELBROT_FORCE_REFERENCE_INVALID
#define MANDELBROT_FORCE_REFERENCE_INVALID 0
#endif

uniform sampler2D mandelbrotReference;

const float MANDELBROT_REFERENCE_WIDTH = 4105.0;
const float MANDELBROT_ORBIT_OFFSET = 9.0;
const vec4 MANDELBROT_REFERENCE_MARKER = vec4(77.0, 66.0, 82.0, 1.0);

struct MandelbrotSplitComplex {
    vec2 hi;
    vec2 lo;
};

vec2 complexMultiply(vec2 left, vec2 right) {
    return vec2(
        left.x * right.x - left.y * right.y,
        left.x * right.y + left.y * right.x
    );
}

vec4 mandelbrotReferenceTexel(float texelIndex) {
    vec2 uv = vec2(
        (texelIndex + 0.5) / MANDELBROT_REFERENCE_WIDTH,
        0.5
    );
    return texture2D(mandelbrotReference, uv);
}

bool mandelbrotReferenceIsValid() {
#if MANDELBROT_FORCE_REFERENCE_INVALID == 1
    return false;
#else
    vec4 marker = mandelbrotReferenceTexel(0.0);
    return all(lessThan(abs(marker - MANDELBROT_REFERENCE_MARKER), vec4(0.25)));
#endif
}

MandelbrotSplitComplex mandelbrotReferenceAt(int iteration) {
    MandelbrotSplitComplex result;
    if (iteration <= 0) {
        result.hi = vec2(0.0);
        result.lo = vec2(0.0);
        return result;
    }

    float texelIndex = MANDELBROT_ORBIT_OFFSET + float(iteration - 1);
    vec4 encoded = mandelbrotReferenceTexel(texelIndex);
    result.hi = encoded.xy;
    result.lo = encoded.zw;
    return result;
}

vec2 mandelbrotSeriesDelta(int checkpointIndex, vec2 deltaC) {
    float firstTexel = 1.0 + float(checkpointIndex * 2);
    vec4 encodedAB = mandelbrotReferenceTexel(firstTexel);
    vec4 encodedC = mandelbrotReferenceTexel(firstTexel + 1.0);
    vec2 coefficientA = encodedAB.xy;
    vec2 coefficientB = encodedAB.zw;
    vec2 coefficientC = encodedC.xy;
    vec2 deltaSquared = complexMultiply(deltaC, deltaC);
    vec2 deltaCubed = complexMultiply(deltaSquared, deltaC);
    return complexMultiply(coefficientA, deltaC)
        + complexMultiply(coefficientB, deltaSquared)
        + complexMultiply(coefficientC, deltaCubed);
}

vec3 mandelbrotPerturbationColorAtCheckpoint(
    vec2 deltaC,
    int startIteration,
    int checkpointIndex
) {
    int referenceIndex = startIteration;
    MandelbrotSplitComplex referenceValue = mandelbrotReferenceAt(referenceIndex);
    vec2 deltaZ = vec2(0.0);
    if (checkpointIndex >= 0) {
        deltaZ = mandelbrotSeriesDelta(checkpointIndex, deltaC);
    }

    float escapedAt = float(startIteration + MAX_ITERATIONS);
    float radiusSquared = 0.0;

    for (int i = 0; i < MAX_ITERATIONS; i++) {
        vec2 referenceProduct = complexMultiply(referenceValue.hi, deltaZ)
            + complexMultiply(referenceValue.lo, deltaZ);
        deltaZ = 2.0 * referenceProduct
            + complexMultiply(deltaZ, deltaZ)
            + deltaC;

        referenceIndex += 1;
        referenceValue = mandelbrotReferenceAt(referenceIndex);
        vec2 actual = referenceValue.hi + deltaZ + referenceValue.lo;
        radiusSquared = dot(actual, actual);
        float globalIteration = float(startIteration + i);

        if (radiusSquared > 256.0) {
            escapedAt = globalIteration;
            break;
        }

        vec2 completeReference = referenceValue.hi + referenceValue.lo;
        float deltaSquaredMagnitude = dot(deltaZ, deltaZ);
        float referenceSquaredMagnitude = dot(completeReference, completeReference);
        bool cancellation = radiusSquared < min(
            deltaSquaredMagnitude,
            0.0001 * referenceSquaredMagnitude
        );
        if (cancellation) {
            // Rebinding to Z0 is an exact change of coordinates: actual is the
            // new delta, while the loop's global iteration remains unchanged.
            deltaZ = actual;
            referenceIndex = 0;
            referenceValue = mandelbrotReferenceAt(referenceIndex);
        }
    }

    if (escapedAt >= float(startIteration + MAX_ITERATIONS)) {
        return vec3(0.008, 0.012, 0.030);
    }

    float logRadius = 0.5 * log(radiusSquared);
    float smoothIteration = escapedAt + 1.0
        - log(logRadius / log(2.0)) / log(2.0);
    vec3 color = palette(0.035 * smoothIteration);
    return pow(clamp(color, 0.0, 1.0), vec3(1.18));
}

vec3 mandelbrotPerturbationColor(vec2 deltaC, float zoomSteps) {
    vec3 oldColor;
    vec3 newColor;
    float checkpointBlend;

    if (zoomSteps < 25.0) {
        return mandelbrotPerturbationColorAtCheckpoint(deltaC, 0, -1);
    }
    if (zoomSteps <= 26.0) {
        oldColor = mandelbrotPerturbationColorAtCheckpoint(deltaC, 0, -1);
        newColor = mandelbrotPerturbationColorAtCheckpoint(deltaC, 64, 0);
        checkpointBlend = smoothstep(25.0, 26.0, zoomSteps);
        return mix(oldColor, newColor, checkpointBlend);
    }

    if (zoomSteps < 29.0) {
        return mandelbrotPerturbationColorAtCheckpoint(deltaC, 64, 0);
    }
    if (zoomSteps <= 30.0) {
        oldColor = mandelbrotPerturbationColorAtCheckpoint(deltaC, 64, 0);
        newColor = mandelbrotPerturbationColorAtCheckpoint(deltaC, 256, 1);
        checkpointBlend = smoothstep(29.0, 30.0, zoomSteps);
        return mix(oldColor, newColor, checkpointBlend);
    }

    if (zoomSteps < 42.0) {
        return mandelbrotPerturbationColorAtCheckpoint(deltaC, 256, 1);
    }
    if (zoomSteps <= 43.0) {
        oldColor = mandelbrotPerturbationColorAtCheckpoint(deltaC, 256, 1);
        newColor = mandelbrotPerturbationColorAtCheckpoint(deltaC, 1024, 2);
        checkpointBlend = smoothstep(42.0, 43.0, zoomSteps);
        return mix(oldColor, newColor, checkpointBlend);
    }

    if (zoomSteps < 60.0) {
        return mandelbrotPerturbationColorAtCheckpoint(deltaC, 1024, 2);
    }
    if (zoomSteps <= 61.0) {
        oldColor = mandelbrotPerturbationColorAtCheckpoint(deltaC, 1024, 2);
        newColor = mandelbrotPerturbationColorAtCheckpoint(deltaC, 3840, 3);
        checkpointBlend = smoothstep(60.0, 61.0, zoomSteps);
        return mix(oldColor, newColor, checkpointBlend);
    }

    return mandelbrotPerturbationColorAtCheckpoint(deltaC, 3840, 3);
}

#endif
