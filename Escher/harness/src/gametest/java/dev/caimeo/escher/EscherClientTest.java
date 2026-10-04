package dev.caimeo.escher;

import com.google.gson.GsonBuilder;
import com.mojang.blaze3d.platform.InputConstants;
import net.fabricmc.fabric.api.client.gametest.v1.FabricClientGameTest;
import net.fabricmc.fabric.api.client.gametest.v1.context.ClientGameTestContext;
import net.fabricmc.fabric.api.client.gametest.v1.context.TestServerContext;
import net.fabricmc.fabric.api.client.event.lifecycle.v1.ClientTickEvents;
import net.fabricmc.fabric.api.client.rendering.v1.hud.HudElementRegistry;
import net.minecraft.client.Minecraft;
import net.minecraft.core.BlockPos;
import net.minecraft.resources.Identifier;
import net.minecraft.world.level.storage.LevelResource;
import net.minecraft.world.phys.Vec3;
import java.nio.file.*;
import java.util.*;

public final class EscherClientTest implements FabricClientGameTest {
  private final Map<String, Object> report = new LinkedHashMap<>();
  private final List<Map<String, Object>> checks = new ArrayList<>();
  private final List<Double> walkPositions = new ArrayList<>();
  private final List<Double> walkHeights = new ArrayList<>();
  private final List<Double> cameraFrames = new ArrayList<>();
  private volatile boolean walking;
  @Override
  public void runTest(ClientGameTestContext context) {
    report.put("result", "running");
    report.put("minecraft", "26.3");
    report.put("renderer", "analytic gallery");
    report.put("checks", checks);
    report.put("presentation", "native visible window");
    ClientTickEvents.END_CLIENT_TICK.register(mc -> {
      if (walking && mc.player != null) {
        walkPositions.add(mc.player.getZ());
        walkHeights.add(mc.player.getY());
      }
    });
    context.runOnClient(
        mc
        -> HudElementRegistry.addLast(
            Identifier.parse("escher:camera_observation"), (graphics, delta) -> {
              if (walking)
                cameraFrames.add(
                    Minecraft.getInstance().gameRenderer.mainCamera().position().z);
            }));
    try {
      var reload = context.computeOnClient(mc -> {
        var packs = mc.getResourcePackRepository();
        packs.reload();
        var ids = new ArrayList<>(packs.getSelectedIds());
        ids.add("file/escher.zip");
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
        mc.getWindow().setTitle("Escher · planar gallery tests");
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
          Files.copy(Path.of("escher-datapack.zip"), dir.resolve("escher.zip"),
                     StandardCopyOption.REPLACE_EXISTING);
          var packs = s.getPackRepository();
          packs.reload();
          var ids = new ArrayList<>(packs.getSelectedIds());
          ids.add("file/escher.zip");
          packs.setSelected(ids);
          return s.reloadResources(ids);
        });
        context.waitFor(mc -> loading.isDone(), 600);
        loading.join();
        context.getInput().resizeWindow(1280, 900);
        server.runOnServer(s
                           -> ((net.minecraft.client.server.IntegratedServer)s)
                                  .setWorldAllowCommands(true));
        server.runCommand("gamemode spectator @a");
        server.runCommand("tp @a 0.0 67.0 4.0 0 5");
        context.waitTicks(50);
        world.getConnection().waitForChunksRender(false, 400);
        if ("folding".equals(System.getenv("ESCHER_TEST_SCENE"))) {
          report.put("scope", "folding");
          verifyFolding(context, server);
          report.put("result", "passed");
          persist();
          return;
        }
        server.runCommand("function escher:demo");
        awaitPacket(context, server);
        context.waitTicks(20);
        context.takeScreenshot("escher-interior");
        var first = GpuReadback.read(context, "gallery_high");
        check(countRed(first) > 100, "Red shader spheres are visible");
        checks.add(Map.of("case", "gallery_landmarks", "red_pixels", countRed(first)));
        persist();
        server.runCommand("scoreboard players set #fold escher 0");
        for (int direction : new int[] {1, -1}) {
          double z = direction == 1 ? 36.25 : -.25;
          server.runCommand("tp @a 0.25 67.0 " + z + " 13 7");
          context.waitTicks(12);
          var before = GpuReadback.readBatch(context, "minecraft:end_of_frame",
                                             List.of("gallery_high", "probe"));
          server.runCommand("execute as @a at @s run function escher:fold/" +
                            (direction == 1 ? "forward" : "backward"));
          context.waitTicks(12);
          var after = GpuReadback.readBatch(context, "minecraft:end_of_frame",
                                            List.of("gallery_high", "probe"));
          double difference =
              imageDifference(before.get("gallery_high"), after.get("gallery_high"));
          check(difference < .15,
                "A whole-period teleport preserves the rendered gallery");
          for (int i = 0; i < 3; i++)
            check(Math.abs(before.get("probe").scalar(i) -
                           after.get("probe").scalar(i)) < .0002,
                  "Folded camera retains sub-block coordinates");
          checks.add(Map.of("case",
                            direction == 1 ? "forward_rebase" : "backward_rebase",
                            "mean_rgb_byte_error", difference, "phase",
                            after.get("probe").scalar(2)));
          persist();
        }
        var velocity = server.computeOnServer(s -> {
          var player = s.getPlayerList().getPlayers().getFirst();
          player.setDeltaMovement(new Vec3(.13, .28, .21));
          player.setKnownMovement(new Vec3(.13, .28, .21));
          s.getCommands().performPrefixedCommand(player.createCommandSourceStack(),
                                                 "tp @s ~ ~ ~-36 ~ ~");
          var actual = player.getDeltaMovement();
          return List.of(actual.x, actual.y, actual.z);
        });
        checks.add(Map.of("case", "teleport_velocity", "before", List.of(.13, .28, .21),
                          "after", velocity));
        persist();
        check(Math.abs(velocity.get(0) - .13) < 1e-5 &&
                  Math.abs(velocity.get(2) - .21) < 1e-5,
              "Relative teleport preserves horizontal velocity");
        check(velocity.get(1) == 0, "Vanilla teleport clears vertical velocity");
        server.runCommand("tp @a 0.0 67.0 17.9999 0 5");
        context.waitTicks(15);
        var seamBefore = GpuReadback.read(context, "gallery_high");
        server.runCommand("tp @a 0.0 67.0 18.0001 0 5");
        context.waitTicks(15);
        double seam =
            imageDifference(seamBefore, GpuReadback.read(context, "gallery_high"));
        checks.add(Map.of("case", "continuous_planar_seam", "mean_rgb_byte_error", seam,
                          "distance_moved", .0002));
        persist();
        check(seam < .5,
              "The logarithmic camera chart is continuous across adjacent rooms");
        server.runCommand("gamemode adventure @a");
        server.runCommand("scoreboard players set #fold escher 1");
        for (int direction : new int[] {1, -1}) {
          server.runCommand("tp @a 0.0 65.0 " + (direction == 1 ? "33.5" : "2.5") +
                            " " + (direction == 1 ? "0" : "180") + " 0");
          context.waitTicks(12);
          context.runOnClient(mc -> {
            walkPositions.clear();
            cameraFrames.clear();
            walking = true;
          });
          long finish = System.nanoTime() + 3_750_000_000L;
          context.getInput().holdKey(InputConstants.KEY_W);
          context.waitFor(mc -> System.nanoTime() >= finish, 12000);
          context.getInput().releaseKey(InputConstants.KEY_W);
          context.runOnClient(mc -> walking = false);
          context.waitTicks(5);
          var cameraPositions =
              context.computeOnClient(mc -> new ArrayList<>(cameraFrames));
          check(cameraPositions.size() > 90,
                "Observe the rendered camera more often than server ticks");
          var positions = context.computeOnClient(mc -> new ArrayList<>(walkPositions));
          int folds = 0;
          double minSpeed = Double.POSITIVE_INFINITY;
          for (int i = 1; i < positions.size(); i++) {
            double delta = positions.get(i) - positions.get(i - 1);
            if (Math.abs(delta) > 18) {
              folds++;
              double travel = delta + direction * 36;
              minSpeed = Math.min(minSpeed, direction * travel);
            }
          }
          check(folds >= 1, "Walking crosses the periodic boundary");
          check(minSpeed > .05, "Boundary crossing retains forward progress");
          double maxCameraStep = 0;
          for (int i = 1; i < cameraPositions.size(); i++) {
            double delta = cameraPositions.get(i) - cameraPositions.get(i - 1);
            delta -= 18 * Math.rint(delta / 18);
            maxCameraStep = Math.max(maxCameraStep, Math.abs(delta));
          }
          check(maxCameraStep < .6,
                "Render camera remains continuous during a walking teleport");
          var y = context.computeOnClient(mc -> mc.player.getY());
          check(Math.abs(y - 65) < .01,
                "Continuous collision floor supports the player");
          checks.add(Map.of("case", direction == 1 ? "walk_inward" : "walk_outward",
                            "folds", folds, "minimum_crossing_displacement", minSpeed,
                            "maximum_camera_frame_step", maxCameraStep,
                            "camera_samples", cameraPositions.size(), "positions",
                            positions));
          persist();
        }
        var baseline = jump(context, server, 8.0);
        var crossing = jump(context, server, 35.2);
        int a = firstAirborne(baseline), b = firstAirborne(crossing);
        double error = 0;
        for (int i = 0; i < Math.min(baseline.size() - a, crossing.size() - b); i++)
          error = Math.max(error, Math.abs(baseline.get(a + i) - crossing.get(b + i)));
        var jumpPositions =
            context.computeOnClient(mc -> new ArrayList<>(walkPositions));
        boolean airborneFold = false;
        for (int i = 1; i < jumpPositions.size(); i++)
          if (jumpPositions.get(i) - jumpPositions.get(i - 1) < -18 &&
              crossing.get(i) > 65.05)
            airborneFold = true;
        checks.add(Map.of("case", "player_jump_rebase", "airborne_fold", airborneFold,
                          "maximum_height_error", error, "baseline", baseline,
                          "crossing", crossing));
        persist();
        check(airborneFold, "Jump crosses the rebase plane while airborne");
        check(error < .001,
              "Relative player teleport preserves the client jump trajectory");
        server.runCommand("gamemode spectator @a");
        server.runCommand("tp @a 0.0 68.0 5.0 180 0");
        context.waitTicks(15);
        context.takeScreenshot("escher-outward");
        context.runOnClient(mc -> mc.options.improvedTransparency().set(true));
        server.runCommand("scoreboard players set #turn escher 799");
        server.runCommand("function escher:send");
        awaitPacket(context, server);
        check(Math.abs(GpuReadback.read(context, "probe").scalar(8) - 799.0 / 1024) <
                  1e-6,
              "GPU decodes the changed twist");
        checks.add(
            Map.of("case", "oit_transport", "data_words", 5, "corner_pixels", 10));
        persist();
        server.runCommand("tp @a -1.0 68.0 3.0 0 8");
        context.waitTicks(15);
        context.takeScreenshot("escher-twist");
        context.getInput().resizeWindow(3456, 2234);
        var qualities = List.of("low", "balanced", "high", "native");
        for (int i = 0; i < qualities.size(); i++) {
          String quality = qualities.get(i);
          server.runCommand("function escher:quality/" + quality);
          awaitPacket(context, server);
          watch(context, 3);
          var target = GpuReadback.read(context, "gallery_" + quality);
          check(countRed(target) > 100, "Each quality renders the analytic scene");
          check(Math.abs(GpuReadback.read(context, "probe").scalar(11) - i) < .01,
                "GPU decodes the selected quality");
          checks.add(Map.of("case", "quality_" + quality, "fps",
                            context.computeOnClient(mc -> mc.getFps()), "render",
                            List.of(target.width(), target.height())));
          persist();
        }
        context.takeScreenshot("escher-large-window");
        server.runCommand("function escher:quality/high");
        awaitPacket(context, server);
        context.getInput().resizeWindow(1280, 900);
        context.runOnClient(
            mc -> mc.player.connection.sendCommand("trigger escher.action set 2"));
        context.waitTicks(12);
        check(GpuReadback.read(context, "probe").scalar(10) == 0,
              "Toggle shows the native collision world");
        context.takeScreenshot("escher-physical-world");
        context.runOnClient(
            mc -> mc.player.connection.sendCommand("trigger escher.action set 2"));
        awaitPacket(context, server);
        server.runCommand("scoreboard players set #turn escher 399");
        server.runCommand("function escher:send");
        server.runCommand("gamemode adventure @a");
        server.runCommand("tp @a 0.0 65.0 2.0 0 0");
        awaitPacket(context, server);
        context.waitTicks(12);
        context.takeScreenshot("escher-ready");
        verifyFolding(context, server);
        report.put("result", "passed");
        persist();
      }
    } catch (Throwable error) {
      report.put("result", "failed");
      report.put("failure", error.toString());
      persist();
      try {
        context.takeScreenshot("escher-failure");
      } catch (Throwable ignored) {
      }
      throw new RuntimeException(error);
    } finally {
      walking = false;
    }
  }
  private void verifyFolding(ClientGameTestContext context, TestServerContext server) {
    server.runCommand("function escher:scene/folding");
    server.runCommand("function escher:quality/low");
    server.runCommand("function escher:folding/balls/pause");
    server.runCommand("function escher:folding/overview");
    server.runCommand("function escher:folding/set {amount:0}");
    awaitFolding(context, server, 0);
    var geometry = GpuReadback.read(context, "probe");
    double maximumJump = 0;
    for (int column = 0; column < 16; column++) {
      for (int side = 0; side < 4; side++)
        check(geometry.scalar(16 + column * 4 + side) < -.005,
              "Every sampled point across a column is solid on the GPU");
      maximumJump = Math.max(maximumJump, Math.abs(geometry.scalar(17 + column * 4) -
                                                   geometry.scalar(18 + column * 4)));
    }
    check(maximumJump < .00021, "Generated periodic column fields are continuous");
    checks.add(Map.of("case", "folding_column_geometry", "interior_samples", 64,
                      "maximum_sdf_jump", maximumJump));
    persist();
    check(context.computeOnClient(mc -> mc.player.isSpectator()),
          "Folding overview uses a gravity-free observer");
    context.getInput().holdKey(InputConstants.KEY_W);
    context.getInput().holdKey(InputConstants.KEY_SPACE);
    watch(context, 1);
    context.getInput().releaseKey(InputConstants.KEY_W);
    context.getInput().releaseKey(InputConstants.KEY_SPACE);
    context.waitTicks(15);
    check(context.computeOnClient(
              mc -> mc.player.position().distanceTo(new Vec3(0, 65, 22))) < .25,
          "Overview movement keeps the player at its observation anchor");
    server.runCommand("tp @a 0 65 22 35 17");
    context.waitTicks(10);
    check(Math.abs(context.computeOnClient(mc -> mc.player.getYRot()) - 35) < .01 &&
              Math.abs(context.computeOnClient(mc -> mc.player.getXRot()) - 17) < .01,
          "Overview anchor preserves mouse orientation");
    server.runCommand("function escher:folding/overview");
    context.waitTicks(10);
    checks.add(Map.of("case", "folding_overview_controls", "anchored", true,
                      "rotation_preserved", true));
    persist();
    context.waitTicks(20);
    var flat = GpuReadback.read(context, "gallery_low");
    context.takeScreenshot("escher-folding-flat");
    for (int amount : new int[] {250, 500, 1000}) {
      server.runCommand("function escher:folding/set {amount:" + amount + "}");
      awaitFolding(context, server, amount / 1000.);
      context.waitTicks(10);
      var picture = GpuReadback.read(context, "gallery_low");
      double difference = imageDifference(flat, picture);
      check(difference > 1, "Folding visibly deforms the architecture");
      checks.add(Map.of("case", "folding_shape_" + amount, "frame_difference",
                        difference, "red_pixels", countRed(picture)));
      persist();
      context.takeScreenshot("escher-folding-" + amount);
    }
    var still = GpuReadback.readBatch(context, "minecraft:end_of_frame",
                                      List.of("frame", "gallery_low"));
    context.waitTicks(15);
    check(Math.abs(GpuReadback.read(context, "frame").scalar(2) -
                   still.get("frame").scalar(2)) < 1e-6,
          "Paused rolling spheres keep their phase");
    server.runCommand("function escher:folding/balls/run");
    awaitPacket(context, server);
    watch(context, 2);
    var moving = GpuReadback.readBatch(context, "minecraft:end_of_frame",
                                       List.of("frame", "gallery_low"));
    double moved = imageDifference(still.get("gallery_low"), moving.get("gallery_low"));
    check(Math.abs(moving.get("frame").scalar(2) - still.get("frame").scalar(2)) > .1,
          "Rolling sphere positions advance with time");
    check(moved > .001, "Rolling spheres change the visible scene");
    checks.add(Map.of("case", "folding_rolling_spheres", "frame_difference", moved,
                      "travel", moving.get("frame").scalar(2), "rotation",
                      moving.get("frame").scalar(7)));
    persist();
    context.takeScreenshot("escher-folding-rolling");
    server.runCommand("function escher:folding/balls/pause");
    server.runCommand("function escher:folding/walk");
    server.runCommand("scoreboard players set #fold escher 0");
    for (int amount : new int[] {0, 500, 1000}) {
      server.runCommand("function escher:folding/set {amount:" + amount + "}");
      awaitFolding(context, server, amount / 1000.);
      server.runCommand("tp @a 0 65 43.9999 0 0");
      context.waitTicks(12);
      var seamBefore = GpuReadback.read(context, "gallery_low");
      server.runCommand("tp @a 0 65 44.0001 0 0");
      context.waitTicks(12);
      double seamError =
          imageDifference(seamBefore, GpuReadback.read(context, "gallery_low"));
      checks.add(Map.of("case", "folding_chart_seam", "amount", amount,
                        "mean_rgb_error", seamError));
      persist();
      check(seamError < .5,
            "Folding view is continuous between adjacent source segments");
      for (int direction : new int[] {1, -1}) {
        server.runCommand("tp @a 0 65 " + (direction == 1 ? "88.25" : "-0.25") + " " +
                          (direction == 1 ? "0" : "180") + " 0");
        context.waitTicks(12);
        var before = GpuReadback.read(context, "gallery_low");
        server.runCommand("execute as @a at @s run function escher:fold/" +
                          (direction == 1 ? "forward" : "backward"));
        context.waitTicks(12);
        double error =
            imageDifference(before, GpuReadback.read(context, "gallery_low"));
        checks.add(Map.of("case", "folding_rebase", "amount", amount, "direction",
                          direction, "mean_rgb_error", error));
        persist();
        check(error < .2, "Folding perspective agrees across either periodic boundary");
      }
    }
    server.runCommand("scoreboard players set #fold escher 1");
    server.runCommand("gamemode adventure @a");
    for (int direction : new int[] {1, -1}) {
      server.runCommand("tp @a 0 65 " + (direction == 1 ? "85.5" : "2.5") + " " +
                        (direction == 1 ? "0" : "180") + " 0");
      context.waitTicks(15);
      context.runOnClient(mc -> {
        walkPositions.clear();
        walking = true;
      });
      context.getInput().holdKey(InputConstants.KEY_W);
      watch(context, 3.75);
      context.getInput().releaseKey(InputConstants.KEY_W);
      context.runOnClient(mc -> walking = false);
      var positions = context.computeOnClient(mc -> new ArrayList<>(walkPositions));
      int crossings = 0;
      for (int i = 1; i < positions.size(); i++)
        if (Math.abs(positions.get(i) - positions.get(i - 1)) > 44)
          crossings++;
      check(crossings > 0, "Folding walking crosses the source boundary");
      check(Math.abs(context.computeOnClient(mc -> mc.player.getY()) - 65) < .01,
            "Folding floor supports walking");
      checks.add(Map.of("case", "folding_walk", "direction", direction, "crossings",
                        crossings));
      persist();
    }
    server.runCommand("function escher:folding/walk");
    context.waitTicks(10);
    context.takeScreenshot("escher-folding-walk");
    server.runCommand("gamemode spectator @a");
    server.runCommand("function escher:folding/overview");
    server.runCommand("function escher:folding/set {amount:0}");
    awaitFolding(context, server, 0);
    server.runCommand("function escher:folding/spiral");
    awaitPacket(context, server);
    watch(context, 1.5);
    double intermediate = GpuReadback.read(context, "probe").scalar(13);
    check(intermediate > 0 && intermediate < 1,
          "Folding morph progresses continuously");
    awaitFolding(context, server, 1);
    checks.add(Map.of("case", "folding_morph", "intermediate", intermediate, "finished",
                      true));
    persist();
    for (String quality : List.of("low", "balanced", "high")) {
      server.runCommand("function escher:quality/" + quality);
      awaitPacket(context, server);
      watch(context, 3);
      checks.add(Map.of("case", "folding_quality_" + quality, "fps",
                        context.computeOnClient(mc -> mc.getFps())));
      persist();
    }
    context.takeScreenshot("escher-folding-ready");
    server.runCommand("function escher:scene/gallery");
    awaitPacket(context, server);
    check(GpuReadback.read(context, "probe").scalar(12) == 0,
          "Scene command returns to the gallery");
    checks.add(Map.of("case", "scene_switching", "passed", true));
    persist();
  }
  private void awaitFolding(ClientGameTestContext context, TestServerContext server,
                            double amount) {
    awaitPacket(context, server);
    for (int attempt = 0; attempt < 100; attempt++) {
      context.waitTicks(10);
      var probe = GpuReadback.read(context, "probe");
      if (probe.scalar(12) == 1 && Math.abs(probe.scalar(13) - amount) < .0001)
        return;
    }
    throw new AssertionError("Folding reaches amount " + amount + ", observed " +
                             GpuReadback.read(context, "probe").scalar(13));
  }
  private List<Double> jump(ClientGameTestContext context, TestServerContext server,
                            double z) {
    server.runCommand("tp @a 0.0 65.0 " + z + " 0 0");
    context.waitTicks(15);
    context.runOnClient(mc -> {
      walkHeights.clear();
      walkPositions.clear();
      walking = true;
    });
    context.getInput().holdKey(InputConstants.KEY_W);
    context.getInput().holdKey(InputConstants.KEY_SPACE);
    context.waitTicks(2);
    context.getInput().releaseKey(InputConstants.KEY_SPACE);
    context.waitTicks(23);
    context.getInput().releaseKey(InputConstants.KEY_W);
    context.runOnClient(mc -> walking = false);
    return context.computeOnClient(mc -> new ArrayList<>(walkHeights));
  }
  private int firstAirborne(List<Double> heights) {
    for (int i = 0; i < heights.size(); i++)
      if (heights.get(i) > 65.001)
        return i;
    throw new AssertionError("Player jumps");
  }
  private void awaitPacket(ClientGameTestContext context, TestServerContext server) {
    for (int attempt = 0; attempt < 60; attempt++) {
      context.waitTicks(2);
      var fields = GpuReadback.readBatch(context, "minecraft:end_of_frame",
                                         List.of("packet", "probe"));
      if (fields == null)
        continue;
      var expected = server.computeOnServer(s
                                            -> s.getCommandStorage()
                                                   .get(Identifier.parse("escher:tx"))
                                                   .getListOrEmpty("colors")
                                                   .stream()
                                                   .map(v -> v.asInt().orElseThrow())
                                                   .toList());
      check(expected.size() == 5, "Region and quality fields are published");
      var packet = fields.get("packet");
      boolean valid =
          (packet.word(0) >>> 8) == 0x455343L && fields.get("probe").scalar(10) == 1;
      for (int i = 0; i < expected.size(); i++)
        valid &= (packet.word(i + 5) >>> 8) == Integer.toUnsignedLong(expected.get(i));
      if (valid)
        return;
    }
    throw new AssertionError(
        "Complete RGB24 packet and camera reach the gallery renderer");
  }
  private double imageDifference(GpuReadback.Image a, GpuReadback.Image b) {
    double sum = 0;
    for (int i = 0; i < a.rgba().length; i++)
      for (int shift : new int[] {8, 16, 24})
        sum += Math.abs(((a.word(i) >> shift) & 255) - ((b.word(i) >> shift) & 255));
    return sum / (a.rgba().length * 3);
  }
  private int countRed(GpuReadback.Image image) {
    int n = 0;
    for (int value : image.rgba()) {
      int r = value >>> 24, g = (value >>> 16) & 255, b = (value >>> 8) & 255;
      if (r > 100 && r > g * 1.4 && r > b * 1.8)
        n++;
    }
    return n;
  }
  private void watch(ClientGameTestContext context, double seconds) {
    long end = System.nanoTime() + (long)(seconds * 1e9);
    context.waitFor(mc -> System.nanoTime() >= end, 12000);
  }
  private void persist() {
    try {
      Files.writeString(Path.of("escher-report.json"),
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
