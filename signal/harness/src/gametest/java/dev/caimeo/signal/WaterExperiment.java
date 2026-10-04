package dev.caimeo.signal;

import com.google.gson.GsonBuilder;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import java.io.InputStreamReader;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import net.minecraft.client.Minecraft;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.resources.Identifier;
import net.minecraft.world.scores.ScoreHolder;

/** Exercises a receiver implemented by data-pack functions and scoreboards. */
public final class WaterExperiment {
  private final Map<String, Object> report = new LinkedHashMap<>();
  private final List<Map<String, Object>> samples = new ArrayList<>();
  private final List<Map<String, Object>> models = new ArrayList<>();
  private final List<Map<String, Object>> series = new ArrayList<>();
  private JsonObject config;

  public void run(Minecraft minecraft) {
    var context = new ProbeContext(minecraft);
    var server = context.server();
    boolean speed = Boolean.getBoolean("signal.speed");
    boolean four = Boolean.getBoolean("signal.four");
    report.put("result", "running");
    report.put("experiment", four ? "water_four" : speed ? "water_speed" : "water");
    report.put("minecraft", "26.3");
    report.put("transport", "player position / data-pack scheduled sampling");
    report.put("native_scheduling",
               System.getProperty("fabric.client.gametest") == null);
    report.put("observation_mode", "water");
    report.put("autonomous_window", true);
    report.put("samples", samples);
    report.put("models", models);
    report.put("series", series);
    report.put("presentation", "visible Minecraft window");
    try {
      check(Boolean.getBoolean("signal.stopwatchOnly"),
            "Water receiver runs with timestamp mixins excluded");
      check(System.getProperty("fabric.client.gametest") == null, "Native scheduler");
      try (var reader = new InputStreamReader(Objects.requireNonNull(
               getClass().getResourceAsStream("/experiment.json")))) {
        config = JsonParser.parseReader(reader).getAsJsonObject();
      }
      report.put("configuration", config);
      int power = Integer.getInteger("signal.power", 32);
      check(power >= 0 && power <= 63, "Encoded workload power");
      if (four) {
        int maximumPower = 0;
        for (var level : config.getAsJsonArray("four_powers"))
          maximumPower = Math.max(maximumPower, level.getAsInt());
        report.put("maximum_iterations_per_fragment",
                   maximumPower * config.get("iterations_per_power").getAsInt());
      } else {
        report.put("selected_power", power);
        report.put("iterations_per_heavy_fragment",
                   power * config.get("iterations_per_power").getAsInt());
      }
      server.computeOnServer(s -> {
        minecraft.getSingleplayerServer().setWorldAllowCommands(true);
        return null;
      });
      server.runCommand("tag @a add signal.probe");
      server.runCommand("function signal:start");
      server.runCommand("function signal:water/stage");
      server.runCommand("scoreboard players reset * signal.rx");
      server.runCommand("scoreboard objectives setdisplay sidebar signal.rx");
      server.runCommand("time set noon");
      context.computeOnClient(mc -> {
        mc.options.enableVsync().set(false);
        mc.options.bobView().set(false);
        mc.options.framerateLimit().set(config.get("frame_limit").getAsInt());
        mc.options.pauseOnLostFocus = false;
        mc.options.inactivityFpsLimit().set(
            net.minecraft.client.InactivityFpsLimit.MINIMIZED);
        mc.getWindow().setTitle(speed || four
                                    ? "Signal · water channel speed experiment"
                                    : "Signal · water position receiver");
        report.put("framebuffer", List.of(mc.gameRenderer.mainRenderTarget().width,
                                          mc.gameRenderer.mainRenderTarget().height));
        report.put("frame_limit", mc.getFramerateLimitTracker().getFramerateLimit());
        return null;
      });
      context.sleep(3000);
      if (four)
        runFour(context, server);
      else if (speed)
        runSpeed(context, server, power);
      else
        runStandard(context, server, power);
      report.put("result", "passed");
    } catch (Throwable error) {
      report.put("result", "failed");
      report.put("failure", error.toString());
      try {
        context.takeScreenshot("signal-water-failure");
      } catch (Throwable ignored) {
      }
    } finally {
      try {
        server.runCommand("function signal:water/stop");
        server.runCommand("tick rate 20");
        select(context, server, 1, 0, 0);
      } catch (Throwable ignored) {
      }
      persist();
      minecraft.execute(minecraft::stop);
    }
  }

