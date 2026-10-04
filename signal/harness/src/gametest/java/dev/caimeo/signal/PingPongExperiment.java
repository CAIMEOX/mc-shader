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
import java.util.concurrent.ConcurrentLinkedQueue;
import net.minecraft.client.Minecraft;
import net.minecraft.network.chat.Component;
import net.minecraft.network.chat.contents.TranslatableContents;
import net.minecraft.resources.Identifier;
import net.minecraft.world.scores.ScoreHolder;

/** Starts one autonomous data-pack session and verifies its received frame and chat. */
public final class PingPongExperiment {
  private static final ConcurrentLinkedQueue<Map<String, Object>> CHAT =
      new ConcurrentLinkedQueue<>();
  private final Map<String, Object> report = new LinkedHashMap<>();
  private final List<Map<String, Object>> progress = new ArrayList<>();

  public static void capture(Component component) {
    if (!Boolean.getBoolean("signal.pingpong") ||
        !(component.getContents() instanceof TranslatableContents content) ||
        !content.getKey().startsWith("signal.ping."))
      return;
    CHAT.add(Map.of("key", content.getKey(), "args",
                    Arrays.stream(content.getArgs())
                        .map(value
                             -> value instanceof Component text ? text.getString()
                                                                : String.valueOf(value))
                        .toList(),
                    "text", component.getString()));
  }

  public void run(Minecraft minecraft) {
    var context = new ProbeContext(minecraft);
    var server = context.server();
    CHAT.clear();
    report.put("result", "running");
    report.put("experiment", "pingpong");
    report.put("native_scheduling",
               System.getProperty("fabric.client.gametest") == null);
    report.put("presentation", "visible Minecraft window");
    report.put("gpu_readback", false);
    report.put("driver",
               "one start command; read-only polling until the data pack reports EOF");
    report.put("progress", progress);
    boolean observing = false;
    try {
      check(Boolean.getBoolean("signal.stopwatchOnly"), "Timestamp observers excluded");
      check(System.getProperty("fabric.client.gametest") == null, "Native scheduler");
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
      int tickRate = config.get("tick_rate").getAsInt();
      server.runCommand("tick rate " + tickRate);
      server.runCommand("difficulty peaceful");
      server.runCommand("gamemode survival @a");
      server.runCommand("kill @e[tag=signal.carrier]");
      server.runCommand("fill -8 63 -8 8 63 8 minecraft:polished_andesite strict");
      server.runCommand("fill -2 64 -2 8 67 2 minecraft:air strict");
      server.runCommand("tp @a 0.5 64 0.5 -90 0");
      server.runCommand("time set noon");
      server.runCommand("scoreboard players reset * signal.rx");
      server.runCommand("scoreboard objectives setdisplay sidebar signal.rx");
      context.computeOnClient(mc -> {
        mc.options.enableVsync().set(false);
        mc.options.bobView().set(false);
        mc.options.framerateLimit().set(config.get("frame_limit").getAsInt());
        mc.options.pauseOnLostFocus = false;
        mc.options.inactivityFpsLimit().set(
            net.minecraft.client.InactivityFpsLimit.MINIMIZED);
        mc.getWindow().setTitle("Signal · ping-pong shader message");
        report.put("framebuffer", List.of(mc.gameRenderer.mainRenderTarget().width,
                                          mc.gameRenderer.mainRenderTarget().height));
        return null;
      });
      context.sleep(1000);
      check(!server.computeOnServer(
                s
                -> s.getPlayerList().getPlayers().getFirst().getPostEffects().contains(
                    Identifier.parse("signal:ping"))),
            "Post effect initially inactive");
      long started = System.nanoTime();
      Observation.begin();
      observing = true;
      server.runCommand("execute as @a[limit=1] at @s run function signal:ping/start");
      Map<String, Object> state = snapshot(server);
      check(value(state, "active") == 1, "Data pack starts the session");
      check(Boolean.TRUE.equals(state.get("posteffect_active")),
            "Data pack activates the post effect");
      while (value(state, "active") == 1 &&
             (System.nanoTime() - started) < 620_000_000_000L) {
        progress.add(state);
        report.put("latest", state);
        report.put("chat", List.copyOf(CHAT));
        persist();
        context.sleep(1000);
        state = snapshot(server);
      }
      report.put("receiver", state);
      report.put("wall_seconds", (System.nanoTime() - started) / 1e9);
      var observations = Observation.finish();
      observing = false;
      report.put("observations", observations);
      for (var stream : List.of("frame", "sent", "arrived", "handled", "server_tick"))
        check(((List<?>)observations.get(stream)).isEmpty(),
              "Timestamp stream excluded: " + stream);
      check(state.get("status").equals("complete"),
            "Data pack completed a CRC-verified frame: " + state.get("status") + " " +
                state.get("error"));
      check(value(state, "active") == 0 &&
                Boolean.FALSE.equals(state.get("posteffect_active")),
            "EOF removes the post effect and stops reception");
      check(((Number)state.get("tick_rate")).floatValue() == tickRate,
            "Data pack preserves the configured tick rate");
      var expectedFrame = config.getAsJsonArray("expected_frame")
                              .asList()
                              .stream()
                              .map(v -> v.getAsInt())
                              .toList();
      var expectedBits = config.getAsJsonArray("expected_bits")
                             .asList()
                             .stream()
                             .map(v -> v.getAsInt())
                             .toList();
      check(state.get("bytes").equals(expectedFrame),
            "Decoded frame equals the shader frame");
      check(state.get("bits").equals(expectedBits),
            "Every accepted bit equals the shader bitstream");
      String message = config.get("expected_message").getAsString();
      check(state.get("message").equals(message),
            "Data pack assembled the shader message");
      context.sleep(300);
      var messages = List.copyOf(CHAT);
      report.put("chat", messages);
      var complete = messages.stream()
                         .filter(m -> m.get("key").equals("signal.ping.complete"))
                         .toList();
      check(complete.size() == 1 &&
                arguments(complete.getFirst()).getFirst().equals(message),
            "Client receives the complete EOF message");
      var bitMessages = messages.stream()
                            .filter(m -> m.get("key").equals("signal.ping.bit"))
                            .toList();
      check(bitMessages.size() >= expectedBits.size(),
            "Client receives bit debug messages");
      var finalBits = bitMessages.subList(bitMessages.size() - expectedBits.size(),
                                          bitMessages.size());
      for (int i = 0; i < finalBits.size(); i++) {
        var args = arguments(finalBits.get(i));
        check(Integer.parseInt(args.get(0)) == i &&
                  Integer.parseInt(args.get(1)) == expectedBits.get(i),
              "Bit debug index and value");
      }
      var charMessages = messages.stream()
                             .filter(m -> m.get("key").equals("signal.ping.character"))
                             .toList();
      check(charMessages.size() >= message.length(),
            "Client receives character debug messages");
      var finalChars = charMessages.subList(charMessages.size() - message.length(),
                                            charMessages.size());
      for (int i = 0; i < finalChars.size(); i++) {
        var args = arguments(finalChars.get(i));
        check(Integer.parseInt(args.get(0)) == i &&
                  args.get(1).equals(message.substring(i, i + 1)) &&
                  Integer.parseInt(args.get(2)) == message.charAt(i),
              "Character debug index, text and ASCII code");
      }
      report.put("bit_messages", bitMessages.size());
      report.put("character_messages", charMessages.size());
      context.takeScreenshot("signal-pingpong-complete");
      context.sleep(2000);
      report.put("result", "passed");
    } catch (Throwable error) {
      report.put("result", "failed");
      report.put("failure", error.toString());
      report.put("chat", List.copyOf(CHAT));
      try {
        report.put("receiver", snapshot(server));
        context.takeScreenshot("signal-pingpong-failure");
      } catch (Throwable ignored) {
      }
    } finally {
      if (observing)
        report.put("observations", Observation.finish());
      try {
        server.runCommand("function signal:ping/cancel");
        server.runCommand("tick rate 20");
      } catch (Throwable ignored) {
      }
      persist();
      minecraft.execute(minecraft::stop);
    }
  }

