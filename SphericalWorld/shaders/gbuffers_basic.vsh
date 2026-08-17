#version 120

#include "/lib/settings.glsl"
#include "/lib/spherical.glsl"

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;

varying vec4 color;

void main() {
    vec3 viewPosition = (gl_ModelViewMatrix * gl_Vertex).xyz;
    vec3 relativeWorld = (gbufferModelViewInverse * vec4(viewPosition, 1.0)).xyz;
    vec3 warpedWorld = sphericalPosition(relativeWorld);
    gl_Position = gl_ProjectionMatrix * gbufferModelView * vec4(warpedWorld, 1.0);
    gl_FogFragCoord = length(warpedWorld);
    color = gl_Color;
}
