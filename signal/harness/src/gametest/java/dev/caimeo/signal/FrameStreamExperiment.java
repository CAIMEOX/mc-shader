package dev.caimeo.signal;

import com.google.gson.GsonBuilder;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import java.io.InputStreamReader;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import net.minecraft.client.Minecraft;
import net.minecraft.core.BlockPos;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.resources.Identifier;
import net.minecraft.world.scores.ScoreHolder;
import net.minecraft.world.level.block.Blocks;
import org.lwjgl.sdl.SDLVideo;

/** Compares data-pack observables while a shared shader advances its own bitstream. */
public final class FrameStreamExperiment {
  public enum Channel {
    FALL("fall", "fall", "Free fall"),
    ROTATION("rstream", "rotate_stream", "Rotation stream");
    final String key, experiment, label;
    Channel(String key, String experiment, String label) {
      this.key = key;
      this.experiment = experiment;
      this.label = label;
    }
  }
  private final Channel channel;
  private final String key;
  public FrameStreamExperiment(Channel channel) {
    this.channel = channel;
    this.key = channel.key;
  }

  private final Map<String, Object> report = new LinkedHashMap<>();
  private final List<Map<String, Object>> pilots = new ArrayList<>();
  private final List<Map<String, Object>> trials = new ArrayList<>();
  private int epoch;
  private boolean observing;

  public void run(Minecraft minecraft) {
    var context = new ProbeContext(minecraft);
    var server = context.server();
    report.put("result", "running");
    report.put("experiment", channel.experiment);
    report.put("minecraft", "26.3");
    report.put("native_scheduling",
               System.getProperty("fabric.client.gametest") == null);
    report.put("presentation", "visible Minecraft window");
    report.put("gpu_readback_during_sampling", false);
    report.put("driver",
               "one stream request; data-pack tick-gap decoding; read-only polling");
    report.put("pilots", pilots);
    report.put("trials", trials);
    try {
      check(Boolean.getBoolean("signal.stopwatchOnly"), "Timestamp observers excluded");
      check(System.getProperty("fabric.client.gametest") == null, "Native scheduling");
      JsonObject config;
      try (var reader = new InputStreamReader(Objects.requireNonNull(
               getClass().getResourceAsStream("/experiment.json")))) {
        config = JsonParser.parseReader(reader).getAsJsonObject();
      }
      report.put("configuration", config);
      server.computeOnServer(s -> {
        minecraft.getSingleplayerServer().setWorldAllowCommands(true);
        return null;
      });
      server.runCommand("tick rate 200");
      server.runCommand("difficulty peaceful");
      server.runCommand("time set noon");
      server.runCommand("weather clear");
      server.runCommand("kill @e[tag=signal.carrier]");
      server.runCommand("tag @a remove signal." + key + ".owner");
      server.runCommand("tag @a[limit=1] add signal." + key + ".owner");
      server.runCommand("scoreboard objectives setdisplay sidebar signal.rx");
      if (channel == Channel.ROTATION)
        server.runCommand(
            "scoreboard objectives add signal.mine minecraft.mined:minecraft.stone");
      context.computeOnClient(mc -> {
        mc.options.enableVsync().set(false);
        mc.options.bobView().set(false);
        mc.options.framerateLimit().set(120);
        mc.options.pauseOnLostFocus = false;
        mc.options.inactivityFpsLimit().set(
            net.minecraft.client.InactivityFpsLimit.MINIMIZED);
        mc.getWindow().setTitle("Signal · " + channel.label);
        report.put("framebuffer", List.of(mc.gameRenderer.mainRenderTarget().width,
                                          mc.gameRenderer.mainRenderTarget().height));
        return null;
      });
      if (System.getProperty("signal.streamStage", "full").equals("controls")) {
        verifyMiningInput(context, server);
        report.put("result", "passed");
        return;
      }
      for (var value : config.getAsJsonArray("pilot_powers")) {
        int power = value.getAsInt();
        announce(server, channel.label + " · calibrating power " + power);
        var sample = measure(context, server, false, power, power, 0, "idle");
        sample.put("power", power);
        summarizePilot(sample);
        pilots.add(sample);
        System.out.println(channel.label + " power " + power + ": " +
                           sample.get("median_ms") + " ms");
        persist();
      }
      var low = nearest(60, 55);
      var high = nearest(100, number(low, "median_ms") + 20);
      int lowPower = value(low, "power"), highPower = value(high, "power");
      var sync = pilots.stream()
                     .filter(p -> value(p, "power") == 63)
                     .findFirst()
                     .orElseThrow();
      int threshold = (int)Math.round(
          (number(low, "median_ticks") + number(high, "median_ticks")) / 2);
      int syncThreshold = (int)Math.round(
          (number(high, "median_ticks") + number(sync, "median_ticks")) / 2);
      check(number(sync, "median_ticks") - number(high, "median_ticks") >= 6,
            "Delimiter separated from data");
      report.put("calibration",
                 Map.of("low_power", lowPower, "high_power", highPower, "low_ms",
                        number(low, "median_ms"), "high_ms", number(high, "median_ms"),
                        "sync_ms", number(sync, "median_ms"), "threshold_ticks",
                        threshold, "sync_ticks", syncThreshold));
      server.runCommand("scoreboard players set #" + key + "_threshold signal " +
                        threshold);
      server.runCommand("scoreboard players set #" + key + "_sync signal " +
                        syncThreshold);
      for (var entry : config.getAsJsonArray("patterns"))
        transmit(context, server, entry.getAsJsonObject(), lowPower, highPower, "idle");
      if (channel == Channel.ROTATION && Boolean.getBoolean("signal.rotateActivities"))
        for (var activity : List.of("walk", "turn", "jump", "mine"))
          transmit(context, server,
                   config.getAsJsonArray("patterns").get(3).getAsJsonObject(), lowPower,
                   highPower, activity);
      context.takeScreenshot("signal-" + key + "-complete");
      report.put("result", "passed");
    } catch (Throwable error) {
      report.put("result", "failed");
      report.put("failure", error.toString());
      error.printStackTrace();
      try {
        context.takeScreenshot("signal-" + key + "-failure");
      } catch (Throwable ignored) {
      }
    } finally {
      if (observing)
        report.put("observations", Observation.finish());
      try {
        if (channel == Channel.ROTATION)
          context.computeOnClient(RotateControls::stop);
        server.runCommand("function signal:" + key + "/stop");
        server.runCommand("posteffect remove @a signal:" + key);
        server.runCommand("kill @e[tag=signal." + key + ".carrier]");
        server.runCommand("gamemode spectator @a");
        server.runCommand("tp @a 0.5 70 0.5 -90 30");
        server.runCommand("tick rate 20");
      } catch (Throwable ignored) {
      }
      persist();
      minecraft.execute(minecraft::stop);
    }
  }

