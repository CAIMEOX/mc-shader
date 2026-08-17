#version 120

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform ivec3 cameraPositionInt;
uniform vec3 cameraPositionFract;

#include "/lib/settings.glsl"
#include "/lib/inversion.glsl"

varying vec4 color;

void main() {
    vec3 viewPosition = (gl_ModelViewMatrix * gl_Vertex).xyz;
    vec3 relativeWorld = (gbufferModelViewInverse * vec4(viewPosition, 1.0)).xyz;
    vec3 cameraAbsolute = vec3(cameraPositionInt) + cameraPositionFract;
    vec3 invertedWorld = inversionPosition(relativeWorld, cameraAbsolute);
    gl_Position = gl_ProjectionMatrix * gbufferModelView * vec4(invertedWorld, 1.0);
    gl_FogFragCoord = length(invertedWorld);
    color = gl_Color;
}
