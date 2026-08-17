#include "/lib/spherical.glsl"

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;

varying vec4 color;
varying vec2 coord0;
varying vec2 coord1;

void main() {
    vec3 viewPosition = (gl_ModelViewMatrix * gl_Vertex).xyz;
    vec3 relativeWorld = (gbufferModelViewInverse * vec4(viewPosition, 1.0)).xyz;
    vec3 warpedWorld = sphericalPosition(relativeWorld);
    gl_Position = gl_ProjectionMatrix * gbufferModelView * vec4(warpedWorld, 1.0);
    gl_FogFragCoord = length(warpedWorld);

    vec3 viewNormal = gl_NormalMatrix * gl_Normal;
    vec3 worldNormal = normalize((gbufferModelViewInverse * vec4(viewNormal, 0.0)).xyz);
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
