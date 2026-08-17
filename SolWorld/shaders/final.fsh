#version 120

#include "/lib/settings.glsl"
#include "/lib/sol.glsl"

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
        vec2 axisDirection = rotateSolAxes(relativeWorld.xz, AXIS_ROTATION);
        float axisLengthSquared = max(dot(axisDirection, axisDirection), 0.0001);
        float axisSignal = (
            axisDirection.x * axisDirection.x
            - axisDirection.y * axisDirection.y
        ) / axisLengthSquared;

        float viewDistance = length(viewPosition);
        float distanceAmount = smoothstep(
            SOL_SCALE * 0.35,
            SOL_SCALE * 3.0,
            viewDistance
        );
        vec3 compressedAxisColor = vec3(1.00, 0.34, 0.16);
        vec3 expandedAxisColor = vec3(0.18, 0.58, 1.00);
        vec3 axisColor = mix(
            compressedAxisColor,
            expandedAxisColor,
            axisSignal * 0.5 + 0.5
        );

        vec3 tintedScene = scene.rgb * (0.82 + axisColor * 0.32);
        color = mix(color, tintedScene, distanceAmount * AXIS_TINT);

        float fogAmount = smoothstep(
            SOL_SCALE * 1.1,
            SOL_SCALE * 4.0,
            viewDistance
        ) * DISTANCE_FOG;
        vec3 solFog = mix(gl_Fog.color.rgb, vec3(0.13, 0.17, 0.24), 0.36);
        color = mix(color, solFog, fogAmount);

        float principalAxis = pow(abs(axisSignal), 4.0);
        color += axisColor * principalAxis * distanceAmount * DISTANCE_GLOW * 0.22;
    }

    gl_FragData[0] = vec4(max(color, vec3(0.0)), scene.a);
}
