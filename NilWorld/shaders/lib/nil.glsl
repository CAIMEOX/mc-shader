#ifndef NIL_TRANSFORM_GLSL
#define NIL_TRANSFORM_GLSL

const float NIL_PI = 3.14159265359;

vec2 rotateNilAxes(vec2 value, float degrees) {
    float angle = degrees * NIL_PI / 180.0;
    float cosine = cos(angle);
    float sine = sin(angle);
    return vec2(
        cosine * value.x - sine * value.y,
        sine * value.x + cosine * value.y
    );
}

float nilSinc(float halfAngle) {
    if (abs(halfAngle) < 0.0001) {
        return 1.0 - halfAngle * halfAngle / 6.0;
    }
    return sin(halfAngle) / halfAngle;
}

vec2 nilHorizontalLift(vec2 axisPosition, float relativeHeight) {
    float safeScale = max(NIL_SCALE, 1.0);
    float fiberAngle = relativeHeight * FIBER_TWIST / safeScale;
    float halfAngle = 0.5 * fiberAngle;
    float cosine = cos(halfAngle);
    float sine = sin(halfAngle);
    vec2 rotatedLayer = vec2(
        cosine * axisPosition.x - sine * axisPosition.y,
        sine * axisPosition.x + cosine * axisPosition.y
    );
    return rotatedLayer * nilSinc(halfAngle);
}

vec2 boundedNilCamera(vec2 cameraHorizontal) {
    float safeScale = max(NIL_SCALE, 1.0);
    return safeScale * vec2(
        atan(cameraHorizontal.x / safeScale),
        atan(cameraHorizontal.y / safeScale)
    );
}

vec3 nilCameraRelative(
    vec3 euclideanRelative,
    vec2 cameraHorizontal
) {
    float safeScale = max(NIL_SCALE, 1.0);
    float centralShift = 0.5 * GROUP_COUPLING * (
        cameraHorizontal.y * euclideanRelative.x
        - cameraHorizontal.x * euclideanRelative.z
    ) / safeScale;
    return vec3(
        euclideanRelative.x,
        euclideanRelative.y + centralShift,
        euclideanRelative.z
    );
}

vec3 nilPosition(vec3 relativeWorldPosition, vec2 cameraHorizontal) {
    float safeScale = max(NIL_SCALE, 1.0);
    vec2 axisPosition = rotateNilAxes(
        relativeWorldPosition.xz,
        AXIS_ROTATION
    );
    vec2 cameraAxes = rotateNilAxes(
        boundedNilCamera(cameraHorizontal),
        AXIS_ROTATION
    );
    vec3 groupRelative = nilCameraRelative(
        vec3(axisPosition.x, relativeWorldPosition.y, axisPosition.y),
        cameraAxes
    );
    float maximumFiberShift = safeScale * max(FIBER_LIMIT, 0.0);
    float connectionShift = clamp(
        groupRelative.y - relativeWorldPosition.y,
        -maximumFiberShift,
        maximumFiberShift
    );
    float nilHeight = relativeWorldPosition.y + connectionShift;
    vec2 liftedAxes = nilHorizontalLift(
        axisPosition,
        nilHeight
    );

    // This x*z central term exposes the signed-area holonomy of the
    // Heisenberg group. Clamp it only to keep distant chunks renderable.
    float rawFiberShift = AREA_SHEAR
        * axisPosition.x * axisPosition.y / safeScale;
    float fiberShift = clamp(
        connectionShift + rawFiberShift,
        -maximumFiberShift,
        maximumFiberShift
    );

    vec2 mappedXZ = rotateNilAxes(liftedAxes, -AXIS_ROTATION);
    vec3 mappedPosition = vec3(
        mappedXZ.x,
        relativeWorldPosition.y + fiberShift,
        mappedXZ.y
    );
    return mix(
        relativeWorldPosition,
        mappedPosition,
        clamp(WARP_STRENGTH, 0.0, 1.0)
    );
}

#endif
