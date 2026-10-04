
layout(location = 10) flat in int SignalCarrier;
layout(location = 11) flat in vec3 SignalWord;
void main() {
  if (SignalCarrier != 0) {
#ifdef OIT_ALPHA_ONLY
    executeAlphaOnlyPhase(gl_FragCoord.z, 1.0);
#else
#ifdef OIT_ACCUMULATE
    fragColor = sampleColorForAccumulation(vec4(SignalWord, 1.0));
#else
    fragColor = vec4(SignalWord, 1.0);
#endif
#endif
    return;
  }