  private void transmit(ProbeContext context, ProbeContext.ServerAccess server,
                        JsonObject pattern, int lowPower, int highPower,
                        String activity) {
    String name = pattern.get("name").getAsString();
    announce(server, channel.label + " · 64 shader bits · " + name + " · " + activity);
    var sample = measure(context, server, true, lowPower, highPower,
                         pattern.get("id").getAsInt(), activity);
    var expected = pattern.getAsJsonArray("expected_bits")
                       .asList()
                       .stream()
                       .map(v -> v.getAsInt())
                       .toList();
    sample.put("pattern", name);
    sample.put("expected_bits", expected);
    sample.put("exact", sample.get("status").equals("complete") &&
                            sample.get("bits").equals(expected));
    trials.add(sample);
    persist();
    System.out.println(channel.label + " " + name + " " + activity + ": " +
                       sample.get("status") + ", " +
                       ((List<?>)sample.get("bits")).size() +
                       " bits, exact=" + sample.get("exact"));
  }

  private void prepareMining(ProbeContext.ServerAccess server) {
    server.runCommand("fill 2 65 0 5 65 0 minecraft:stone strict");
    server.runCommand(
        "item replace entity @a[tag=signal.rstream.owner] weapon.mainhand with minecraft:iron_pickaxe");
  }

  private Map<String, Object> miningInput(Minecraft mc) {
    return Map.of("window_active", mc.isWindowActive(), "mouse_grabbed",
                  mc.mouseHandler.isMouseGrabbed(), "attack_down",
                  mc.options.keyAttack.isDown(), "hit",
                  mc.hitResult == null ? "null" : mc.hitResult.getType().toString(),
                  "destroying", mc.gameMode.isDestroying(), "destroy_stage",
                  mc.gameMode.getDestroyStage());
  }