  private void runStandard(ProbeContext context, ProbeContext.ServerAccess server,
                           int power) {
    int sequence = 1;
    for (var target : config.getAsJsonArray("tick_rates")) {
      int rate = target.getAsInt();
      setRate(server, rate);
      server.runCommand("function signal:water/training/reset");
      for (int i = 0; i < config.get("training_windows").getAsInt(); i++) {
        int bit = (i ^ (i >> 1)) & 1;
        measure(context, server, "training", sequence++, bit, power, rate,
                standardTrial(bit));
        train(server, bit);
      }
      var model = finishModel(server, rate);
      for (var element : config.getAsJsonArray("payload")) {
        var expected = element.getAsJsonObject();
        var sample =
            measure(context, server, "payload", expected.get("sequence").getAsInt(), 2,
                    power, rate, standardTrial(expected.get("bit").getAsInt()));
        check(((Number)sample.get("gpu_digest")).longValue() ==
                  expected.get("digest").getAsLong(),
              "GPU digest matches Haskell reference");
        verifyDecode(sample, model);
      }
      context.takeScreenshot("signal-water-" + rate);
    }
  }

  private Trial standardTrial(int bit) {
    return new Trial(
        (int)(config.get("water_window_seconds").getAsDouble() * 1000), false, true,
        true, (long)(config.get("water_settle_seconds").getAsDouble() * 1000), bit, -1);
  }

  private void runSpeed(ProbeContext context, ProbeContext.ServerAccess server,
                        int power) {
    int sequence = 1;
    int guard =
        Integer.getInteger("signal.guardMs", config.get("speed_guard_ms").getAsInt());
    int blockSize = config.get("speed_block_symbols").getAsInt();
    check(guard >= 0 && guard <= 1000, "Guard interval range");
    report.put("guard_ms", guard);
    report.put("block_symbols", blockSize);
    report.put("estimator",
               "merge gaps below 20 ms; median of last three complete burst intervals");
    report.put(
        "gpu_verification",
        "Stable symbols and load scan: every request. Continuous blocks: first and last request, outside sampling.");
    for (var target : config.getAsJsonArray("tick_rates")) {
      int rate = target.getAsInt();
      setRate(server, rate);
      long calibrationStart = System.nanoTime();
      server.runCommand("function signal:water/training/reset");
      for (int i = 0; i < config.get("training_windows").getAsInt(); i++) {
        int bit = (i ^ (i >> 1)) & 1;
        measure(context, server, "training", sequence++, bit, power, rate,
                new Trial(config.get("speed_calibration_ms").getAsInt(), true, true,
                          true, 800, bit, -1));
        train(server, bit);
      }
      var model = finishModel(server, rate);
      model.put("calibration_wall_ms", elapsed(calibrationStart));
      for (var element : config.getAsJsonArray("speed_cases")) {
        var testCase = element.getAsJsonObject();
        boolean continuous = testCase.get("continuous").getAsBoolean();
        int window = testCase.get("window_ms").getAsInt();
        String filter = System.getProperty("signal.speedCases", "all");
        if (!filter.equals("all") &&
            !filter.equals(continuous ? "continuous" : "stable"))
          continue;
        int onlyWindow = Integer.getInteger("signal.windowMs", 0);
        if (onlyWindow != 0 && onlyWindow != window)
          continue;
        String id = rate + "/" + (continuous ? "continuous" : "stable") + "/" + window;
        var result = new LinkedHashMap<String, Object>();
        result.put("id", id);
        result.put("tick_rate", rate);
        result.put("continuous", continuous);
        result.put("window_ms", window);
        result.put("guard_ms", continuous ? guard : 0);
        result.put("block_symbols", continuous ? blockSize : 1);
        result.put("payload_symbols", testCase.getAsJsonArray("payload").size());
        series.add(result);
        long start = System.nanoTime();
        int index = 0;
        for (var item : testCase.getAsJsonArray("payload")) {
          var expected = item.getAsJsonObject();
          boolean blockStart = !continuous || index % blockSize == 0;
          int seq = expected.get("sequence").getAsInt();
          var sample = measure(context, server, "payload", seq, 2, power, rate,
                               new Trial(window, true, blockStart, blockStart,
                                         blockStart ? 800 : guard,
                                         expected.get("bit").getAsInt(),
                                         expected.get("digest").getAsLong()));
          sample.put("series", id);
          sample.put("block", index / (continuous ? blockSize : 1));
          sample.put("symbol_in_block", continuous ? index % blockSize : 0);
          verifyDecode(sample, model);
          index++;
          if (continuous && index % blockSize == 0) {
            var state = awaitSelection(context, seq | (2 << 16) | (power << 18));
            check(state.word(1) == expected.get("digest").getAsLong(),
                  "Final GPU result in continuous block");
            sample.put("block_final_gpu_digest", state.word(1));
          }
          persist();
        }
        result.put("wall_ms", elapsed(start));
        persist();
        context.takeScreenshot("signal-speed-" + rate + "-" +
                               (continuous ? "continuous" : "stable") + "-" + window);
      }
      if (!Boolean.getBoolean("signal.skipScan")) {
        var powers = config.getAsJsonArray("scan_powers");
        for (int repeat = 0; repeat < config.get("scan_repetitions").getAsInt();
             repeat++) {
          for (int i = 0; i < powers.size(); i++) {
            int scanPower = powers.get((i * 3 + repeat * 5) % powers.size()).getAsInt();
            var sample =
                measure(context, server, "scan", sequence++, 1, scanPower, rate,
                        new Trial(config.get("scan_window_ms").getAsInt(), true, true,
                                  true, 800, 1, -1));
            sample.put("repetition", repeat);
          }
        }
      }
      context.takeScreenshot("signal-speed-scan-" + rate);
    }
  }

