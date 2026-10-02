#include "/lib/ring.glsl"

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
#if ROLL_WITH_PLAYER == 0
uniform ivec3 cameraPositionInt;
uniform vec3 cameraPositionFract;
#elif defined(RING_DEBUG_SURFACE) && RING_DEBUG_MODE > 0
uniform ivec3 cameraPositionInt;
uniform vec3 cameraPositionFract;
#endif

varying vec4 color;
varying vec2 coord0;
varying vec2 coord1;
#ifdef RING_DEBUG_SURFACE
#if RING_DEBUG_MODE > 0
varying vec3 debugSourcePosition;
varying vec3 debugLocalPosition;
varying vec3 debugSourceNormal;
#endif
#endif

void main() {
    vec3 viewPosition = (gl_ModelViewMatrix * gl_Vertex).xyz;
    vec3 relativeWorld = (gbufferModelViewInverse * vec4(viewPosition, 1.0)).xyz;
#if ROLL_WITH_PLAYER == 1
    vec2 cameraPhase = vec2(0.0);
#else
    vec2 cameraPhase = ringCameraPhase(
        cameraPositionInt,
        cameraPositionFract
    );
#endif
    vec3 warpedWorld = ringPosition(relativeWorld, cameraPhase);
    gl_Position = gl_ProjectionMatrix * gbufferModelView * vec4(warpedWorld, 1.0);
    gl_FogFragCoord = length(warpedWorld);

    vec3 viewNormal = gl_NormalMatrix * gl_Normal;
    vec3 sourceNormal = normalize(
        (gbufferModelViewInverse * vec4(viewNormal, 0.0)).xyz
    );
#ifdef RING_DEBUG_SURFACE
#if RING_DEBUG_MODE > 0
    const float debugWorldPeriod = 256.0;
    vec3 debugCameraPhase = vec3(
        ringSplitPhase(
            cameraPositionInt.x,
            cameraPositionFract.x,
            debugWorldPeriod
        ),
        ringSplitPhase(
            cameraPositionInt.y,
            cameraPositionFract.y,
            debugWorldPeriod
        ),
        ringSplitPhase(
            cameraPositionInt.z,
            cameraPositionFract.z,
            debugWorldPeriod
        )
    );
    debugSourcePosition = relativeWorld + debugCameraPhase;
    debugLocalPosition = relativeWorld;
    debugSourceNormal = sourceNormal;
#endif
#endif
    vec3 worldNormal = ringMappedNormal(
        relativeWorld,
        sourceNormal,
        cameraPhase
    );
    float faceLight = min(
        worldNormal.x * worldNormal.x * 0.60
        + worldNormal.y * worldNormal.y * 0.25 * (3.0 + worldNormal.y)
        + worldNormal.z * worldNormal.z * 0.80,
        1.0
    );
    color = vec4(gl_Color.rgb * faceLight, gl_Color.a);
    coord0 = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    coord1 = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
}