  private void prepareMiningInput(ProbeContext context) {
    context.computeOnClient(mc -> {
      SDLVideo.SDL_RaiseWindow(mc.getWindow().handle());
      return null;
    });
    for (int attempt = 0;
         attempt < 40 && !context.computeOnClient(Minecraft::isWindowActive); attempt++)
      context.sleep(50);
    context.computeOnClient(mc -> {
      mc.mouseHandler.grabMouse();
      return null;
    });
    context.sleep(100);
    check(context.computeOnClient(
              mc -> mc.isWindowActive() && mc.mouseHandler.isMouseGrabbed()),
          "Mining starts with the visible game window focused and its mouse captured");
  }

  private void verifyMiningInput(ProbeContext context,
                                 ProbeContext.ServerAccess server) {
    var controls = new LinkedHashMap<String, Object>();
    report.put("controls", controls);
    for (boolean probe : List.of(false, true)) {
      server.runCommand("function signal:rstream/setup");
      prepareMining(server);
      select(server, request(20, 32, 0, false));
      context.sleep(700);
      context.computeOnClient(mc -> {
        mc.mouseHandler.releaseMouse();
        return null;
      });
      prepareMiningInput(context);
      var result = new LinkedHashMap<String, Object>();
      controls.put(probe ? "probe" : "control", result);
      var before = snapshot(server);
      result.put("before", before);
      result.put("input_before", context.computeOnClient(this::miningInput));
      context.computeOnClient(mc -> {
        RotateControls.start(mc, "mine");
        return null;
      });
      if (probe) {
        server.runCommand("scoreboard players set #rstream_stream signal 0");
        server.runCommand("scoreboard players set #rstream_duration signal 2000");
        server.runCommand("function signal:rstream/start");
      }
      context.sleep(2200);
      var after = snapshot(server);
      result.put("after", after);
      result.put("input_after", context.computeOnClient(this::miningInput));
      result.put("audit", context.computeOnClient(RotateControls::stop));
      persist();
      check(value(after, "stone_targets") < 4 &&
                value(after, "mined") > value(before, "mined"),
            "Mining input breaks the target blocks");
    }
  }

  private Map<String, Object> nearest(double target, double minimum) {
    return pilots.stream()
        .filter(p
                -> value(p, "power") > 0 && value(p, "power") < 63 &&
                       number(p, "median_ms") >= minimum)
        .min(Comparator.comparingDouble(p -> Math.abs(number(p, "median_ms") - target)))
        .orElseThrow();
  }

