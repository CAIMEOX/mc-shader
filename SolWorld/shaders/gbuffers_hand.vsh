#version 120

varying vec4 color;
varying vec2 coord0;
varying vec2 coord1;

void main() {
    gl_Position = ftransform();
    color = gl_Color;
    coord0 = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    coord1 = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
}