  private Map<String, Object> snapshot(ProbeContext.ServerAccess server) {
    return server.computeOnServer(s -> {
      var data = s.getCommandStorage().get(Identifier.parse("signal:ping"));
      var out = new LinkedHashMap<String, Object>();
      for (var name : List.of("status", "error"))
        out.put(name, data.getStringOr(name, ""));
      for (var name : List.of("elapsed_ms", "transfer_ms", "length", "crc_expected",
                              "crc_received", "frame_retries", "total_bit_retries"))
        out.put(name, data.getIntOr(name, 0));
      for (var name : List.of("bits", "bytes"))
        out.put(name, data.getListOrEmpty(name)
                          .stream()
                          .map(v -> v.asInt().orElseThrow())
                          .toList());
      out.put("message", String.join("", data.getListOrEmpty("chars")
                                             .stream()
                                             .map(v -> v.asString().orElseThrow())
                                             .toList()));
      var scoreboard = s.getScoreboard();
      var objective = scoreboard.getObjective("signal");
      for (var name : List.of("active", "phase", "cal_index", "index", "bit_count",
                              "kind", "byte", "chars", "frame_number", "bit_retries")) {
        var value = scoreboard.getPlayerScoreInfo(
            ScoreHolder.forNameOnly("#ping_" + name), objective);
        out.put(name, value == null ? 0 : value.value());
      }
      var receiver = new LinkedHashMap<String, Integer>();
      for (var name : List.of("collect", "events", "value", "valid", "ready", "center0",
                              "center1", "threshold", "decoded")) {
        var value = scoreboard.getPlayerScoreInfo(
            ScoreHolder.forNameOnly("#rotate_" + name), objective);
        receiver.put(name, value == null ? 0 : value.value());
      }
      out.put("timing", receiver);
      var player = s.getPlayerList().getPlayers().getFirst();
      out.put("posteffect_active",
              player.getPostEffects().contains(Identifier.parse("signal:ping")));
      out.put("tick_rate", s.tickRateManager().tickrate());
      return out;
    });
  }

  @SuppressWarnings("unchecked")
  private static List<String> arguments(Map<String, Object> message) {
    return (List<String>)message.get("args");
  }
  private static int value(Map<String, Object> value, String key) {
    return ((Number)value.get(key)).intValue();
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