  private Map<String, Object> measure(ProbeContext context,
                                      ProbeContext.ServerAccess server, boolean stream,
                                      int low, int high, int pattern, String activity) {
    server.runCommand("function signal:" + key + "/setup");
    if (activity.equals("mine"))
      prepareMining(server);
    int holdWord = request(low, high, 0, false);
    select(server, holdWord);
    context.sleep(700);
    var ready = GpuReadback.readBatch(context, "signal:" + key, List.of("state"));
    check(ready != null && ready.get("state").word(0) == holdWord,
          "GPU received the setup request before sampling");
    check((ready.get("state").word(1) & 63) == low, "GPU workload power");
    server.runCommand("scoreboard players set #" + key + "_stream signal " +
                      (stream ? 1 : 0));
    server.runCommand("scoreboard players set #" + key + "_min_gap signal " +
                      (channel == Channel.ROTATION && !stream ? 1 : 4));
    int duration = stream ? 15000 : 2000;
    server.runCommand("scoreboard players set #" + key + "_duration signal " +
                      duration);
    var before = snapshot(server);
    double startY = number(before, "end_y");
    if (activity.equals("mine"))
      prepareMiningInput(context);
    if (channel == Channel.ROTATION)
      context.computeOnClient(mc -> {
        RotateControls.start(mc, activity);
        return null;
      });
    Observation.begin();
    observing = true;
    server.runCommand("function signal:" + key + "/start");
    int word = stream ? request(low, high, pattern, true) : holdWord;
    if (stream)
      select(server, word);
    Map<String, Object> state = snapshot(server);
    check(value(state, "active") == 1, "Data pack starts sampling");
    long deadline = System.nanoTime() + (duration + 5000L) * 1000000L;
    while (value(state, "active") == 1 && System.nanoTime() < deadline) {
      context.sleep(250);
      state = snapshot(server);
    }
    var observations = Observation.finish();
    observing = false;
    for (var name : List.of("frame", "sent", "arrived", "handled", "server_tick"))
      check(((List<?>)observations.get(name)).isEmpty(),
            "Timestamp stream excluded: " + name);
    check(value(state, "active") == 0, "Data pack ends sampling autonomously");
    check(value(state, "changes") > 5, "Receiver observes client updates");
    if (channel == Channel.FALL) {
      check(number(state, "end_y") < startY, "Falling produces position changes");
      check(value(state, "upward") == 0 && value(state, "ground_polls") == 0,
            "Continuous airborne descent during sampling");
    } else {
      var input = context.computeOnClient(RotateControls::stop);
      state.put("input_audit", input);
      double distance =
          Math.sqrt(Math.pow(number(state, "end_x") - number(before, "end_x"), 2) +
                    Math.pow(number(state, "end_y") - startY, 2) +
                    Math.pow(number(state, "end_z") - number(before, "end_z"), 2));
      state.put("position_change_blocks", distance);
      if (activity.equals("idle") || activity.equals("turn"))
        check(distance < 0.001, "Rotation probing preserves player position");
      if (activity.equals("walk"))
        check(distance > 1, "Walking input moves the player during reception");
      if (activity.equals("jump"))
        check(number(input, "vertical_range_blocks") > 0.5,
              "Jump input produces airborne movement");
      state.put("mined_blocks", value(state, "mined") - value(before, "mined"));
      state.put("activity", activity);
      report.put("latest", state);
      if (activity.equals("mine"))
        check(value(state, "mined_blocks") > 0,
              "Mining input breaks a block during reception");
      check(value(state, "winding") == 0 && value(state, "waiting") == 0,
            "Rotation winding is compensated after reception");
    }
    state.put("activity", activity);
    state.put("start_y", startY);
    state.put("word", word);
    state.put("low_power", low);
    state.put("high_power", high);
    state.put("observations", observations);
    state.put("observed_tps", value(state, "ticks") * 1000.0 / value(state, "now"));
    verifyReceiver(state);
    var finalGpu = GpuReadback.readBatch(context, "signal:" + key, List.of("state"));
    if (finalGpu != null)
      state.put("shader_frame_after_sampling", finalGpu.get("state").word(1) >> 6);
    return state;
  }

  private void verifyReceiver(Map<String, Object> state) {
    var events = records(state, "events");
    check(events.size() == value(state, "changes"), "Observable event count");
    int previousTick = 0, previousMs = 0;
    Map<String, Integer> groupStart = null;
    var grouped = new ArrayList<Map<String, Integer>>();
    for (var event : events) {
      check(event.get("gap_ticks") == event.get("tick") - previousTick &&
                event.get("gap_ms") == event.get("time_ms") - previousMs,
            "Data-pack tick and stopwatch intervals");
      if (channel == Channel.FALL)
        check(event.get("dy") < 0, "Each recorded position change is downward");
      else {
        int armed = event.get("armed_yaw"), reply = event.get("reply_yaw");
        check((armed < -180000000 || armed >= 180000000) && reply >= -180000000 &&
                  reply < 180000000,
              "Unwrapped marker returns to the normalized angle range");
      }
      if (groupStart == null)
        groupStart = event;
      else if (event.get("gap_ticks") >= value(state, "min_gap")) {
        grouped.add(Map.of("time_ms", event.get("time_ms"), "tick", event.get("tick"),
                           "gap_ms", event.get("time_ms") - groupStart.get("time_ms"),
                           "gap_ticks", event.get("tick") - groupStart.get("tick")));
        groupStart = event;
      }
      previousTick = event.get("tick");
      previousMs = event.get("time_ms");
    }
    check(grouped.equals(state.get("intervals")),
          "Data-pack burst grouping matches observed events");
    var received = (List<?>)state.get("bits");
    check(received.size() == value(state, "bit_count"), "Live bit count");
    if (!received.isEmpty())
      check(received.getLast().equals(state.get("scoreboard_received")),
            "Last decoded bit is visible in the player's scoreboard");
    var predicted = new ArrayList<Integer>();
    boolean active = false;
    for (var event : records(state, "intervals")) {
      int gap = event.get("gap_ticks");
      if (gap >= value(state, "sync")) {
        if (active)
          break;
        active = true;
      } else if (active)
        predicted.add(gap >= value(state, "threshold") ? 1 : 0);
    }
    if (value(state, "stream") == 1)
      check(predicted.equals(state.get("bits")),
            "Live data-pack decisions match observed tick gaps");
  }

