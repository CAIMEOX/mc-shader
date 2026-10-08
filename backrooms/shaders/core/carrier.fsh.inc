
layout(location = 10) flat in int BackroomsCarrier;
layout(location = 11) flat in vec3 BackroomsWord;
void main() {
  if (BackroomsCarrier != 0) {
#ifdef OIT_ALPHA_ONLY
    executeAlphaOnlyPhase(gl_FragCoord.z, 1.0);
#else
#ifdef OIT_ACCUMULATE
    fragColor = sampleColorForAccumulation(vec4(BackroomsWord, 1.0));
#else
    fragColor = vec4(BackroomsWord, 1.0);
#endif
#endif
    return;
  }
