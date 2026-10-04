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
import net.minecraft.resources.Identifier;

public final class TimingExperiment {
  private final Map<String, Object> report = new LinkedHashMap<>();
  private final List<Map<String, Object>> samples = new ArrayList<>();
  private JsonObject config;
  private int pilotSequence = 1;
  private final boolean stopwatchOnly = Boolean.getBoolean("signal.stopwatchOnly");

  public void run(Minecraft minecraft) {
    var context = new ProbeContext(minecraft);
    var server = context.server();
    report.put("result", "running");
    report.put("minecraft", "26.3");
    report.put("transport", "integrated server / local Netty channel");
    report.put("native_scheduling",
               System.getProperty("fabric.client.gametest") == null);
    report.put("samples", samples);
    report.put("observation_mode", stopwatchOnly ? "stopwatch_only" : "full");
    report.put("presentation", "visible Minecraft window");
    try {
      check(System.getProperty("fabric.client.gametest") == null,
            "Timing run uses the ordinary client scheduler");
      try (var reader = new InputStreamReader(Objects.requireNonNull(
               getClass().getResourceAsStream("/experiment.json")))) {
        config = JsonParser.parseReader(reader).getAsJsonObject();
      }
      report.put("configuration", config);
      server.computeOnServer(s -> {
        minecraft.getSingleplayerServer().setWorldAllowCommands(true);
        return null;
      });
      server.runCommand("gamemode spectator @a");
      server.runCommand("tp @a 0 69 10 180 30");
      server.runCommand("time set noon");
      server.runCommand("function signal:start");
      context.computeOnClient(mc -> {
        mc.options.renderDistance().set(3);
        mc.options.simulationDistance().set(5);
        mc.options.enableVsync().set(false);
        mc.options.bobView().set(false);
        mc.options.framerateLimit().set(config.get("frame_limit").getAsInt());
        mc.options.inactivityFpsLimit().set(
            net.minecraft.client.InactivityFpsLimit.MINIMIZED);
        mc.options.pauseOnLostFocus = false;
        mc.getWindow().setTitle("Signal · native client timing experiment");
        report.put("framebuffer", List.of(mc.gameRenderer.mainRenderTarget().width,
                                          mc.gameRenderer.mainRenderTarget().height));
        report.put("frame_limit", mc.getFramerateLimitTracker().getFramerateLimit());
        return null;
      });
      watch(context, 3.0);
      int fixedPower = Integer.getInteger("signal.power", -1);
      check(!stopwatchOnly || fixedPower >= 0,
            "Stopwatch-only runs require fixed workload power");
      int power = fixedPower >= 0 ? fixedPower : calibrate(context, server);
      check(power >= 0 && power <= 63, "Power is within the encoded range");
      report.put("power_selection", fixedPower >= 0 ? "fixed" : "calibrated");
      report.put("selected_power", power);
      report.put("iterations_per_heavy_fragment",
                 power * config.get("iterations_per_power").getAsInt());
      for (var rateValue : config.getAsJsonArray("tick_rates")) {
        int rate = rateValue.getAsInt();
        server.runCommand("tick rate " + rate);
        check(server.computeOnServer(s -> s.tickRateManager().tickrate()) == rate,
              "Server target tick rate applied");
        watch(context, 1.0);
        for (int i = 0; i < config.get("training_windows").getAsInt(); i++) {
          int mode = (i ^ (i >> 1)) & 1;
          measure(context, server, "training", pilotSequence++, mode, power, rate,
                  config.get("window_seconds").getAsDouble());
        }
        for (var value : config.getAsJsonArray("payload")) {
          var payload = value.getAsJsonObject();
          var sample =
              measure(context, server, "payload", payload.get("sequence").getAsInt(), 2,
                      power, rate, config.get("window_seconds").getAsDouble());
          check(((Number)sample.get("gpu_digest")).longValue() ==
                    payload.get("digest").getAsLong(),
                "GPU digest matches the Haskell reference");
          check(((Number)sample.get("bit")).intValue() == payload.get("bit").getAsInt(),
                "GPU bit matches the Haskell reference");
        }
        context.takeScreenshot("signal-rate-" + rate);
      }
      report.put("result", "passed");
    } catch (Throwable error) {
      report.put("result", "failed");
      report.put("failure", error.toString());
    } finally {
      try {
        server.runCommand("function signal:measure/stop");
        server.runCommand("tick rate 20");
        select(context, server, 1, 0, 0);
      } catch (Throwable ignored) {
      }
      persist();
      minecraft.execute(minecraft::stop);
    }
  }
  private int calibrate(ProbeContext context, ProbeContext.ServerAccess server) {
    measure(context, server, "pilot", pilotSequence++, 0, 0, 20, 1.5);
    int selected = 1;
    for (var value : config.getAsJsonArray("pilot_powers")) {
      selected = value.getAsInt();
      var sample =
          measure(context, server, "pilot", pilotSequence++, 1, selected, 20, 1.5);
      if (medianFrame(sample) >= config.get("target_frame_ms").getAsDouble())
        break;
    }
    report.put("calibration_frame_ms", medianFrame(samples.get(samples.size() - 1)));
    report.put("calibration_target_reached",
               medianFrame(samples.get(samples.size() - 1)) >=
                   config.get("target_frame_ms").getAsDouble());
    context.takeScreenshot("signal-calibration");
    return selected;
  }

