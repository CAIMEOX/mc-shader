package dev.caimeo.backrooms;

import com.google.gson.GsonBuilder;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import com.mojang.blaze3d.platform.InputConstants;
import net.fabricmc.fabric.api.client.event.lifecycle.v1.ClientTickEvents;
import net.fabricmc.fabric.api.client.gametest.v1.FabricClientGameTest;
import net.fabricmc.fabric.api.client.gametest.v1.context.ClientGameTestContext;
import net.fabricmc.fabric.api.client.gametest.v1.context.TestServerContext;
import net.minecraft.core.BlockPos;
import net.minecraft.core.registries.Registries;
import net.minecraft.resources.Identifier;
import net.minecraft.resources.ResourceKey;
import net.minecraft.world.level.Level;
import net.minecraft.world.level.storage.LevelResource;
import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.*;
import java.util.zip.ZipFile;

public final class BackroomsClientTest implements FabricClientGameTest {
  private final Map<String, Object> report = new LinkedHashMap<>();
  private final List<Map<String, Object>> checks = new ArrayList<>();
  private final List<Double> positions = new ArrayList<>();
  private volatile boolean walking;
  private static final ResourceKey<Level> DIM =
      ResourceKey.create(Registries.DIMENSION, Identifier.parse("backrooms:level0"));
  private JsonObject scene;