  private void runFour(ProbeContext context, ProbeContext.ServerAccess server) {
    int sequence = 1;
    int guard = Integer.getInteger("signal.guardMs", 50);
    int window = config.get("scan_window_ms").getAsInt();
    report.put("estimator",
               "merge gaps below 20 ms; median of last three complete burst intervals");
    report.put("guard_ms", guard);
    report.put("bits_per_symbol", 2);
    report.put(
        "gpu_verification",
        "Stable symbols: every request. Continuous blocks: first and last request, outside sampling.");
    for (var target : config.getAsJsonArray("tick_rates")) {
      int rate = target.getAsInt();
      setRate(server, rate);
      long calibrationStart = System.nanoTime();
      server.runCommand("function signal:water/four/training/reset");
      for (int i = 0; i < 16; i++) {
        int level = (i * 3 + i / 4) % 4;
        int power = config.getAsJsonArray("four_powers").get(level).getAsInt();
        var sample = measure(context, server, "training_four", sequence++, 1, power,
                             rate, new Trial(window, true, true, true, 800, 1, -1));
        sample.put("training_level", level);
        server.runCommand("function signal:water/four/training/" + level);
      }
      server.runCommand("function signal:water/four/model");
      var model = snapshot(server);
      model.put("tick_rate", rate);
      model.put("calibration_wall_ms", elapsed(calibrationStart));
      models.add(model);
      verifyFourModel(rate, model);
      for (boolean continuous : List.of(false, true)) {
        String id =
            rate + "/four/" + (continuous ? "continuous" : "stable") + "/" + window;
        var result = new LinkedHashMap<String, Object>();
        result.put("id", id);
        result.put("tick_rate", rate);
        result.put("continuous", continuous);
        result.put("window_ms", window);
        result.put("guard_ms", continuous ? guard : 0);
        result.put("bits_per_symbol", 2);
        result.put("block_symbols", continuous ? 2 : 1);
        result.put("payload_symbols", config.getAsJsonArray("four_payload").size());
        series.add(result);
        long start = System.nanoTime();
        int index = 0;
        for (var element : config.getAsJsonArray("four_payload")) {
          var expected = element.getAsJsonObject();
          boolean blockStart = !continuous || index % 2 == 0;
          int seq = expected.get("sequence").getAsInt();
          var sample = measure(context, server, "payload", seq, 3, 0, rate,
                               new Trial(window, true, blockStart, blockStart,
                                         blockStart ? 800 : guard,
                                         expected.get("symbol").getAsInt(),
                                         expected.get("digest").getAsLong()));
          sample.put("series", id);
          sample.put("block", index / (continuous ? 2 : 1));
          sample.put("symbol_in_block", continuous ? index % 2 : 0);
          verifyDecode(sample, model);
          index++;
          if (continuous && index % 2 == 0) {
            var state = awaitSelection(context, seq | (3 << 16));
            check(state.word(1) == expected.get("digest").getAsLong(),
                  "Final GPU result in four-level block");
            sample.put("block_final_gpu_digest", state.word(1));
          }
          persist();
        }
        result.put("wall_ms", elapsed(start));
        persist();
        context.takeScreenshot("signal-four-" + rate + "-" +
                               (continuous ? "continuous" : "stable"));
      }
    }
  }

