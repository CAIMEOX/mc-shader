package dev.caimeo.signal;

import com.google.gson.GsonBuilder;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import java.io.InputStreamReader;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import net.minecraft.client.Minecraft;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.resources.Identifier;
import net.minecraft.util.Mth;
import net.minecraft.world.scores.ScoreHolder;

/** Measures data-pack observations of equivalent rotation requests. */
public final class RotateExperiment {
  private final Map<String, Object> report = new LinkedHashMap<>();
  private final List<Map<String, Object>> samples = new ArrayList<>();
  private final List<Map<String, Object>> models = new ArrayList<>();
  private final List<Map<String, Object>> fpsSamples = new ArrayList<>();
  private JsonObject config;

  public void run(Minecraft minecraft) {
    var context = new ProbeContext(minecraft);
    var server = context.server();
    report.put("result", "running");
    report.put("experiment", "rotate");
    report.put("minecraft", "26.3");
    report.put("transport", "equivalent yaw / data-pack scheduled sampling");
    report.put("native_scheduling",
               System.getProperty("fabric.client.gametest") == null);
    report.put("observation_mode", "rotate");
    report.put("autonomous_window", true);
    report.put("samples", samples);
    report.put("models", models);
    report.put("fps_samples", fpsSamples);
    report.put("presentation", "visible Minecraft window");
    report.put("stage", System.getProperty("signal.rotateStage", "full"));
    try {
      check(Boolean.getBoolean("signal.stopwatchOnly"), "Timestamp observers excluded");
      check(System.getProperty("fabric.client.gametest") == null, "Native scheduling");
      try (var reader = new InputStreamReader(Objects.requireNonNull(
               getClass().getResourceAsStream("/experiment.json")))) {
        config = JsonParser.parseReader(reader).getAsJsonObject();
      }
      report.put("configuration", config);
      server.computeOnServer(s -> {
        minecraft.getSingleplayerServer().setWorldAllowCommands(true);
        return null;
      });
      server.runCommand("tag @a add signal.probe");
      server.runCommand("function signal:start");
      server.runCommand("function signal:rotate/stage");
      server.runCommand("difficulty peaceful");
      server.runCommand("scoreboard players reset * signal.rx");
      server.runCommand("scoreboard objectives setdisplay sidebar signal.rx");
      server.runCommand(
          "scoreboard objectives add signal.mine minecraft.mined:minecraft.stone");
      server.runCommand("time set noon");
      context.computeOnClient(mc -> {
        mc.options.enableVsync().set(false);
        mc.options.bobView().set(false);
        mc.options.framerateLimit().set(config.get("frame_limit").getAsInt());
        mc.options.pauseOnLostFocus = false;
        mc.options.inactivityFpsLimit().set(
            net.minecraft.client.InactivityFpsLimit.MINIMIZED);
        mc.getWindow().setTitle("Signal · rotation reply experiment");
        report.put("framebuffer", List.of(mc.gameRenderer.mainRenderTarget().width,
                                          mc.gameRenderer.mainRenderTarget().height));
        return null;
      });
      context.sleep(2000);
      int sequence = 1;
      var powers =
          Arrays
              .stream(System
                          .getProperty("signal.rotatePowers",
                                       System.getProperty("signal.power", "32"))
                          .split(","))
              .map(Integer::parseInt)
              .toList();
      report.put("powers", powers);
      for (var target : config.getAsJsonArray("tick_rates")) {
        int rate = target.getAsInt();
        server.runCommand("tick rate " + rate);
        for (double yaw :
             List.of(-179.0, -90.0, -1.0, -0.02, 0.0, 0.02, 1.0, 90.0, 179.0, 180.0)) {
          server.runCommand("tp @a[tag=signal.probe] 0.5 64 0.5 " + yaw + " 0");
          context.sleep(250);
          var sample =
              measure(context, server, "geometry", sequence++, 0, 0, rate, 300, 0, -1);
          sample.put("initial_yaw", yaw);
          @SuppressWarnings("unchecked")
          var geometry = (Map<String, Object>)sample.get("rotate");
          check(yaw == 0
                    ? value(geometry, "events") == 0 && value(geometry, "skips") > 0
                    : value(geometry, "events") >= 3,
                "Rotation marker responds at supported headings");
          persist();
        }
        for (int power : powers) {
          server.runCommand(
              "execute as @a[tag=signal.probe] at @s run rotate @s -90 0");
          context.sleep(250);
          if (Boolean.getBoolean("signal.rotateFps")) {
            for (int bit : List.of(0, 1)) {
              select(context, server, 700 + bit, bit, power);
              context.sleep(2500);
              int fps = context.computeOnClient(Minecraft::getFps);
              fpsSamples.add(
                  Map.of("tick_rate", rate, "power", power, "bit", bit, "fps", fps));
              persist();
            }
          }
          server.runCommand("function signal:rotate/training/reset");
          int trainingCount = report.get("stage").equals("probe")
                                  ? 8
                                  : config.get("training_windows").getAsInt();
          for (int i = 0; i < trainingCount; i++) {
            int bit = (i ^ (i >> 1)) & 1;
            measure(context, server, "training", sequence++, bit, power, rate, 500, bit,
                    -1);
            server.runCommand("function signal:rotate/training/" + bit);
          }
          server.runCommand("function signal:rotate/model");
          var model = snapshot(server);
          model.put("tick_rate", rate);
          model.put("power", power);
          models.add(model);
          verifyModel(rate, power, model);
          if (!report.get("stage").equals("probe")) {
            for (var element : config.getAsJsonArray("payload")) {
              var expected = element.getAsJsonObject();
              var sample = measure(context, server, "payload",
                                   expected.get("sequence").getAsInt(), 2, power, rate,
                                   500, expected.get("bit").getAsInt(),
                                   expected.get("digest").getAsLong());
              verifyDecode(sample, model);
            }
            if (Boolean.getBoolean("signal.rotateActivities") &&
                power == powers.getLast())
              runActivities(context, server, rate, power, model);
          }
          context.takeScreenshot("signal-rotate-" + rate + "-" + power);
        }
      }
      report.put("result", "passed");
    } catch (Throwable error) {
      report.put("result", "failed");
      report.put("failure", error.toString());
      try {
        context.takeScreenshot("signal-rotate-failure");
      } catch (Throwable ignored) {
      }
    } finally {
      try {
        context.computeOnClient(mc -> RotateControls.stop(mc));
        server.runCommand("function signal:rotate/stop");
        server.runCommand("tick rate 20");
        server.runCommand("execute as @a[tag=signal.probe] at @s run rotate @s -90 0");
        select(context, server, 1, 0, 0);
      } catch (Throwable ignored) {
      }
      persist();
      minecraft.execute(minecraft::stop);
    }
  }

