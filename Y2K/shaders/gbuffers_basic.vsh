#version 120

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;

varying vec4 color;

void main() {
    vec3 viewPosition = (gl_ModelViewMatrix * gl_Vertex).xyz;
    vec3 worldPosition = (gbufferModelViewInverse * vec4(viewPosition, 1.0)).xyz;
    gl_Position = gl_ProjectionMatrix * gbufferModelView * vec4(worldPosition, 1.0);
    gl_FogFragCoord = length(worldPosition);
    color = gl_Color;
}