  private void verifyFourModel(int rate, Map<String, Object> model) {
    int[] sum = new int[4], count = new int[4], centers = new int[4];
    for (var sample : samples) {
      if (!sample.get("phase").equals("training_four") ||
          ((Number)sample.get("tick_rate")).intValue() != rate)
        continue;
      @SuppressWarnings("unchecked")
      var water = (Map<String, Object>)sample.get("water");
      if (((Number)water.get("valid")).intValue() != 1)
        continue;
      int level = ((Number)sample.get("training_level")).intValue();
      sum[level] += ((Number)water.get("value")).intValue();
      count[level]++;
    }
    for (int i = 0; i < 4; i++) {
      check(count[i] > 0, "All four calibration classes have samples");
      centers[i] = sum[i] / count[i];
      check(((Number)model.get("c" + i)).intValue() == centers[i],
            "Four-level calibration center");
    }
    boolean separated = true;
    for (int i = 0; i < 3; i++) {
      separated &= centers[i + 1] - centers[i] >= 5000;
      if (separated)
        check(((Number)model.get("cut" + i)).intValue() ==
                  (centers[i] + centers[i + 1]) / 2,
              "Four-level decision boundary");
    }
    check(((Number)model.get("ready")).intValue() == (separated ? 1 : 0),
          "Four-level model separation");
  }

  private void setRate(ProbeContext.ServerAccess server, int rate) {
    server.runCommand("tick rate " + rate);
    check(server.computeOnServer(s -> s.tickRateManager().tickrate()) == rate,
          "Target tick rate");
  }

  private void train(ProbeContext.ServerAccess server, int bit) {
    server.runCommand("function signal:water/training/" + (bit == 0 ? "zero" : "one"));
  }

  private Map<String, Object> finishModel(ProbeContext.ServerAccess server, int rate) {
    server.runCommand("function signal:water/model");
    var model = snapshot(server);
    model.put("tick_rate", rate);
    models.add(model);
    verifyModel(rate, model);
    return model;
  }

  private record Trial(int windowMs, boolean median, boolean reset, boolean verifyGpu,
                       long settleMs, int symbol, long digest) {}