  private Map<String, Object> measure(ProbeContext context,
                                      ProbeContext.ServerAccess server, String phase,
                                      int sequence, int mode, int power, int rate,
                                      int window, int bit, long digest) {
    return measure(context, server, phase, sequence, mode, power, rate, window, bit,
                   digest, "idle", true);
  }

  private void runActivities(ProbeContext context, ProbeContext.ServerAccess server,
                             int rate, int power, Map<String, Object> model) {
    for (var activity : List.of("walk", "turn", "jump", "mine")) {
      for (int bit : List.of(0, 1)) {
        prepareActivity(context, server, activity);
        measure(context, server, "control", 600 + bit, bit, power, rate, 1500, bit, -1,
                activity, false);
        prepareActivity(context, server, activity);
        measure(context, server, "behavior", 610 + bit, bit, power, rate, 1500, bit, -1,
                activity, true);
      }
      int[] count = new int[2];
      for (var element : config.getAsJsonArray("payload")) {
        var expected = element.getAsJsonObject();
        int bit = expected.get("bit").getAsInt();
        if (count[bit] >= 4)
          continue;
        count[bit]++;
        prepareActivity(context, server, activity);
        var sample = measure(context, server, "payload",
                             expected.get("sequence").getAsInt(), 2, power, rate, 500,
                             bit, expected.get("digest").getAsLong(), activity, true);
        verifyDecode(sample, model);
      }
      context.takeScreenshot("signal-rotate-" + rate + "-" + activity);
    }
  }

  private void prepareActivity(ProbeContext context, ProbeContext.ServerAccess server,
                               String activity) {
    server.runCommand("fill 2 65 0 5 65 0 minecraft:air strict");
    server.runCommand("tp @a[tag=signal.probe] 0.5 64 0.5 -90 0");
    if (activity.equals("mine")) {
      server.runCommand("fill 2 65 0 5 65 0 minecraft:stone strict");
      server.runCommand(
          "item replace entity @a[tag=signal.probe] weapon.mainhand with minecraft:iron_pickaxe");
    }
    context.sleep(200);
  }

