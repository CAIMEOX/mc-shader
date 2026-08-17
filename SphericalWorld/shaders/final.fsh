#version 120

#include "/lib/settings.glsl"

varying vec2 texcoord;

uniform sampler2D colortex0;
uniform sampler2D depthtex0;
uniform mat4 gbufferModelViewInverse;
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
    vec3 color = scene.rgb;

    if (!clearDepth) {
        float safeRadius = max(SPHERE_RADIUS, 1.0);
        vec3 viewPosition = reconstructViewPosition(texcoord, depth);
        vec3 relativeWorld = mat3(gbufferModelViewInverse) * viewPosition;
        float viewDistance = length(viewPosition);
        float shellHeight = clamp(relativeWorld.y / (2.0 * safeRadius), 0.0, 1.0);

        vec3 horizonColor = vec3(0.34, 0.52, 0.76);
        float horizonAmount = smoothstep(0.08, 0.82, shellHeight) * HORIZON_TINT;
        color = mix(color, color * (0.82 + horizonColor * 0.34), horizonAmount);

        float fogAmount = smoothstep(
            safeRadius * 0.75,
            safeRadius * 2.25,
            viewDistance
        ) * SPHERE_FOG;
        vec3 sphereFogColor = mix(gl_Fog.color.rgb, vec3(0.16, 0.22, 0.34), 0.38);
        color = mix(color, sphereFogColor, fogAmount);

        float antipodeOffset = (relativeWorld.y - 2.0 * safeRadius)
            / (safeRadius * 0.20);
        float antipodeRing = exp(-antipodeOffset * antipodeOffset);
        color += vec3(0.34, 0.58, 1.00) * antipodeRing * ANTIPODE_GLOW;
    }

    gl_FragData[0] = vec4(max(color, vec3(0.0)), scene.a);
}
