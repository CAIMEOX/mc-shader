uniform sampler2D texture;
uniform sampler2D lightmap;
uniform vec4 entityColor;
uniform float blindness;
uniform int isEyeInWater;

#ifdef NIL_GRID_SURFACE
#if GRID_MODE > 0
#include "/lib/grid.glsl"
#endif
#endif

varying vec4 color;
varying vec2 coord0;
varying vec2 coord1;
#ifdef NIL_GRID_SURFACE
#if GRID_MODE > 0
varying vec3 gridPosition;
varying vec3 gridNormal;
#endif
#endif

void main() {
    vec3 light = texture2D(lightmap, coord1).rgb * (1.0 - blindness);
    vec4 shaded = color * vec4(light, 1.0) * texture2D(texture, coord0);
    shaded.rgb = mix(shaded.rgb, entityColor.rgb, entityColor.a);
#ifdef NIL_GRID_SURFACE
#if GRID_MODE > 0
    shaded.rgb = applyNilGrid(shaded.rgb, gridPosition, gridNormal);
#endif
#endif
    float fogAmount = isEyeInWater > 0
        ? 1.0 - exp(-gl_FogFragCoord * gl_Fog.density)
        : clamp((gl_FogFragCoord - gl_Fog.start) * gl_Fog.scale, 0.0, 1.0);
    shaded.rgb = mix(shaded.rgb, gl_Fog.color.rgb, fogAmount);
    gl_FragData[0] = shaded;
}
