#version 120

#include "/lib/settings.glsl"
#include "/lib/nil.glsl"

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
        vec3 viewPosition = reconstructViewPosition(texcoord, depth);
        vec3 relativeWorld = mat3(gbufferModelViewInverse) * viewPosition;
        vec2 axisPosition = rotateNilAxes(relativeWorld.xz, AXIS_ROTATION);
        float radiusSquared = max(dot(axisPosition, axisPosition), 0.0001);
        float holonomySignal = clamp(
            2.0 * axisPosition.x * axisPosition.y / radiusSquared,
            -1.0,
            1.0
        );
        float viewDistance = length(viewPosition);
        float distanceAmount = smoothstep(
            NIL_SCALE * 0.35,
            NIL_SCALE * 3.0,
            viewDistance
        );

        vec3 negativeFiberColor = vec3(0.20, 0.72, 0.94);
        vec3 positiveFiberColor = vec3(0.76, 0.28, 1.00);
        vec3 fiberColor = mix(
            negativeFiberColor,
            positiveFiberColor,
            holonomySignal * 0.5 + 0.5
        );
        vec3 tintedScene = scene.rgb * (0.84 + fiberColor * 0.30);
        color = mix(color, tintedScene, distanceAmount * FIBER_TINT);

        float fiberPhase = atan(axisPosition.y, axisPosition.x)
            + relativeWorld.y * FIBER_TWIST / max(NIL_SCALE, 1.0) * 0.5;
        float fiberBand = pow(0.5 + 0.5 * cos(fiberPhase * 4.0), 8.0);
        color += fiberColor * fiberBand * distanceAmount
            * HOLONOMY_GLOW * 0.28;

        float fogAmount = smoothstep(
            NIL_SCALE * 1.2,
            NIL_SCALE * 4.2,
            viewDistance
        ) * DISTANCE_FOG;
        vec3 nilFog = mix(gl_Fog.color.rgb, vec3(0.12, 0.10, 0.20), 0.34);
        color = mix(color, nilFog, fogAmount);
    }

    gl_FragData[0] = vec4(max(color, vec3(0.0)), scene.a);
}