  private Map<String, Object> measure(ProbeContext context,
                                      ProbeContext.ServerAccess server, String phase,
                                      int sequence, int mode, int power, int rate,
                                      int window, int bit, long digest, String activity,
                                      boolean enabled) {
    long start = System.nanoTime();
    server.runCommand("title @a actionbar " + new GsonBuilder().create().toJson(
                                                  "Rotate signal · " + phase + " · " +
                                                  rate + " TPS · " + sequence));
    var image = select(context, server, sequence, mode, power);
    if (digest >= 0)
      check(image.word(1) == digest, "GPU digest matches Haskell reference");
    check((mode == 2 ? (int)(image.word(1) & 1) : mode) == bit,
          "GPU result matches symbol");
    context.sleep(100);
    var clientBefore = clientSnapshot(context);
    int minedBefore = value(snapshot(server), "mined");
    context.computeOnClient(mc -> {
      RotateControls.start(mc, activity);
      return null;
    });
    server.runCommand("scoreboard players set #rotate_enabled signal " +
                      (enabled ? 1 : 0));
    server.runCommand("scoreboard players set #rotate_duration signal " + window);
    server.runCommand("function signal:rotate/start");
    long[] before =
        server.computeOnServer(s -> new long[] {s.getTickCount(), System.nanoTime()});
    Observation.begin();
    context.sleep(window);
    var state = snapshot(server);
    for (int attempts = 0; value(state, "collect") != 0 && attempts < 50; attempts++) {
      context.sleep(20);
      state = snapshot(server);
    }
    check(value(state, "collect") == 0, "Data pack completes its own window");
    var sample = Observation.finish();
    long[] after =
        server.computeOnServer(s -> new long[] {s.getTickCount(), System.nanoTime()});
    var events = server.computeOnServer(
        s
        -> s.getCommandStorage()
               .get(Identifier.parse("signal:rotate"))
               .getListOrEmpty("events")
               .stream()
               .map(tag -> {
                 var event = (CompoundTag)tag;
                 var values = new LinkedHashMap<String, Integer>();
                 for (var name : List.of("time_ms", "delay_ms", "armed_yaw",
                                         "reply_yaw", "on_ground"))
                   values.put(name, event.get(name).asInt().orElseThrow());
                 return values;
               })
               .toList());
    for (var stream : List.of("frame", "sent", "arrived", "handled", "server_tick"))
      check(((List<?>)sample.get(stream)).isEmpty(),
            "Timestamp observer excluded: " + stream);
    check(events.size() == value(state, "events"), "Reply event count");
    for (var event : events) {
      check(event.get("armed_yaw") < -180000000 || event.get("armed_yaw") >= 180000000,
            "Armed yaw is outside the packet range");
      check(event.get("reply_yaw") >= -180000000 && event.get("reply_yaw") < 180000000,
            "Received yaw is wrapped");
    }
    int feature = events.size() < 3
                      ? 0
                      : events.stream().mapToInt(e -> e.get("delay_ms")).sum() * 1000 /
                            events.size();
    check(value(state, "valid") == (events.size() >= 3 ? 1 : 0) &&
              value(state, "value") == feature,
          "Data-pack response feature matches structured events");
    check(value(state, "received") == value(state, "decoded"),
          "Player scoreboard contains the received symbol");
    var audit = context.computeOnClient(RotateControls::stop);
    var clientAfter = clientSnapshot(context);
    sample.put("phase", phase);
    sample.put("activity", activity);
    sample.put("probe_enabled", enabled);
    sample.put("input_audit", audit);
    sample.put("mined_blocks", value(snapshot(server), "mined") - minedBefore);
    check(value(state, "winding") == 0,
          "Probe winding compensated at window completion");
    sample.put("sequence", sequence);
    sample.put("mode", mode);
    sample.put("power", power);
    sample.put("bit", bit);
    sample.put("tick_rate", rate);
    sample.put("window_ms", window);
    sample.put("control_word", image.word(0));
    sample.put("gpu_digest", image.word(1));
    sample.put("rotate", state);
    sample.put("events", events);
    sample.put("client_before", clientBefore);
    sample.put("client_after", clientAfter);
    sample.put(
        "yaw_difference_degrees",
        Math.abs(Mth.wrapDegrees(((Number)clientAfter.get("yaw")).floatValue() -
                                 ((Number)clientBefore.get("yaw")).floatValue())));
    sample.put("position_change_blocks", distance(clientBefore, clientAfter));
    sample.put("scoreboard_received", state.get("received"));
    sample.put("observed_tps", (after[0] - before[0]) * 1e9 / (after[1] - before[1]));
    sample.put("trial_wall_ms", (System.nanoTime() - start) / 1e6);
    samples.add(sample);
    persist();
    return sample;
  }