  private Map<String, Object> measure(ProbeContext context,
                                      ProbeContext.ServerAccess server, String phase,
                                      int sequence, int mode, int power, int rate,
                                      double seconds) {
    server.runCommand("title @a actionbar " + new GsonBuilder().create().toJson(
                                                  "Signal · " + phase + " · " + rate +
                                                  " TPS target · sample " + sequence));
    var state = select(context, server, sequence, mode, power);
    watch(context, config.get("settle_seconds").getAsDouble());
    server.runCommand("function signal:measure/start");
    long[] before =
        server.computeOnServer(s -> new long[] {s.getTickCount(), System.nanoTime()});
    Observation.begin();
    watch(context, seconds);
    var sample = Observation.finish();
    long[] after =
        server.computeOnServer(s -> new long[] {s.getTickCount(), System.nanoTime()});
    server.runCommand("function signal:measure/stop");
    var intervals =
        server.computeOnServer(s
                               -> s.getCommandStorage()
                                      .get(Identifier.parse("signal:measurement"))
                                      .getListOrEmpty("intervals")
                                      .stream()
                                      .map(v -> v.asInt().orElseThrow())
                                      .toList());
    check(intervals.size() > 5, "Data pack stopwatch sampler is active");
    for (var name : List.of("frame", "sent", "arrived", "handled", "server_tick")) {
      int count = ((List<?>)sample.get(name)).size();
      check(stopwatchOnly ? count == 0 : count > 3,
            "Timing observer configuration: " + name);
    }
    double observedTps = (after[0] - before[0]) * 1e9 / (after[1] - before[1]);
    check(Double.isFinite(observedTps) && observedTps > 0,
          "Server tick observer is active");
    sample.put("rate_tracking", observedTps >= rate * .9 && observedTps <= rate * 1.1);
    sample.put("observed_tps", observedTps);
    sample.put("phase", phase);
    sample.put("sequence", sequence);
    sample.put("mode", mode);
    sample.put("power", power);
    sample.put("tick_rate", rate);
    sample.put("control_word", state.word(0));
    sample.put("gpu_digest", state.word(1));
    sample.put("bit", mode == 2 ? (int)(state.word(1) & 1) : mode);
    sample.put("stopwatch_intervals_ms", intervals);
    samples.add(sample);
    persist();
    return sample;
  }

  private GpuReadback.Image select(ProbeContext context,
                                   ProbeContext.ServerAccess server, int sequence,
                                   int mode, int power) {
    int word = sequence | (mode << 16) | (power << 18);
    server.runCommand("function signal:select {word:" + word + "}");
    for (int i = 0; i < 40; i++) {
      context.sleep(50);
      var image = GpuReadback.read(context, "state");
      if (image != null && image.word(0) == word)
        return image;
    }
    throw new AssertionError("Request reaches shader state: " + word);
  }

  private double medianFrame(Map<String, Object> sample) {
    @SuppressWarnings("unchecked") var frames = (List<Double>)sample.get("frame");
    var gaps = new ArrayList<Double>();
    for (int i = 1; i < frames.size(); i++)
      gaps.add(frames.get(i) - frames.get(i - 1));
    gaps.sort(Double::compare);
    return gaps.isEmpty() ? 0 : gaps.get(gaps.size() / 2);
  }

  private void watch(ProbeContext context, double seconds) {
    context.sleep((long)(seconds * 1000));
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
