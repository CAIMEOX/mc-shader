#version 120

#include "/lib/settings.glsl"
#include "/lib/ring.glsl"

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

    if (clearDepth) {
        vec3 farViewPosition = reconstructViewPosition(texcoord, 1.0);
        vec3 worldRay = mat3(gbufferModelViewInverse) * farViewPosition;
        color = applyRingSky(color, worldRay);
    } else {
        float safeCurvature = max(CURVATURE, 0.000001);
        float ringRadius = 1.0 / safeCurvature;
        vec3 viewPosition = reconstructViewPosition(texcoord, depth);
        float viewDistance = length(viewPosition);

        float fogAmount = smoothstep(
            ringRadius * 0.55,
            ringRadius * 2.40,
            viewDistance
        ) * RING_FOG;
        vec3 ringFogColor = mix(gl_Fog.color.rgb, vec3(0.09, 0.13, 0.26), 0.42);
        color = mix(color, ringFogColor, fogAmount);
    }

    gl_FragData[0] = vec4(max(color, vec3(0.0)), scene.a);
}