  private Map<String, Object> clientSnapshot(ProbeContext context) {
    return context.computeOnClient(mc -> {
      var p = mc.player;
      return Map.of("x", p.getX(), "y", p.getY(), "z", p.getZ(), "yaw", p.getYRot(),
                    "pitch", p.getXRot(), "on_ground", p.onGround(), "health",
                    p.getHealth());
    });
  }

  private static double distance(Map<String, Object> a, Map<String, Object> b) {
    double square = 0;
    for (var axis : List.of("x", "y", "z")) {
      double delta =
          ((Number)a.get(axis)).doubleValue() - ((Number)b.get(axis)).doubleValue();
      square += delta * delta;
    }
    return Math.sqrt(square);
  }

  private Map<String, Object> snapshot(ProbeContext.ServerAccess server) {
    return server.computeOnServer(s -> {
      var scores = s.getScoreboard();
      var objective = scores.getObjective("signal");
      var state = new LinkedHashMap<String, Object>();
      for (var name : List.of("collect", "duration", "polls", "events", "arms", "skips",
                              "timeouts", "sum", "ground_polls", "valid", "value",
                              "ready", "center0", "center1", "threshold", "high_bit",
                              "decoded", "minimum_separation", "winding")) {
        var score = scores.getPlayerScoreInfo(
            ScoreHolder.forNameOnly("#rotate_" + name), objective);
        state.put(name, score == null ? 0 : score.value());
      }
      var player = s.getPlayerList().getPlayers().getFirst();
      var received =
          scores.getPlayerScoreInfo(player, scores.getObjective("signal.rx"));
      state.put("received", received == null ? -1 : received.value());
      var mined = scores.getPlayerScoreInfo(player, scores.getObjective("signal.mine"));
      state.put("mined", mined == null ? 0 : mined.value());
      return state;
    });
  }

  private void verifyModel(int rate, int power, Map<String, Object> model) {
    int[] total = new int[2], count = new int[2];
    for (var sample : samples) {
      if (!sample.get("phase").equals("training") ||
          value(sample, "tick_rate") != rate || value(sample, "power") != power)
        continue;
      @SuppressWarnings("unchecked")
      var state = (Map<String, Object>)sample.get("rotate");
      if (value(state, "valid") == 1) {
        total[value(sample, "bit")] += value(state, "value");
        count[value(sample, "bit")]++;
      }
    }
    if (count[0] == 0 || count[1] == 0) {
      check(value(model, "ready") == 0, "Insufficient calibration remains unresolved");
      return;
    }
    int a = total[0] / count[0], b = total[1] / count[1];
    check(value(model, "center0") == a && value(model, "center1") == b,
          "Calibration centers");
    check(value(model, "ready") ==
              (Math.abs(a - b) >= value(model, "minimum_separation") ? 1 : 0),
          "Calibration separation");
    if (value(model, "ready") == 1)
      check(value(model, "threshold") == (a + b) / 2, "Calibration midpoint");
  }

  private void verifyDecode(Map<String, Object> sample, Map<String, Object> model) {
    @SuppressWarnings("unchecked")
    var state = (Map<String, Object>)sample.get("rotate");
    int expected = -1;
    if (value(state, "valid") == 1 && value(model, "ready") == 1)
      expected = value(state, "value") > value(model, "threshold")
                     ? value(model, "high_bit")
                     : 1 - value(model, "high_bit");
    check(value(sample, "scoreboard_received") == expected, "Live calibrated decoder");
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
    throw new AssertionError("Shader receives request " + word);
  }

  private static int value(Map<String, Object> state, String name) {
    return ((Number)state.get(name)).intValue();
  }
  private static void check(boolean condition, String message) {
    if (!condition)
      throw new AssertionError(message);
  }
  private void persist() {
    try {
      Files.writeString(Path.of("signal-report.json"),
                        new GsonBuilder().setPrettyPrinting().create().toJson(report));
    } catch (Exception error) {
      throw new RuntimeException(error);
    }
  }
}
