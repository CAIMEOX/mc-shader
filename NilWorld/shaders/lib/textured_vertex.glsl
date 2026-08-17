#include "/lib/nil.glsl"

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform vec3 cameraPosition;

varying vec4 color;
varying vec2 coord0;
varying vec2 coord1;
#ifdef NIL_GRID_SURFACE
#if GRID_MODE > 0
uniform ivec3 cameraPositionInt;
uniform vec3 cameraPositionFract;
varying vec3 gridPosition;
varying vec3 gridNormal;
#endif
#endif

void main() {
    vec3 viewPosition = (gl_ModelViewMatrix * gl_Vertex).xyz;
    vec3 relativeWorld = (gbufferModelViewInverse * vec4(viewPosition, 1.0)).xyz;
    vec3 warpedWorld = nilPosition(relativeWorld, cameraPosition.xz);
    gl_Position = gl_ProjectionMatrix * gbufferModelView * vec4(warpedWorld, 1.0);
    gl_FogFragCoord = length(warpedWorld);

    vec3 viewNormal = gl_NormalMatrix * gl_Normal;
    vec3 worldNormal = normalize((gbufferModelViewInverse * vec4(viewNormal, 0.0)).xyz);
#ifdef NIL_GRID_SURFACE
#if GRID_MODE > 0
    int gridPeriod = int(GRID_SPACING * GRID_MAJOR_EVERY + 0.5);
    ivec3 gridQuotient = cameraPositionInt / gridPeriod;
    ivec3 gridRemainder = cameraPositionInt - gridQuotient * gridPeriod;
    vec3 gridCameraPhase = mod(
        vec3(gridRemainder) + cameraPositionFract,
        vec3(float(gridPeriod))
    );
    gridPosition = relativeWorld + gridCameraPhase;
    gridNormal = worldNormal;
#endif
#endif
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
