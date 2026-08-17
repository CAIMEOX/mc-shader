#version 120

varying vec4 color;
varying vec2 coord0;

void main() {
    vec3 viewPosition = (gl_ModelViewMatrix * gl_Vertex).xyz;
    gl_Position = ftransform();
    gl_FogFragCoord = length(viewPosition);
    color = gl_Color;
    coord0 = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
}
