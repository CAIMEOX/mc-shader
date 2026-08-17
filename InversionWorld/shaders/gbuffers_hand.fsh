#version 120

uniform sampler2D texture;
uniform sampler2D lightmap;

varying vec4 color;
varying vec2 coord0;
varying vec2 coord1;

void main() {
    gl_FragData[0] = color * vec4(texture2D(lightmap, coord1).rgb, 1.0)
        * texture2D(texture, coord0);
}
