#version 120

#include "/lib/settings.glsl"

varying vec2 texcoord;

uniform sampler2D colortex0;
uniform sampler2D depthtex0;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;

float depthToNdc(float depth) {
    bool zeroToOneReverseZ = gbufferProjection[2][2] > -0.5;
    return zeroToOneReverseZ ? depth : depth * 2.0 - 1.0;
}

vec3 reconstructViewPosition(vec2 uv, float depth) {
    vec4 clipPosition = vec4(uv * 2.0 - 1.0, depthToNdc(depth), 1.0);
    vec4 viewPosition = gbufferProjectionInverse * clipPosition;
    return viewPosition.xyz / viewPosition.w;
}

void main() {
    vec4 scene = texture2D(colortex0, texcoord);
    float depth = texture2D(depthtex0, texcoord).r;
    bool clearDepth = depth == 0.0 || depth == 1.0;

    float boundaryAmount = 0.0;
    if (!clearDepth) {
        float viewDistance = length(reconstructViewPosition(texcoord, depth));
        float boundaryDistance = max(2.0 * CURVATURE_RADIUS, 1.0);
        boundaryAmount = clamp(viewDistance / boundaryDistance, 0.0, 1.0);
    }

    float edge = smoothstep(0.52, 0.98, boundaryAmount);
    float ringOffset = (boundaryAmount - 0.82) / 0.085;
    float ring = exp(-ringOffset * ringOffset) * step(0.01, boundaryAmount);
    vec3 boundaryColor = mix(gl_Fog.color.rgb, vec3(0.13, 0.24, 0.38), 0.42);

    vec3 color = mix(scene.rgb, boundaryColor, edge * BOUNDARY_FOG);
    color *= 1.0 - edge * BOUNDARY_DARKEN;
    color += vec3(0.16, 0.42, 0.72) * ring * BOUNDARY_GLOW;
    gl_FragData[0] = vec4(max(color, vec3(0.0)), scene.a);
}
