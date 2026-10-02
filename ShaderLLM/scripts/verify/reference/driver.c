/* Benchmark driver for the pinned qwen3.c forward implementation. */
int main(int argc, char **argv) {
  if (argc != 5) {
    fprintf(stderr, "Usage: reference MODEL TOKENS GENERATE RESULT\n");
    return 2;
  }
  Transformer model;
  build_transformer(&model, argv[1], 0);
  FILE *input = fopen(argv[2], "rb");
  if (!input)
    return 2;
  int count;
  if (fread(&count, 4, 1, input) != 1 || count <= 0 || count > model.config.seq_len)
    return 2;
  int *tokens = calloc(model.config.seq_len, sizeof(int));
  if (fread(tokens, 4, count, input) != (size_t)count)
    return 2;
  fclose(input);
  int generate = atoi(argv[3]), produced = 0;
  FILE *result = fopen(argv[4], "w");
  if (!result)
    return 2;
  fprintf(result, "{\"prompt_tokens\":%d,\"generated\":[", count);
  double begin = (double)clock() / CLOCKS_PER_SEC;
  for (int pos = 0; pos < count + generate && pos < model.config.seq_len; pos++) {
    float *logits = forward(&model, tokens[pos], pos);
    int best = 0;
    for (int i = 1; i < model.config.vocab_size; i++)
      if (logits[i] > logits[best])
        best = i;
    if (pos >= count - 1) {
      if (produced++)
        fprintf(result, ",");
      fprintf(result, "%d", best);
      if (best == 151645 || best == 151643 || produced >= generate)
        break;
      tokens[pos + 1] = best;
    }
  }
  double seconds = (double)clock() / CLOCKS_PER_SEC - begin;
  fprintf(result, "],\"cpu_seconds\":%.9f,\"generated_count\":%d}\n", seconds,
          produced);
  fclose(result);
  free(tokens);
  free_transformer(&model);
  return 0;
}
