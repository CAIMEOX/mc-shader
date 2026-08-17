#version 120

uniform sampler2D texture;
uniform sampler2D lightmap;
uniform vec4 entityColor;

varying vec4 color;
varying vec2 coord0;
varying vec2 coord1;

void main() {
    vec4 shaded = color * vec4(texture2D(lightmap, coord1).rgb, 1.0)
        * texture2D(texture, coord0);
    shaded.rgb = mix(shaded.rgb, entityColor.rgb, entityColor.a);
    gl_FragData[0] = shaded;
}