  private Map<String, Object> measure(ProbeContext context,
                                      ProbeContext.ServerAccess server, String phase,
                                      int sequence, int mode, int power, int rate,
                                      Trial trial) {
    long start = System.nanoTime();
    server.runCommand("title @a actionbar " +
                      new GsonBuilder().create().toJson(
                          "Water signal · " + phase + " · " + rate + " TPS · " +
                          trial.windowMs() + " ms · " + sequence));
    if (trial.reset())
      server.runCommand("function signal:water/reset");
    int word = sequence | (mode << 16) | (power << 18);
    server.runCommand("function signal:select {word:" + word + "}");
    var state = trial.verifyGpu() ? awaitSelection(context, word) : null;
    if (state != null && trial.digest() >= 0)
      check(state.word(1) == trial.digest(), "GPU digest matches Haskell reference");
    context.sleep(trial.settleMs());
    var playerState = server.computeOnServer(s -> {
      var p = s.getPlayerList().getPlayers().getFirst();
      return Map.of("flying", p.getAbilities().flying, "passenger", p.isPassenger(),
                    "in_water", p.isInWater(), "x", p.getX(), "y", p.getY());
    });
    check(Boolean.FALSE.equals(playerState.get("flying")) &&
              Boolean.FALSE.equals(playerState.get("passenger")),
          "Player uses ordinary fluid physics");
    check(Boolean.TRUE.equals(playerState.get("in_water")),
          "Player is in the water trough");
    server.runCommand("scoreboard players set #water_duration signal " +
                      trial.windowMs());
    server.runCommand("scoreboard players set #water_stat signal " +
                      (trial.median() ? 1 : 0));
    server.runCommand("function signal:water/start");
    long[] before =
        server.computeOnServer(s -> new long[] {s.getTickCount(), System.nanoTime()});
    Observation.begin();
    context.sleep(trial.windowMs());
    Map<String, Object> water = snapshot(server);
    for (int attempts = 0;
         ((Number)water.get("collect")).intValue() != 0 && attempts < 50; attempts++) {
      context.sleep(20);
      water = snapshot(server);
    }
    check(((Number)water.get("collect")).intValue() == 0,
          "Data pack finishes and decodes its own stopwatch window");
    var sample = Observation.finish();
    long[] after =
        server.computeOnServer(s -> new long[] {s.getTickCount(), System.nanoTime()});
    var events = server.computeOnServer(
        s
        -> s.getCommandStorage()
               .get(Identifier.parse("signal:water"))
               .getListOrEmpty("events")
               .stream()
               .map(tag -> {
                 var event = (CompoundTag)tag;
                 var values = new LinkedHashMap<String, Integer>();
                 for (var name : List.of("time_ms", "gap_ms", "dx_microblocks",
                                         "x_microblocks", "moving"))
                   values.put(name, event.get(name).asInt().orElseThrow());
                 return values;
               })
               .toList());
    for (var name : List.of("frame", "sent", "arrived", "handled", "server_tick"))
      check(((List<?>)sample.get(name)).isEmpty(),
            "Timestamp observer excluded: " + name);
    check(!events.isEmpty(),
          "Scheduled data-pack sampler observes automatic position changes");
    check(events.stream().allMatch(event -> event.get("dx_microblocks") > 0),
          "Water advances the player along the trough");
    check(events.getLast().get("x_microblocks") < 7_000_000,
          "Player has space to move throughout sampling");
    Integer feature = feature(events, trial.median());
    check(((Number)water.get("valid")).intValue() == (feature == null ? 0 : 1),
          "Data-pack feature validity");
    check(((Number)water.get("value")).intValue() == (feature == null ? 0 : feature),
          "Data-pack interval feature matches structured events");
    sample.put("events", events);
    sample.put("water", water);
    sample.put("player_state", playerState);
    sample.put("phase", phase);
    sample.put("sequence", sequence);
    sample.put("mode", mode);
    sample.put("power", power);
    sample.put("tick_rate", rate);
    sample.put("window_ms", trial.windowMs());
    sample.put("estimator", trial.median() ? "burst_median" : "mean");
    sample.put("reset", trial.reset());
    sample.put("settle_ms", trial.settleMs());
    sample.put("gpu_verified", state != null);
    sample.put("control_word", word);
    if (state != null) {
      sample.put("gpu_digest", state.word(1));
      check((mode >= 2 ? (int)(state.word(1) & (mode == 3 ? 3 : 1)) : mode) ==
                trial.symbol(),
            "GPU result matches expected symbol");
    }
    if (trial.digest() >= 0)
      sample.put("reference_digest", trial.digest());
    sample.put("symbol", trial.symbol());
    if (mode != 3)
      sample.put("bit", trial.symbol());
    sample.put("decoded", water.get("decoded"));
    sample.put("scoreboard_received", water.get("received"));
    check(water.get("decoded").equals(water.get("received")),
          "Player signal.rx contains the data-pack result");
    sample.put("observed_tps", (after[0] - before[0]) * 1e9 / (after[1] - before[1]));
    sample.put("trial_wall_ms", elapsed(start));
    samples.add(sample);
    persist();
    return sample;
  }

  private static Integer feature(List<LinkedHashMap<String, Integer>> events,
                                 boolean robust) {
    if (!robust)
      return events.size() < 4
          ? null
          : (events.getLast().get("time_ms") - events.getFirst().get("time_ms")) *
                1000 / (events.size() - 1);
    var starts = new ArrayList<Integer>();
    Integer previous = null;
    for (var event : events) {
      int time = event.get("time_ms");
      if (previous == null || time - previous >= 20)
        starts.add(time);
      previous = time;
    }
    if (starts.size() < 4)
      return null;
    int n = starts.size();
    int a = starts.get(n - 1) - starts.get(n - 2);
    int b = starts.get(n - 2) - starts.get(n - 3);
    int c = starts.get(n - 3) - starts.get(n - 4);
    return (a + b + c - Math.min(a, Math.min(b, c)) - Math.max(a, Math.max(b, c))) *
        1000;
  }

