#version 120

uniform sampler2D texture;

varying vec4 color;
varying vec2 coord0;

void main() {
    vec4 shaded = color * texture2D(texture, coord0);
    float fogAmount = clamp((gl_FogFragCoord - gl_Fog.start) * gl_Fog.scale, 0.0, 1.0);
    shaded.rgb = mix(shaded.rgb, gl_Fog.color.rgb, fogAmount);
    gl_FragData[0] = shaded;
}
