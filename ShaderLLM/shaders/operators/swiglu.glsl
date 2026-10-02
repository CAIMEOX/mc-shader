float x = scalar(Input0Sampler, i);
outValue = x * scalar(Input1Sampler, i) / (1. + exp(-x));
