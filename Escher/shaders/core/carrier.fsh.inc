
layout(location = 10) flat in int EscherCarrier;
layout(location = 11) flat in vec3 EscherWord;
void main() {
  if (EscherCarrier != 0) {
#ifdef OIT_ALPHA_ONLY
    executeAlphaOnlyPhase(gl_FragCoord.z, 1.0);
#else
#ifdef OIT_ACCUMULATE
    fragColor = sampleColorForAccumulation(vec4(EscherWord, 1.0));
#else
    fragColor = vec4(EscherWord, 1.0);
#endif
#endif
    return;
  }
