#version 120

#include "/lib/settings.glsl"
#include "/lib/ring.glsl"

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
#if ROLL_WITH_PLAYER == 0
uniform ivec3 cameraPositionInt;
uniform vec3 cameraPositionFract;
#endif

varying vec4 color;

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
    color = gl_Color;
}