  private int request(int low, int high, int pattern, boolean stream) {
    return low | (high << 6) | (pattern << 12) | (stream ? 1 << 14 : 0) |
        (++epoch << 16);
  }

  private void select(ProbeContext.ServerAccess server, int word) {
    server.runCommand("data modify storage signal:" + key + " control.word set value " +
                      word);
    server.runCommand("function signal:" + key + "/send with storage signal:" + key +
                      " control");
  }

  private Map<String, Object> snapshot(ProbeContext.ServerAccess server) {
    return server.computeOnServer(s -> {
      var out = new LinkedHashMap<String, Object>();
      var data = s.getCommandStorage().get(Identifier.parse("signal:" + key));
      out.put("status", data.getStringOr("status", ""));
      out.put("bits", data.getListOrEmpty("bits")
                          .stream()
                          .map(v -> v.asInt().orElseThrow())
                          .toList());
      for (var list : List.of("events", "intervals")) {
        var keys =
            list.equals("events")
                ? (channel == Channel.FALL
                       ? List.of("time_ms", "tick", "gap_ms", "gap_ticks", "y", "dy")
                       : List.of("time_ms", "tick", "gap_ms", "gap_ticks", "armed_yaw",
                                 "reply_yaw", "delay_ticks"))
                : List.of("time_ms", "tick", "gap_ms", "gap_ticks");
        out.put(list, data.getListOrEmpty(list)
                          .stream()
                          .map(tag -> {
                            var entry = (CompoundTag)tag;
                            var result = new LinkedHashMap<String, Integer>();
                            for (var key : keys)
                              result.put(key, entry.getIntOr(key, 0));
                            return result;
                          })
                          .toList());
      }
      var board = s.getScoreboard();
      var objective = board.getObjective("signal");
      for (var name :
           List.of("active", "ticks", "now", "changes", "groups", "ground_polls",
                   "upward", "threshold", "sync", "stream", "phase", "started_ms",
                   "ended_ms", "bit_count", "min_gap", "winding", "waiting", "skips")) {
        var score = board.getPlayerScoreInfo(
            ScoreHolder.forNameOnly("#" + key + "_" + name), objective);
        out.put(name, score == null ? 0 : score.value());
      }
      var player = s.getPlayerList().getPlayers().getFirst();
      out.put("end_y", player.getY());
      out.put("end_x", player.getX());
      out.put("end_z", player.getZ());
      var minedObjective = board.getObjective("signal.mine");
      var mined = minedObjective == null
                      ? null
                      : board.getPlayerScoreInfo(player, minedObjective);
      out.put("mined", mined == null ? 0 : mined.value());
      int stoneTargets = 0;
      for (int x = 2; x <= 5; x++)
        if (s.overworld().getBlockState(new BlockPos(x, 65, 0)).is(Blocks.STONE))
          stoneTargets++;
      out.put("stone_targets", stoneTargets);
      var received = board.getPlayerScoreInfo(s.getPlayerList().getPlayers().getFirst(),
                                              board.getObjective("signal.rx"));
      out.put("scoreboard_received", received == null ? -1 : received.value());
      return out;
    });
  }

  private void summarizePilot(Map<String, Object> sample) {
    var intervals = records(sample, "intervals");
    check(intervals.size() >= 4, "Enough complete calibration intervals");
    var ms = intervals.stream().map(e -> e.get("gap_ms")).sorted().toList();
    var ticks = intervals.stream().map(e -> e.get("gap_ticks")).sorted().toList();
    sample.put("median_ms", median(ms));
    sample.put("median_ticks", median(ticks));
    sample.put("min_ms", ms.getFirst());
    sample.put("max_ms", ms.getLast());
  }

  private static double median(List<Integer> values) {
    int n = values.size();
    return (values.get((n - 1) / 2) + values.get(n / 2)) / 2.0;
  }
  @SuppressWarnings("unchecked")
  private static List<Map<String, Integer>> records(Map<String, Object> data,
                                                    String name) {
    return (List<Map<String, Integer>>)data.get(name);
  }
  private static int value(Map<String, Object> data, String name) {
    return ((Number)data.get(name)).intValue();
  }
  private static double number(Map<String, Object> data, String name) {
    return ((Number)data.get(name)).doubleValue();
  }
  private void announce(ProbeContext.ServerAccess server, String text) {
    server.runCommand("title @a actionbar " + new GsonBuilder().create().toJson(text));
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
