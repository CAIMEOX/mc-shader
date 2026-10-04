package dev.caimeo.signal;

import com.google.gson.GsonBuilder;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import java.io.InputStreamReader;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import net.fabricmc.fabric.api.client.gametest.v1.FabricClientGameTest;
import net.fabricmc.fabric.api.client.gametest.v1.context.ClientGameTestContext;
import net.fabricmc.fabric.api.client.gametest.v1.context.TestServerContext;
import net.minecraft.resources.Identifier;
import net.minecraft.world.level.storage.LevelResource;

public final class WorldFixtureTest implements FabricClientGameTest {
  private final Map<String, Object> report = new LinkedHashMap<>();

  private JsonObject config;

  @Override
  public void runTest(ClientGameTestContext context) {
    report.put("result", "running");
    report.put("minecraft", "26.3");
    report.put("transport", "integrated server / local Netty channel");

    report.put("presentation", "visible Minecraft window");
    try {
      try (var reader = new InputStreamReader(Objects.requireNonNull(
               getClass().getResourceAsStream("/experiment.json")))) {
        config = JsonParser.parseReader(reader).getAsJsonObject();
      }
      var reload = context.computeOnClient(mc -> {
        var packs = mc.getResourcePackRepository();
        packs.reload();
        var ids = new ArrayList<>(packs.getSelectedIds());
        ids.add("file/signal.zip");
        packs.setSelected(ids);
        mc.options.renderDistance().set(3);
        mc.options.enableVsync().set(false);
        mc.options.bobView().set(false);
        mc.options.framerateLimit().set(config.get("frame_limit").getAsInt());
        mc.options.inactivityFpsLimit().set(
            net.minecraft.client.InactivityFpsLimit.MINIMIZED);
        mc.options.pauseOnLostFocus = false;
        mc.getWindow().setTitle("Signal · shader and client tick timing");
        return mc.reloadResourcePacks();
      });
      context.waitFor(mc -> reload.isDone(), 1200);
      reload.join();
      context.waitFor(mc -> mc.gui.overlay() == null, 400);
      try (var world = context.worldBuilder().create()) {
        var server = world.getServer();
        var loading = server.computeOnServer(s -> {
          var dir = s.getWorldPath(LevelResource.DATAPACK_DIR);
          Files.createDirectories(dir);
          Files.copy(Path.of("signal-datapack.zip"), dir.resolve("signal.zip"),
                     StandardCopyOption.REPLACE_EXISTING);
          var packs = s.getPackRepository();
          packs.reload();
          var ids = new ArrayList<>(packs.getSelectedIds());
          ids.add("file/signal.zip");
          packs.setSelected(ids);
          return s.reloadResources(ids);
        });
        context.waitFor(mc -> loading.isDone(), 600);
        loading.join();
        context.getInput().resizeWindow(1280, 720);
        server.runCommand("gamemode spectator @a");
        server.runCommand("fill -8 63 -8 8 63 8 minecraft:polished_andesite strict");
        server.runCommand("tp @a 0 69 10 180 30");
        server.runCommand("time set noon");
        server.runCommand("weather clear");
        if (!config.has("experiment"))
          server.runCommand("function signal:start");
        context.waitTicks(50);
        world.getConnection().waitForChunksRender(false, 400);
        report.put("framebuffer",
                   context.computeOnClient(
                       mc
                       -> List.of(mc.gameRenderer.mainRenderTarget().width,
                                  mc.gameRenderer.mainRenderTarget().height)));
        report.put("frame_limit",
                   context.computeOnClient(
                       mc -> mc.getFramerateLimitTracker().getFramerateLimit()));
        context.takeScreenshot("signal-world");
        report.put("result", "passed");
        persist();
      }
    } catch (Throwable error) {
      report.put("result", "failed");
      report.put("failure", error.toString());
      persist();
      throw new RuntimeException(error);
    }
  }
  private void persist() {
    try {
      Files.writeString(Path.of("signal-world.json"),
                        new GsonBuilder().setPrettyPrinting().create().toJson(report));
    } catch (Exception e) {
      throw new RuntimeException(e);
    }
  }
}
