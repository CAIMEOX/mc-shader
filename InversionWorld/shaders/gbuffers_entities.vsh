#version 120

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform ivec3 cameraPositionInt;
uniform vec3 cameraPositionFract;

#include "/lib/settings.glsl"
#include "/lib/inversion.glsl"

varying vec4 color;
varying vec2 coord0;
varying vec2 coord1;

void main() {
    vec3 viewPosition = (gl_ModelViewMatrix * gl_Vertex).xyz;
    vec3 relativeWorld = (gbufferModelViewInverse * vec4(viewPosition, 1.0)).xyz;
    vec3 cameraAbsolute = vec3(cameraPositionInt) + cameraPositionFract;
    vec3 invertedWorld = inversionPosition(relativeWorld, cameraAbsolute);
    gl_Position = gl_ProjectionMatrix * gbufferModelView * vec4(invertedWorld, 1.0);
    gl_FogFragCoord = length(invertedWorld);
    color = gl_Color;
    coord0 = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    coord1 = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
}
