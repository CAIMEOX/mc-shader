#version 120

uniform float blindness;
uniform int isEyeInWater;

varying vec4 color;

void main() {
    float fogAmount = isEyeInWater > 0
        ? 1.0 - exp(-gl_FogFragCoord * gl_Fog.density)
        : clamp((gl_FogFragCoord - gl_Fog.start) * gl_Fog.scale, 0.0, 1.0);
    vec4 shaded = color;
    shaded.rgb = mix(shaded.rgb, gl_Fog.color.rgb, fogAmount);
    shaded.rgb *= 1.0 - blindness;
    gl_FragData[0] = shaded;
}