  @Override
  public void runTest(ClientGameTestContext context) {
    if (!Boolean.getBoolean("backrooms.test.lab"))
      return;
    report.put("result", "running");
    report.put("minecraft", "26.3");
    report.put("presentation", "native visible window");
    report.put("checks", checks);
    ClientTickEvents.END_CLIENT_TICK.register(mc -> {
      if (walking && mc.player != null)
        positions.add(mc.player.getZ());
    });
    try {
      try (var stream = getClass().getResourceAsStream("/scene.json")) {
        if (stream == null)
          throw new IllegalStateException("Missing generated scene descriptor");
        scene =
            JsonParser
                .parseString(new String(stream.readAllBytes(), StandardCharsets.UTF_8))
                .getAsJsonObject();
      }
      var reload = context.computeOnClient(mc -> {
        var packs = mc.getResourcePackRepository();
        packs.reload();
        var ids = new ArrayList<>(packs.getSelectedIds());
        ids.add("file/backrooms.zip");
        packs.setSelected(ids);
        mc.options.renderDistance().set(5);
        mc.options.bobView().set(false);
        mc.options.enableVsync().set(false);
        mc.options.framerateLimit().set(60);
        mc.options.inactivityFpsLimit().set(
            net.minecraft.client.InactivityFpsLimit.MINIMIZED);
        mc.options.pauseOnLostFocus = false;
        mc.options.chatOpacity().set(0.0);
        mc.options.textBackgroundOpacity().set(0.0);
        mc.getWindow().setTitle("Backrooms · corridors, portals and mirrors");
        return mc.reloadResourcePacks();
      });
      context.waitFor(mc -> reload.isDone(), 1200);
      reload.join();
      context.waitFor(mc -> mc.gui.overlay() == null, 500);
      try (var world = context.worldBuilder().create()) {
        var server = world.getServer();
        var originalMode =
            server.computeOnServer(s
                                   -> s.getPlayerList()
                                          .getPlayers()
                                          .getFirst()
                                          .gameMode.getGameModeForPlayer());
        check(server.computeOnServer(s -> s.getLevel(DIM) != null),
              "Custom dimension loads at world creation");
        var loading = server.computeOnServer(s -> {
          var dir = s.getWorldPath(LevelResource.DATAPACK_DIR);
          Files.createDirectories(dir);
          Files.copy(Path.of("backrooms-datapack.zip"), dir.resolve("backrooms.zip"),
                     StandardCopyOption.REPLACE_EXISTING);
          var packs = s.getPackRepository();
          packs.reload();
          var ids = new ArrayList<>(packs.getSelectedIds());
          ids.add("file/backrooms.zip");
          packs.setSelected(ids);
          return s.reloadResources(ids);
        });
        context.waitFor(mc -> loading.isDone(), 600);
        loading.join();
        checkResources(server);
        context.getInput().resizeWindow(1280, 720);
        server.runOnServer(s
                           -> ((net.minecraft.client.server.IntegratedServer)s)
                                  .setWorldAllowCommands(true));
        server.runCommand("execute as @a at @s run function backrooms:lab/enter");
        awaitReady(context, 0);
        world.getConnection().waitForChunksRender(false, 500);
        context.waitTicks(20);
        checkCollision(server);
        verifyRays(context);
        context.takeScreenshot("backrooms-corridor");
        var first = GpuReadback.read(context, "scene");
        check(count(first, 2) > 1000, "Rendered carpet is visible");
        check(count(first, 3) > 1000, "Rendered ceiling is visible");
        check(count(first, 5) > 100, "Authored lights are visible in the renderer");
        checks.add(Map.of("case", "corridor_render", "floor_pixels", count(first, 2),
                          "ceiling_pixels", count(first, 3)));
        persist();

        server.runCommand("scoreboard players set #active backrooms 0");
        teleport(server, 0, 64, 2, 0, 0);
        context.waitTicks(15);
        var loopBefore = GpuReadback.read(context, "scene");
        teleport(server, 0, 64, 50, 0, 0);
        context.waitTicks(15);
        var loopAfter = GpuReadback.read(context, "scene");
        double loopError = geometryDifference(loopBefore, loopAfter);
        check(loopError < 0.6, "Whole-span relocation preserves the rendered corridor");
        checks.add(Map.of("case", "loop_view", "mean_rgb_error", loopError));
        persist();

        server.runCommand("scoreboard players set #active backrooms 1");
        teleport(server, 0, 64, 46, 0, 0);
        context.waitTicks(12);
        context.runOnClient(mc -> {
          positions.clear();
          walking = true;
        });
        context.getInput().holdKey(InputConstants.KEY_W);
        watch(context, 3.2);
        context.getInput().releaseKey(InputConstants.KEY_W);
        context.runOnClient(mc -> walking = false);
        context.waitTicks(8);
        var observed = context.computeOnClient(mc -> new ArrayList<>(positions));
        boolean crossed = false;
        for (int i = 1; i < observed.size(); i++)
          if (observed.get(i) - observed.get(i - 1) < -24)
            crossed = true;
        check(crossed, "Native forward input crosses the loop boundary");
        check(Math.abs(server.computeOnServer(
                           s -> s.getPlayerList().getPlayers().getFirst().getY()) -
                       64) < 0.01,
              "Collision floor supports walking");
        checks.add(Map.of("case", "loop_walk", "crossed", crossed, "samples",
                          observed.size()));
        persist();

        server.runCommand("scoreboard players set #active backrooms 0");
        teleport(server, 3.99, 64, 12, -90, 0);
        context.waitTicks(18);
        var portalBefore = GpuReadback.read(context, "scene");
        long portalPixels = count(portalBefore, 7);
        check(portalPixels > 2000, "The doorway renders the target hall");
        context.takeScreenshot("backrooms-doorway");
        server.runCommand(
            "execute as @a in backrooms:level0 at @s run function backrooms:portal/enter_first");
        server.runCommand("execute as @a at @s run tp @s ~0.02 ~ ~");
        awaitReady(context, 1);
        context.waitTicks(18);
        var portalAfter = GpuReadback.read(context, "scene");
        context.takeScreenshot("backrooms-portal-crossing");
        double portalError = geometryDifference(portalBefore, portalAfter);
        checks.add(Map.of("case", "portal_comparison", "mean_rgb_error", portalError,
                          "native_before", count(portalBefore, 8), "native_after",
                          count(portalAfter, 8), "position", playerPosition(server)));
        persist();
        check(portalError < 2.0, "Portal translation preserves the geometric view");
        var p = playerPosition(server);
        check(Math.abs(p.get(0) - 116.01) < 0.01 && Math.abs(p.get(2)) < 0.01,
              "Server applies the declared portal transform");
        checks.add(Map.of("case", "portal_view", "portal_pixels", portalPixels,
                          "mean_rgb_error", portalError, "position", p));
        persist();

        teleport(server, 115.2, 64, 0, -90, 0);
        server.runCommand("scoreboard players set #active backrooms 1");
        context.waitTicks(12);
        context.getInput().holdKey(InputConstants.KEY_W);
        watch(context, 1.0);
        context.getInput().releaseKey(InputConstants.KEY_W);
        awaitReady(context, 1);
        p = playerPosition(server);
        check(p.get(0) > 116 && p.get(0) < 124,
              "Walking passes through the doorway into the hall");
        checks.add(Map.of("case", "portal_walk", "position", p));
        persist();
        teleport(server, 128, 64, -5, 0, -8);
        context.waitTicks(15);
        context.takeScreenshot("backrooms-hall");
        check(count(GpuReadback.read(context, "scene"), 4) > 100,
              "Hall columns participate in rendered occlusion");

        teleport(server, 117.8, 64, 0, 90, 0);
        context.waitTicks(10);
        context.getInput().holdKey(InputConstants.KEY_W);
        watch(context, 1.1);
        context.getInput().releaseKey(InputConstants.KEY_W);
        awaitReady(context, 0);
        p = playerPosition(server);
        check(p.get(0) < 4.1 && p.get(2) > 11 && p.get(2) < 13,
              "The doorway supports the return walk");
        checks.add(Map.of("case", "portal_return", "position", p));
        persist();

        server.runCommand("scoreboard players set #active backrooms 0");
        teleport(server, 0, 64, 6, 90, 0);
        context.waitTicks(18);
        server.runCommand("scoreboard players set #mirror backrooms 0");
        server.runCommand("function backrooms:send");
        awaitMirror(context, 0);
        var ordinary = GpuReadback.read(context, "scene");
        check(count(ordinary, 6) > 10000,
              "The mirror is visible from native first-person view");
        context.takeScreenshot("backrooms-mirror");
        server.runCommand("execute as @a run trigger backrooms.action set 1");
        awaitMirror(context, 1);
        var anomaly = GpuReadback.read(context, "scene");
        double mirrorDifference = difference(ordinary, anomaly, 6);
        double outsideDifference = differenceExcluding(ordinary, anomaly, 6);
        check(mirrorDifference > 8, "The mirror can show a different light state");
        check(outsideDifference < 0.3,
              "Mirror state leaves the observed room lighting stable");
        context.takeScreenshot("backrooms-mirror-anomaly");
        checks.add(Map.of("case", "mirror_state", "mirror_rgb_difference",
                          mirrorDifference, "outside_rgb_difference",
                          outsideDifference));
        persist();

        teleport(server, 0, 64, 2, 0, 0);
        context.waitTicks(15);
        server.runCommand(
            "execute in backrooms:level0 run setblock 0 65 5 minecraft:red_concrete");
        context.waitTicks(18);
        var obstructed = GpuReadback.read(context, "scene");
        check(count(obstructed, 8) > 1000,
              "A real foreground block occludes shader geometry");
        context.takeScreenshot("backrooms-foreground");
        checks.add(Map.of("case", "native_occlusion", "foreground_pixels",
                          count(obstructed, 8)));
        persist();
        server.runCommand(
            "execute in backrooms:level0 run setblock 0 65 5 minecraft:air");

        context.runOnClient(mc -> mc.options.improvedTransparency().set(true));
        teleport(server, 0, 64, 6, 90, 0);
        awaitReady(context, 0);
        context.waitTicks(15);
        check(count(GpuReadback.read(context, "scene"), 6) > 1000,
              "Mirror and pixel transport work with improved transparency");
        checks.add(Map.of("case", "improved_transparency", "packet_ready", true));
        persist();
        context.getInput().resizeWindow(1920, 1080);
        context.waitTicks(20);
        watch(context, 2.0);
        checks.add(Map.of("case", "large_window", "fps",
                          context.computeOnClient(mc -> mc.getFps()), "framebuffer",
                          List.of(1920, 1080)));
        persist();
        server.runCommand("execute as @a run function backrooms:stop");
        context.waitTicks(20);
        check(
            server.computeOnServer(
                s
                -> s.getPlayerList().getPlayers().getFirst().level().dimension().equals(
                    Level.OVERWORLD)),
            "Exit restores the original dimension");
        check(GpuReadback.read(context, "probe").scalar(0) < .5,
              "Exit restores native world rendering");
        check(server.computeOnServer(s
                                     -> s.getPlayerList()
                                                .getPlayers()
                                                .getFirst()
                                                .gameMode.getGameModeForPlayer() ==
                                            originalMode),
              "Exit restores the original game mode");
        checks.add(Map.of("case", "exit", "restored_dimension", "minecraft:overworld"));
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

  private void checkResources(TestServerContext server) throws Exception {
    int files = server.computeOnServer(s -> {
      int checked = 0;
      try (var archive = new ZipFile("backrooms-datapack.zip")) {
        for (var entry : Collections.list(archive.entries())) {
          if (!entry.getName().startsWith("data/") || entry.isDirectory())
            continue;
          var parts = entry.getName().split("/", 3);
          var id = Identifier.fromNamespaceAndPath(parts[1], parts[2]);
          var resource = s.getResourceManager().getResource(id).orElseThrow();
          try (var source = archive.getInputStream(entry);
               var actual = resource.open()) {
            check(
                Arrays.equals(
                    MessageDigest.getInstance("SHA-256").digest(source.readAllBytes()),
                    MessageDigest.getInstance("SHA-256").digest(actual.readAllBytes())),
                "Loaded data resource matches the delivery pack");
          }
          checked++;
        }
      }
      return checked;
    });
    checks.add(Map.of("case", "loaded_resources", "files", files));
    persist();
  }

  private void checkCollision(TestServerContext server) {
    int verified = server.computeOnServer(s -> {
      var level = s.getLevel(DIM);
      int checked = 0;
      for (var element : scene.getAsJsonArray("collision_volumes")) {
        var volume = element.getAsJsonObject();
        var lo = volume.getAsJsonArray("lower");
        var hi = volume.getAsJsonArray("upper");
        int x =
            (int)Math.floor((lo.get(0).getAsDouble() + hi.get(0).getAsDouble()) * .5);
        int y =
            (int)Math.floor((lo.get(1).getAsDouble() + hi.get(1).getAsDouble()) * .5);
        int z =
            (int)Math.floor((lo.get(2).getAsDouble() + hi.get(2).getAsDouble()) * .5);
        var state = level.getBlockState(new BlockPos(x, y, z));
        var id = net.minecraft.core.registries.BuiltInRegistries.BLOCK
                     .getKey(state.getBlock())
                     .toString();
        check(id.equals(volume.get("block").getAsString()) ||
                  (volume.get("block").getAsString().equals("minecraft:smooth_stone") &&
                   id.equals("minecraft:ochre_froglight")),
              "Collision volume is materialized");
        checked++;
      }
      check(level.getBlockState(new BlockPos(4, 65, 12)).isAir(),
            "Corridor portal has headroom");
      check(level.getBlockState(new BlockPos(115, 65, 0)).isAir(),
            "Hall portal has headroom");
      return checked;
    });
    checks.add(Map.of("case", "collision_geometry", "volumes", verified));
    persist();
  }

  private void verifyRays(ClientGameTestContext context) {
    var actual = GpuReadback.read(context, "probe");
    int index = 0;
    for (var element : scene.getAsJsonArray("rays")) {
      var expected = element.getAsJsonObject().getAsJsonArray("expected");
      check(Math.abs(actual.scalar(8 + 4 * index) - expected.get(0).getAsDouble()) <
                0.01,
            "GPU ray distance matches the Haskell scene");
      check((int)Math.round(actual.scalar(9 + 4 * index)) == expected.get(1).getAsInt(),
            "GPU ray material matches the Haskell scene");
      check((int)Math.round(actual.scalar(10 + 4 * index)) ==
                expected.get(2).getAsInt(),
            "GPU ray selects the target room");
      index++;
    }
    checks.add(Map.of("case", "gpu_geometry", "rays", index));
    persist();
  }

  private void awaitReady(ClientGameTestContext context, int room) {
    for (int i = 0; i < 100; i++) {
      context.waitTicks(3);
      var p = GpuReadback.read(context, "probe");
      if (p != null && p.scalar(0) > .5 && Math.abs(p.scalar(1) - room) < .01)
        return;
    }
    throw new IllegalStateException("Camera packet or room scene did not become ready");
  }
  private void awaitMirror(ClientGameTestContext context, int mirror) {
    for (int i = 0; i < 60; i++) {
      context.waitTicks(3);
      var p = GpuReadback.read(context, "probe");
      if (p != null && p.scalar(0) > .5 && Math.abs(p.scalar(2) - mirror) < .01)
        return;
    }
    throw new IllegalStateException("Mirror state did not arrive at the renderer");
  }
  private static void teleport(TestServerContext server, double x, double y, double z,
                               float yaw, float pitch) {
    server.runCommand("execute in backrooms:level0 run tp @a " + x + " " + y + " " + z +
                      " " + yaw + " " + pitch);
  }
  private static List<Double> playerPosition(TestServerContext server) {
    return server.computeOnServer(s -> {
      var p = s.getPlayerList().getPlayers().getFirst();
      return List.of(p.getX(), p.getY(), p.getZ());
    });
  }
  private static long count(GpuReadback.Image image, int material) {
    long count = 0;
    for (int rgba : image.rgba())
      if ((rgba & 255) == material)
        count++;
    return count;
  }
  private static double difference(GpuReadback.Image a, GpuReadback.Image b,
                                   int material) {
    double sum = 0;
    long count = 0;
    for (int i = 0; i < a.rgba().length; i++)
      if (material < 0 || (a.rgba()[i] & 255) == material) {
        for (int channel = 1; channel < 4; channel++)
          sum += Math.abs(((a.rgba()[i] >>> (channel * 8)) & 255) -
                          ((b.rgba()[i] >>> (channel * 8)) & 255));
        count += 3;
      }
    return sum / Math.max(1, count);
  }
  private static double differenceExcluding(GpuReadback.Image a, GpuReadback.Image b,
                                            int material) {
    double sum = 0;
    long count = 0;
    for (int i = 0; i < a.rgba().length; i++)
      if ((a.rgba()[i] & 255) != material) {
        for (int channel = 1; channel < 4; channel++)
          sum += Math.abs(((a.rgba()[i] >>> (channel * 8)) & 255) -
                          ((b.rgba()[i] >>> (channel * 8)) & 255));
        count += 3;
      }
    return sum / Math.max(1, count);
  }
  private static double geometryDifference(GpuReadback.Image a, GpuReadback.Image b) {
    double sum = 0;
    long count = 0;
    for (int i = 0; i < a.rgba().length; i++)
      if ((a.rgba()[i] & 255) != 8 && (b.rgba()[i] & 255) != 8) {
        for (int channel = 1; channel < 4; channel++)
          sum += Math.abs(((a.rgba()[i] >>> (channel * 8)) & 255) -
                          ((b.rgba()[i] >>> (channel * 8)) & 255));
        count += 3;
      }
    return sum / Math.max(1, count);
  }
  private static void watch(ClientGameTestContext context, double seconds) {
    long finish = System.nanoTime() + (long)(seconds * 1e9);
    context.waitFor(mc -> System.nanoTime() >= finish, 12000);
  }
  private static void check(boolean ok, String message) {
    if (!ok)
      throw new IllegalStateException(message);
  }
  private void persist() {
    try {
      Files.writeString(Path.of("backrooms-report.json"),
                        new GsonBuilder().setPrettyPrinting().create().toJson(report));
    } catch (Exception error) {
      throw new RuntimeException(error);
    }
  }
}
