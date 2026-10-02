package dev.caimeo.qwen;

import com.google.gson.*;
import net.fabricmc.fabric.api.client.gametest.v1.FabricClientGameTest;
import net.fabricmc.fabric.api.client.gametest.v1.context.ClientGameTestContext;
import net.minecraft.world.level.storage.LevelResource;
import java.io.InputStreamReader;
import java.nio.file.*;
import java.util.*;

public final class QwenClientTest implements FabricClientGameTest {
  private final Map<String, Object> report = new LinkedHashMap<>();
  private final List<Map<String, Object>> checks = new ArrayList<>();
  private void persist() {
    try {
      Files.writeString(Path.of("qwen-report.json"),
                        new GsonBuilder().setPrettyPrinting().create().toJson(report));
    } catch (Exception e) {
      throw new RuntimeException(e);
    }
  }
  private void check(boolean value, String message) {
    if (!value)
      throw new AssertionError(message);
  }
  @Override
  public void runTest(ClientGameTestContext context) {
    report.put("result", "running");
    report.put("checks", checks);
    report.put("presentation", "visible native window");
    persist();
    try {
      var reload = context.computeOnClient(mc -> {
        var packs = mc.getResourcePackRepository();
        packs.reload();
        var selected = new ArrayList<>(packs.getSelectedIds());
        selected.add("file/qwen.zip");
        selected.add("file/qwen-probes.zip");
        packs.setSelected(selected);
        mc.options.renderDistance().set(3);
        mc.options.enableVsync().set(false);
        mc.options.framerateLimit().set(60);
        mc.options.bobView().set(false);
        mc.options.pauseOnLostFocus = false;
        mc.options.inactivityFpsLimit().set(
            net.minecraft.client.InactivityFpsLimit.MINIMIZED);
        mc.getWindow().setTitle("Qwen3 · visible shader benchmark");
        return mc.reloadResourcePacks();
      });
      context.waitFor(mc -> reload.isDone(), 1800);
      reload.join();
      context.waitFor(mc -> mc.gui.overlay() == null, 600);
      try (var world = context.worldBuilder().create()) {
        var server = world.getServer();
        var loading = server.computeOnServer(s -> {
          var dir = s.getWorldPath(LevelResource.DATAPACK_DIR);
          Files.createDirectories(dir);
          Files.copy(Path.of("qwen-datapack.zip"), dir.resolve("qwen.zip"),
                     StandardCopyOption.REPLACE_EXISTING);
          var packs = s.getPackRepository();
          packs.reload();
          var ids = new ArrayList<>(packs.getSelectedIds());
          ids.add("file/qwen.zip");
          packs.setSelected(ids);
          return s.reloadResources(ids);
        });
        context.waitFor(mc -> loading.isDone(), 1200);
        loading.join();
        context.getInput().resizeWindow(1280, 720);
        server.runCommand("gamemode spectator @a");
        server.runCommand("tp @a 0 100 0 0 0");
        context.waitTicks(30);
        world.getConnection().waitForChunksRender(false, 400);
        server.runCommand("data modify storage qwen:input max_tokens set value 8");
        JsonArray fixtures;
        try (var reader = new InputStreamReader(
                 QwenClientTest.class.getResourceAsStream("/fixtures.json"))) {
          fixtures = JsonParser.parseReader(reader).getAsJsonArray();
        }
        for (int which = 0; which < fixtures.size(); which++) {
          var fixture = fixtures.get(which).getAsJsonObject();
          String prompt = fixture.get("prompt").getAsString();
          server.runCommand("data modify storage qwen:input max_tokens set value " +
                            (which == 4 ? 40 : 8));
          server.runCommand("data modify storage qwen:input prompt set value " +
                            new Gson().toJson(prompt));
          server.runCommand("execute as @a at @s run function qwen:submit");
          long begin = System.nanoTime();
          GpuReadback.Image state = null;
          for (int i = 0; i < 400; i++) {
            context.waitTicks(2);
            state = GpuReadback.read(context, "control_b");
            if (state != null && state.word(1) == which + 1 && state.word(0) >= 2)
              break;
          }
          if (state == null || state.word(1) != which + 1) {
            var debug = GpuReadback.readBatch(context, "minecraft:end_of_frame",
                                              List.of("packet", "control_b"));
            var packetDebug = new ArrayList<Long>();
            for (int j = 0; j < 40; j++)
              packetDebug.add(debug.get("packet").word(j));
            report.put("packetDebug", packetDebug);
            report.put("controlDebug", Arrays.toString(debug.get("control_b").rgba()));
            report.put(
                "transmitter",
                server.computeOnServer(
                    s
                    -> s.getCommandStorage()
                           .get(net.minecraft.resources.Identifier.parse("qwen:tx"))
                           .toString()));
            persist();
            context.takeScreenshot("qwen-transport");
          }
          check(state != null && state.word(1) == which + 1, "New request received");
          var batch = GpuReadback.readBatch(context, "minecraft:end_of_frame",
                                            List.of("tokens", "packet"));
          var tokens = batch.get("tokens");
          var expected = fixture.getAsJsonArray("token_ids");
          var tokenDebug = new ArrayList<Long>();
          for (int j = 0; j < 40; j++)
            tokenDebug.add(tokens.word(j));
          var packetWords = new ArrayList<Long>();
          for (int j = 0; j < 40; j++)
            packetWords.add(batch.get("packet").word(j));
          report.put("tokenDebug", tokenDebug);
          report.put("packetDebug", packetWords);
          report.put("controlDebug", Arrays.toString(state.rgba()));
          persist();
          check(state.word(9) == (which == 4 ? 40 : 8), "Generation limit received");
          check(tokens.word(1) == 0, "Tokenizer status");
          check(tokens.word(0) == expected.size(), "Token count");
          for (int i = 0; i < expected.size(); i++)
            check(tokens.word(i + 2) == expected.get(i).getAsInt(), "Token " + i);
          for (int i = 0; i < prompt.length(); i++)
            check(batch.get("packet").word(3 + i) == prompt.charAt(i),
                  "Code point " + i);
          if (!fixture.has("reference")) {
            checks.add(Map.of("case", "input", "prompt", prompt, "token_count",
                              expected.size(), "codepoints", prompt.length()));
            persist();
            continue;
          }
          long firstToken = -1;
          var fpsSamples = new ArrayList<Integer>();
          for (int i = 0; i < 2400 && state.word(0) != 6; i++) {
            check(state.word(0) != 7, "Shader inference error");
            context.waitTicks(1);
            state = GpuReadback.read(context, "control_b");
            if (firstToken < 0 && state.word(6) > 0)
              firstToken = System.nanoTime();
            if (i % 10 == 0 && state.word(0) == 3)
              fpsSamples.add(context.computeOnClient(mc -> mc.getFps()));
            if (i % 40 == 0) {
              report.put("progress", List.of(which, state.word(0), state.word(2),
                                             state.word(3), state.word(6)));
              persist();
            }
          }
          check(state.word(0) == 6, "Generation completed");
          long finished = System.nanoTime();
          batch = GpuReadback.readBatch(context, "minecraft:end_of_frame",
                                        List.of("generated_b", "output_b"));
          var actual = batch.get("generated_b");
          var generated =
              fixture.getAsJsonObject("reference").getAsJsonArray("generated");
          check(state.word(6) == generated.size(), "Generated token count");
          var ids = new ArrayList<Long>();
          for (int i = 0; i < generated.size(); i++)
            ids.add(actual.word(i));
          report.put("generated", ids);
          persist();
          for (int i = 0; i < generated.size(); i++)
            check(actual.word(i) == generated.get(i).getAsInt(),
                  "Generated token " + i);
          byte[] bytes = new byte[(int)state.word(8)];
          for (int i = 0; i < bytes.length; i++)
            bytes[i] = (byte)batch.get("output_b").word(i);
          String text = new String(bytes, java.nio.charset.StandardCharsets.UTF_8);
          check(text.equals(fixture.get("decoded").getAsString()),
                "Rendered text bytes");
          var measured = new LinkedHashMap<String, Object>();
          measured.put("prompt", prompt);
          measured.put("token_ids", ids);
          measured.put("output", text);
          measured.put("seconds", (finished - begin) * 1e-9);
          measured.put("first_token_seconds", (firstToken - begin) * 1e-9);
          measured.put("decode_tokens_per_second",
                       (ids.size() - 1) / ((finished - firstToken) * 1e-9));
          measured.put("fps", context.computeOnClient(mc -> mc.getFps()));
          measured.put("fps_samples", fpsSamples);
          measured.put("context_capacity", 1024);
          checks.add(measured);
          persist();
          context.takeScreenshot("qwen-output-" + which);
        }
        server.runCommand("data modify storage qwen:input max_tokens set value 256");
        server.runCommand("execute as @a at @s run function qwen:submit");
        context.waitTicks(8);
        var capacity = GpuReadback.read(context, "control_b");
        check(capacity.word(1) == fixtures.size() + 1 && capacity.word(9) == 256,
              "256-token request received");
        checks.add(
            Map.of("case", "generation_capacity", "max_tokens", capacity.word(9)));
        try (var reader = new InputStreamReader(
                 QwenClientTest.class.getResourceAsStream("/probes.json"))) {
          for (var entry : JsonParser.parseReader(reader).getAsJsonArray()) {
            var probe = entry.getAsJsonObject();
            String effect = probe.get("effect").getAsString();
            server.runCommand("posteffect add @a " + effect);
            context.waitTicks(3);
            var image =
                GpuReadback.readBatch(context, effect, List.of("result")).get("result");
            var indices = probe.getAsJsonArray("indices");
            var expected = probe.getAsJsonArray("values");
            double maximum = 0;
            for (int i = 0; i < indices.size(); i++) {
              double value = image.scalar(indices.get(i).getAsInt()),
                     wanted = expected.get(i).getAsDouble();
              maximum = Math.max(maximum, Math.abs(value - wanted));
              check(Double.isFinite(value) &&
                        Math.abs(value - wanted) <= .0002 + Math.abs(wanted) * .00002,
                    "Operator probe " + probe.get("name") + " element " + i);
            }
            checks.add(Map.of("case", "operator_probe", "name",
                              probe.get("name").getAsString(), "max_abs_error",
                              maximum));
            persist();
            server.runCommand("posteffect remove @a " + effect);
          }
        }
        report.put("result", "passed");
        persist();
      }
    } catch (Throwable e) {
      report.put("result", "failed");
      report.put("failure", e.toString());
      persist();
      try {
        context.takeScreenshot("qwen-failure");
      } catch (Throwable ignored) {
      }
      throw new RuntimeException(e);
    }
  }
}