  private Map<String, Object> snapshot(ProbeContext.ServerAccess server) {
    return server.computeOnServer(s -> {
      var scores = s.getScoreboard();
      var objective = scores.getObjective("signal");
      var values = new LinkedHashMap<String, Object>();
      for (var name : List.of("collect", "polls", "moving_polls", "events", "intervals",
                              "gap_sum", "groups", "group_intervals", "g1", "g2", "g3",
                              "duration", "stat", "value", "valid", "ready", "center0",
                              "center1", "threshold", "high_bit", "decoded", "alphabet",
                              "c0", "c1", "c2", "c3", "cut0", "cut1", "cut2")) {
        var score = scores.getPlayerScoreInfo(ScoreHolder.forNameOnly("#water_" + name),
                                              objective);
        values.put(name, score == null ? 0 : score.value());
      }
      var player = s.getPlayerList().getPlayers().getFirst();
      var received =
          scores.getPlayerScoreInfo(player, scores.getObjective("signal.rx"));
      values.put("received", received == null ? -1 : received.value());
      return values;
    });
  }

  private void verifyModel(int rate, Map<String, Object> model) {
    int[] total = new int[2], count = new int[2];
    for (var sample : samples)
      if (sample.get("phase").equals("training") &&
          ((Number)sample.get("tick_rate")).intValue() == rate) {
        int bit = ((Number)sample.get("bit")).intValue();
        @SuppressWarnings("unchecked")
        var water = (Map<String, Object>)sample.get("water");
        if (((Number)water.get("valid")).intValue() == 1) {
          total[bit] += ((Number)water.get("value")).intValue();
          count[bit]++;
        }
      }
    check(count[0] > 0 && count[1] > 0,
          "Both calibration symbols produce valid observations");
    int center0 = total[0] / count[0], center1 = total[1] / count[1];
    check(((Number)model.get("center0")).intValue() == center0 &&
              ((Number)model.get("center1")).intValue() == center1,
          "Data-pack calibration centers");
    if (Math.abs(center1 - center0) >= 5000)
      check(((Number)model.get("threshold")).intValue() == (center0 + center1) / 2,
            "Data-pack calibrated threshold");
  }

  private void verifyDecode(Map<String, Object> sample, Map<String, Object> model) {
    @SuppressWarnings("unchecked") var water = (Map<String, Object>)sample.get("water");
    int expected = -1;
    if (((Number)model.get("ready")).intValue() == 1 &&
        ((Number)water.get("valid")).intValue() == 1) {
      if (((Number)water.get("alphabet")).intValue() == 4) {
        int level = 0;
        for (int i = 0; i < 3; i++)
          if (((Number)water.get("value")).intValue() >
              ((Number)model.get("cut" + i)).intValue())
            level++;
        expected = level ^ (level >> 1);
      } else {
        int high = ((Number)model.get("high_bit")).intValue();
        expected = ((Number)water.get("value")).intValue() >
                           ((Number)model.get("threshold")).intValue()
                       ? high
                       : 1 - high;
      }
    }
    check(((Number)sample.get("decoded")).intValue() == expected,
          "Data-pack decoder follows its calibrated model");
  }

  private GpuReadback.Image select(ProbeContext context,
                                   ProbeContext.ServerAccess server, int sequence,
                                   int mode, int power) {
    int word = sequence | (mode << 16) | (power << 18);
    server.runCommand("function signal:select {word:" + word + "}");
    return awaitSelection(context, word);
  }

  private GpuReadback.Image awaitSelection(ProbeContext context, int word) {
    for (int i = 0; i < 40; i++) {
      context.sleep(50);
      var image = GpuReadback.read(context, "state");
      if (image != null && image.word(0) == word)
        return image;
    }
    throw new AssertionError("Shader receives request " + word);
  }

  private static double elapsed(long start) {
    return (System.nanoTime() - start) / 1e6;
  }

  private void persist() {
    try {
      Files.writeString(Path.of("signal-report.json"),
                        new GsonBuilder().setPrettyPrinting().create().toJson(report));
    } catch (Exception e) {
      throw new RuntimeException(e);
    }
  }
  private static void check(boolean condition, String message) {
    if (!condition)
      throw new AssertionError(message);
  }
}
