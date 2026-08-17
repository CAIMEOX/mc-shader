#version 120

uniform sampler2D colortex0;
uniform mat4 gbufferModelView;
uniform mat4 gbufferProjection;
uniform ivec3 cameraPositionInt;
uniform vec3 cameraPositionFract;
uniform float viewWidth;
uniform float viewHeight;

#include "/lib/settings.glsl"
#include "/lib/inversion.glsl"

varying vec2 texcoord;

void main() {
    vec4 scene = texture2D(colortex0, texcoord);
    vec3 cameraAbsolute = vec3(cameraPositionInt) + cameraPositionFract;
    vec3 centerRelative = inversionCenterRelative(cameraAbsolute);
    vec3 centerView = (gbufferModelView * vec4(centerRelative, 1.0)).xyz;

    float ring = 0.0;
    float interior = 0.0;
    if (centerView.z < -0.01) {
        vec4 clipCenter = gbufferProjection * vec4(centerView, 1.0);
        vec2 centerUv = clipCenter.xy / clipCenter.w * 0.5 + 0.5;
        float aspect = viewWidth / max(viewHeight, 1.0);
        float projectedRadius = abs(gbufferProjection[0][0]) * INVERSION_RADIUS
            / max(-centerView.z, 0.01) * 0.5;
        float distanceFromCenter = length((texcoord - centerUv) * vec2(aspect, 1.0));
        float width = max(SINGULARITY_WIDTH, 0.001);
        float normalizedRing = (distanceFromCenter - projectedRadius) / width;
        ring = exp(-normalizedRing * normalizedRing);
        interior = 1.0 - smoothstep(projectedRadius * 0.72, projectedRadius,
            distanceFromCenter);
    }

    vec3 color = scene.rgb;
    color *= 1.0 - interior * SINGULARITY_VIGNETTE;
    color += vec3(0.35, 0.67, 1.00) * ring * SINGULARITY_GLOW;
    gl_FragData[0] = vec4(max(color, vec3(0.0)), scene.a);
}
