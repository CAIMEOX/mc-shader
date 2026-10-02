// per-head RMS + split-half RoPE
int h = i / HEAD_DIM, j = i % HEAD_DIM, k = j % (HEAD_DIM / 2);
float ss = 0.;
for (int a = 0; a < HEAD_DIM; a++) {
  float v = scalar(Input0Sampler, h * HEAD_DIM + a);
  ss += v * v;
}
float inv = inversesqrt(ss / float(HEAD_DIM) + RMS_EPS);
float x = scalar(Input0Sampler, h *HEAD_DIM + k) * inv * scalar(NormsSampler, b + k);
float y = scalar(Input0Sampler, h *HEAD_DIM + k + HEAD_DIM / 2) * inv *
          scalar(NormsSampler, b + k + HEAD_DIM / 2);
float angle = float(State.y) * pow(ROPE_THETA, -float(k) / float(HEAD_DIM / 2));
outValue = j < HEAD_DIM / 2 ? x * cos(angle) - y * sin(angle)
                            : x * sin(angle) + y * cos(angle);
