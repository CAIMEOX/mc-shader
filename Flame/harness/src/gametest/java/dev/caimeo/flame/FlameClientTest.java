package dev.caimeo.flame;

import com.google.gson.GsonBuilder;
import com.google.gson.JsonParser;
import net.fabricmc.fabric.api.client.gametest.v1.FabricClientGameTest;
import net.fabricmc.fabric.api.client.gametest.v1.context.ClientGameTestContext;
import net.fabricmc.fabric.api.client.gametest.v1.context.TestServerContext;
import net.minecraft.core.BlockPos;
import net.minecraft.core.registries.Registries;
import net.minecraft.resources.Identifier;
import net.minecraft.tags.TagKey;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.block.state.properties.BlockStateProperties;
import net.minecraft.world.level.storage.LevelResource;
import java.io.InputStreamReader;
import java.nio.file.*;
import java.util.*;

public final class FlameClientTest implements FabricClientGameTest {
  private static final int N = 16384;
  private static final double AMBIENT = 293.0;
  private final Map<String, Object> report = new LinkedHashMap<>();
  private final List<Map<String, Object>> checks = new ArrayList<>();
  private double[] loads;
  @Override
  public void runTest(ClientGameTestContext context) {
    report.put("result", "running");
    report.put("minecraft", "26.3");
    report.put("checks", checks);
    report.put("presentation", "native visible window");
    try {
      try (var reader = new InputStreamReader(Objects.requireNonNull(
               getClass().getResourceAsStream("/flame-build.json")))) {
        var profiles = JsonParser.parseReader(reader).getAsJsonObject().getAsJsonArray(
            "fuel_profiles");
        loads = profiles.asList()
                    .stream()
                    .mapToDouble(v -> v.getAsJsonObject().get("load").getAsDouble())
                    .toArray();
      }
      var reload = context.computeOnClient(mc -> {
        var packs = mc.getResourcePackRepository();
        packs.reload();
        var ids = new ArrayList<>(packs.getSelectedIds());
        ids.add("file/flame.zip");
        packs.setSelected(ids);
        mc.options.renderDistance().set(5);
        mc.options.enableVsync().set(false);
        mc.options.bobView().set(false);
        mc.options.framerateLimit().set(60);
        mc.options.inactivityFpsLimit().set(
            net.minecraft.client.InactivityFpsLimit.MINIMIZED);
        mc.options.pauseOnLostFocus = false;
        mc.getWindow().setTitle("Flame · combustion and terrain tests");
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
          Files.copy(Path.of("flame-datapack.zip"), dir.resolve("flame.zip"),
                     StandardCopyOption.REPLACE_EXISTING);
          var packs = s.getPackRepository();
          packs.reload();
          var ids = new ArrayList<>(packs.getSelectedIds());
          ids.add("file/flame.zip");
          packs.setSelected(ids);
          return s.reloadResources(ids);
        });
        context.waitFor(mc -> loading.isDone(), 600);
        loading.join();
        context.getInput().resizeWindow(1280, 900);
        server.runCommand("gamemode spectator @a");
        server.runCommand("tp @a 8 70 22 180 25");
        server.runCommand("time set noon");
        context.waitTicks(50);
        world.getConnection().waitForChunksRender(false, 400);
        server.runCommand("function flame:demo");
        awaitReady(context, server);
        verifyTerrain(context, server);
        var originalBlocks = server.computeOnServer(s -> {
          var out = new ArrayList<BlockState>();
          for (int z = 0; z < 16; z++)
            for (int y = 64; y < 72; y++)
              for (int x = 0; x < 16; x++)
                out.add(s.overworld().getBlockState(new BlockPos(x, y, z)));
          return out;
        });
        stage(server, "Flame · igniting wood");
        watch(context, 5);
        var burning = snapshot(context);
        var ignition = metrics(burning);
        record("ignition", ignition);
        screenshot(context, "flame-ignition");
        check(number(ignition, "consumedFuel") > .02, "Ignition consumes exposed fuel");
        check(number(ignition, "maximumTemperature") > 650, "Combustion heats the air");
        check(number(ignition, "reactionSum") > .001, "Gas fuel reacts");
        check(number(ignition, "smokeSum") > .001, "Combustion produces smoke");
        verifyProjection(burning);
        server.runCommand("function flame:source/off");
        stage(server, "Flame · self-sustained combustion");
        watch(context, 2);
        var self = snapshot(context);
        var sustained = metrics(self);
        record("igniter_off", sustained);
        check(number(sustained, "reactionSum") > .001,
              "Burning continues with the igniter off");
        check(number(sustained, "remainingFuel") < number(ignition, "remainingFuel"),
              "Self-sustained burning consumes fuel");
        server.runCommand("tp @a 4.5 68 14.5 180 28");
        watch(context, 2);
        screenshot(context, "flame-close");
        context.getInput().resizeWindow(3456, 2234);
        watch(context, 3);
        screenshot(context, "flame-large-window");
        checks.add(Map.of("case", "large_window", "fps",
                          context.computeOnClient(mc -> mc.getFps()), "framebuffer",
                          context.computeOnClient(
                              mc
                              -> List.of(mc.gameRenderer.mainRenderTarget().width,
                                         mc.gameRenderer.mainRenderTarget().height)),
                          "frame_limit",
                          context.computeOnClient(
                              mc -> mc.getFramerateLimitTracker().getFramerateLimit()),
                          "reactionSum",
                          number(metrics(snapshot(context)), "reactionSum")));
        persist();
        context.getInput().resizeWindow(1280, 900);
        stage(server, "Flame · heat spreads across combustible surfaces");
        watch(context, 12);
        var spread = snapshot(context);
        var spreading = metrics(spread);
        record("spread", spreading);
        screenshot(context, "flame-spread");
        check(number(spreading, "remoteConsumedFuel") > .015,
              "Heat ignites fuel beyond the direct ignition footprint");
        check(number(spreading, "maximumSmokeHeight") > 3.0,
              "Buoyancy carries smoke upward");
        var preserved = server.computeOnServer(s -> {
          int i = 0;
          for (int z = 0; z < 16; z++)
            for (int y = 64; y < 72; y++)
              for (int x = 0; x < 16; x++)
                if (!s.overworld()
                         .getBlockState(new BlockPos(x, y, z))
                         .equals(originalBlocks.get(i++)))
                  return false;
          return true;
        });
        check(preserved, "Visual combustion preserves the original blocks");
        checks.add(
            Map.of("case", "world_preservation", "blocks", 2048, "preserved", true));
        persist();
        context.runOnClient(mc -> mc.options.improvedTransparency().set(true));
        server.runCommand("scoreboard players set #power flame 96");
        server.runCommand("function flame:send");
        awaitPayload(context, server);
        checks.add(Map.of("case", "oit_transport", "complete_payload", true));
        persist();
        server.runCommand("tp @a 14.5 69 15.5 135 20");
        watch(context, 2);
        screenshot(context, "flame-occlusion");
        context.runOnClient(
            mc -> mc.player.connection.sendCommand("trigger flame.action set 2"));
        watch(context, .5);
        var quenched = snapshot(context);
        var extinguished = metrics(quenched);
        record("quench", extinguished);
        check(number(extinguished, "reactionSum") < 1e-7, "Quenching stops combustion");
        check(number(extinguished, "maximumTemperature") < AMBIENT + 1,
              "Quenching cools the gas");
        check(number(extinguished, "remainingFuel") <
                  number(ignition, "initialFuel") - .02,
              "Quenching retains spent fuel");
        watch(context, 2);
        var afterQuench = metrics(snapshot(context));
        check(Math.abs(number(afterQuench, "remainingFuel") -
                       number(extinguished, "remainingFuel")) < 1e-5,
              "Fuel is stable while extinguished");
        check(number(afterQuench, "smokeSum") < number(extinguished, "smokeSum") + .001,
              "Smoke dissipates after extinguishing");
        screenshot(context, "flame-extinguished");
        context.getInput().resizeWindow(1280, 900);

        stage(server, "Flame · sealed stone firebreak");
        server.runCommand("function flame:demo");
        server.runCommand("fill 9 65 0 9 71 15 minecraft:stone_bricks strict");
        server.runCommand("function flame:rescan");
        awaitReady(context, server);
        watch(context, 9);
        var barrier = snapshot(context);
        var blocked = metrics(barrier);
        record("terrain_barrier", blocked);
        double rightSmoke = 0, rightConsumed = 0;
        var solid = barrier.get("solid");
        var thermal = barrier.get("thermal_b");
        var gas = barrier.get("gas_b");
        for (int i = 0; i < N; i++)
          if (i % 32 >= 20) {
            rightSmoke += gas.scalar(i + 2 * N);
            rightConsumed += initial(solid, i) - thermal.scalar(i);
          }
        check(rightSmoke < 1e-5, "Smoke does not cross a sealed solid barrier");
        check(rightConsumed < 1e-5, "The insulated region retains its fuel");
        check(number(blocked, "reactionSum") > .001,
              "The barrier fixture contains an active fire");
        screenshot(context, "flame-barrier");

        fuelSample(server, false);
        awaitReady(context, server);
        watch(context, 3);
        var inert = metrics(snapshot(context));
        record("inert_material", inert);
        check(number(inert, "initialFuel") == 0,
              "Inert terrain provides no combustible fuel");
        check(number(inert, "reactionSum") < 1e-7 && number(inert, "smokeSum") < 1e-7,
              "Ignition alone does not create combustion products");
        stage(server, "Flame · finite fuel burns out");
        fuelSample(server, true);
        awaitReady(context, server);
        watch(context, 30);
        var exhausted = metrics(snapshot(context));
        record("fuel_exhaustion", exhausted);
        check(number(exhausted, "initialFuel") > 0 &&
                  number(exhausted, "remainingFuel") < .001,
              "A heated finite fuel sample is exhausted");
        check(number(exhausted, "reactionSum") < .001,
              "Combustion stops after fuel exhaustion even with the igniter enabled");
        screenshot(context, "flame-burnout");
        server.runCommand("function flame:demo");
        awaitReady(context, server);
        watch(context, 3);
        screenshot(context, "flame-ready");
        report.put("result", "passed");
        persist();
      }
    } catch (Throwable error) {
      report.put("result", "failed");
      report.put("failure", error.toString());
      persist();
      try {
        screenshot(context, "flame-failure");
      } catch (Throwable ignored) {
      }
      throw new RuntimeException(error);
    }
  }
  private void fuelSample(TestServerContext server, boolean combustible) {
    server.runCommand("fill 0 64 0 15 71 15 minecraft:air strict");
    server.runCommand("fill 0 64 0 15 64 15 minecraft:stone strict");
    if (combustible)
      server.runCommand("setblock 3 65 8 minecraft:oak_planks strict");
    server.runCommand("execute positioned 0 64 0 run function flame:start");
  }
  private Map<String, GpuReadback.Image> snapshot(ClientGameTestContext context) {
    return GpuReadback.readBatch(context, "minecraft:end_of_frame",
                                 List.of("thermal_b", "gas_b", "solid", "control_b",
                                         "velocity_b", "velocity_work"));
  }
  private int channel(GpuReadback.Image image, int i, int channel) {
    return (int)((image.word(i) >>> ((3 - channel) * 8)) & 255);
  }
  private double initial(GpuReadback.Image solid, int i) {
    return channel(solid, i, 0) > 0 && channel(solid, i, 2) > 0
        ? loads[channel(solid, i, 1)]
        : 0;
  }
  private Map<String, Object> metrics(Map<String, GpuReadback.Image> fields) {
    var solid = fields.get("solid");
    var thermal = fields.get("thermal_b");
    var gas = fields.get("gas_b");
    double remaining = 0, initial = 0, remote = 0, maxTemperature = AMBIENT, smoke = 0,
           reaction = 0, maxHeight = 0, minOxygen = 1, maxSolidHeat = AMBIENT;
    int pyrolyzing = 0;
    for (int i = 0; i < N; i++) {
      double fuel = thermal.scalar(i), heat = thermal.scalar(i + N),
             rate = thermal.scalar(i + 2 * N), start = initial(solid, i);
      check(Double.isFinite(fuel) && Double.isFinite(heat) && Double.isFinite(rate),
            "Finite surface state");
      check(fuel >= -1e-6 && fuel <= start + 1e-5,
            "Fuel remains within its initial capacity");
      check(rate >= 0, "Pyrolysis is nonnegative");
      remaining += fuel;
      initial += start;
      maxSolidHeat = Math.max(maxSolidHeat, heat);
      if (rate > 1e-4)
        pyrolyzing++;
      if (i % 32 >= 12)
        remote += start - fuel;
      for (int kind = 0; kind < 5; kind++)
        check(Double.isFinite(gas.scalar(i + kind * N)), "Finite gas state");
      double temperature = gas.scalar(i), vapor = gas.scalar(i + N),
             density = gas.scalar(i + 2 * N), oxygen = gas.scalar(i + 3 * N),
             burn = gas.scalar(i + 4 * N);
      check(temperature >= AMBIENT - .01 && temperature <= 2300.1,
            "Bounded gas temperature");
      check(vapor >= -1e-7 && density >= -1e-7 && oxygen >= -1e-7 && oxygen <= 1.0001 &&
                burn >= -1e-7,
            "Nonnegative chemistry and bounded oxygen");
      if (channel(solid, i, 0) > 0)
        check(vapor + density + burn < 1e-7, "Combustion products stay outside solids");
      maxTemperature = Math.max(maxTemperature, temperature);
      minOxygen = Math.min(minOxygen, oxygen);
      smoke += density;
      reaction += burn;
      if (density > .001)
        maxHeight = Math.max(maxHeight, ((i / 32) % 16 + .5) * .5);
    }
    var out = new LinkedHashMap<String, Object>();
    out.put("initialFuel", initial);
    out.put("remainingFuel", remaining);
    out.put("consumedFuel", initial - remaining);
    out.put("remoteConsumedFuel", remote);
    out.put("maximumTemperature", maxTemperature);
    out.put("maximumSolidTemperature", maxSolidHeat);
    out.put("smokeSum", smoke);
    out.put("reactionSum", reaction);
    out.put("minimumOxygen", minOxygen);
    out.put("pyrolyzingCells", pyrolyzing);
    out.put("maximumSmokeHeight", maxHeight);
    out.put("simulatedSeconds", fields.get("control_b").word(4) / 30.0);
    return out;
  }
  private void verifyProjection(Map<String, GpuReadback.Image> fields) {
    var solid = fields.get("solid");
    var before = fields.get("velocity_work");
    var after = fields.get("velocity_b");
    double pre = 0, post = 0;
    int cells = 0;
    for (int i = 0; i < N; i++) {
      int x = i % 32, y = i / 32 % 16, z = i / 512;
      boolean occupied = channel(solid, i, 0) > 0;
      for (int a = 0; a < 3; a++) {
        int xx = x + (a == 0 ? 1 : 0), yy = y + (a == 1 ? 1 : 0),
            zz = z + (a == 2 ? 1 : 0);
        boolean blocked = occupied || xx >= 32 || zz >= 32 ||
                          (yy < 16 && channel(solid, xx + 32 * (yy + 16 * zz), 0) > 0);
        if (blocked)
          check(Math.abs(after.scalar(i + a * N)) < 1e-7,
                "Solid faces have zero normal flow");
      }
      if (occupied)
        continue;
      double d0 = 0, d1 = 0;
      for (int a = 0; a < 3; a++) {
        int stride = a == 0 ? 1 : a == 1 ? 32 : 512;
        boolean negative = a == 0 ? x > 0 : a == 1 ? y > 0 : z > 0;
        d0 += (before.scalar(i + a * N) -
               (negative ? before.scalar(i - stride + a * N) : 0)) /
              .5;
        d1 += (after.scalar(i + a * N) -
               (negative ? after.scalar(i - stride + a * N) : 0)) /
              .5;
      }
      pre += d0 * d0;
      post += d1 * d1;
      cells++;
    }
    checks.add(Map.of("case", "pressure_projection", "beforeRms",
                      Math.sqrt(pre / cells), "afterRms", Math.sqrt(post / cells),
                      "ratio", Math.sqrt(post / Math.max(pre, 1e-12))));
    persist();
    check(post <= pre * 1.01, "Pressure projection reduces divergence");
  }
  private void verifyTerrain(ClientGameTestContext context, TestServerContext server)
      throws Exception {
    int[] palette;
    try (var reader = new InputStreamReader(Objects.requireNonNull(
             getClass().getResourceAsStream("/flame-build.json")))) {
      palette = JsonParser.parseReader(reader)
                    .getAsJsonObject()
                    .getAsJsonArray("shape_masks")
                    .asList()
                    .stream()
                    .mapToInt(v -> v.getAsInt())
                    .toArray();
    }
    var expected = server.computeOnServer(s -> {
      var out = new ArrayList<int[]>();
      var level = s.overworld();
      for (int z = 0; z < 16; z++)
        for (int y = 0; y < 8; y++)
          for (int x = 0; x < 16; x++) {
            var p = new BlockPos(x, 64 + y, z);
            var state = level.getBlockState(p);
            var boxes = state.getCollisionShape(level, p).toAabbs();
            int mask = 0;
            for (int bit = 0; bit < 8; bit++) {
              double xx = (bit & 1) == 0 ? .25 : .75, yy = (bit & 2) == 0 ? .25 : .75,
                     zz = (bit & 4) == 0 ? .25 : .75;
              if (boxes.stream().anyMatch(b -> b.contains(xx, yy, zz)))
                mask |= 1 << bit;
            }
            out.add(new int[] {mask, material(state)});
          }
      return out;
    });
    var images = GpuReadback.readBatch(context, "minecraft:end_of_frame",
                                       List.of("terrain", "solid"));
    var terrain = images.get("terrain");
    var solid = images.get("solid");
    int[] materials = new int[4];
    for (int i = 0; i < 2048; i++) {
      int id = terrain.red(i), m = channel(terrain, i, 1);
      check(id < palette.length, "Known demo collision shape");
      check(palette[id] == expected.get(i)[0],
            "Terrain matches vanilla collision geometry");
      check(m == expected.get(i)[1], "Material profile matches the original block");
      materials[m]++;
    }
    for (int i = 0; i < N; i++) {
      int x = i % 32, y = i / 32 % 16, z = i / 512,
          b = x / 2 + 16 * (y / 2 + 8 * (z / 2)),
          oct = x % 2 + 2 * (y % 2) + 4 * (z % 2);
      check((solid.red(i) > 0) == ((expected.get(b)[0] & (1 << oct)) != 0),
            "Expanded gas obstacles match block geometry");
    }
    awaitPayload(context, server);
    checks.add(Map.of("case", "terrain_and_material_transport", "blocks", 2048,
                      "voxels", N, "materialCounts", materials));
    persist();
  }
  private int material(BlockState state) {
    if (state.hasProperty(BlockStateProperties.WATERLOGGED) &&
        state.getValue(BlockStateProperties.WATERLOGGED))
      return 0;
    for (String name : List.of("logs", "planks", "wooden_stairs", "wooden_slabs"))
      if (state.is(
              TagKey.create(Registries.BLOCK, Identifier.parse("minecraft:" + name))))
        return 1;
    if (state.is(TagKey.create(Registries.BLOCK, Identifier.parse("minecraft:leaves"))))
      return 2;
    for (String name : List.of("wool", "wool_stairs", "wool_slabs"))
      if (state.is(
              TagKey.create(Registries.BLOCK, Identifier.parse("minecraft:" + name))))
        return 3;
    return 0;
  }
  private void awaitReady(ClientGameTestContext context, TestServerContext server) {
    context.waitTicks(15);
    long epoch = server
                     .computeOnServer(s
                                      -> s.getCommandStorage()
                                             .get(Identifier.parse("flame:tx"))
                                             .getListOrEmpty("colors")
                                             .get(0)
                                             .asInt()
                                             .orElseThrow())
                     .longValue();
    for (int n = 0; n < 100; n++) {
      context.waitTicks(2);
      var image = GpuReadback.read(context, "control_b");
      if (image != null && image.word(0) == epoch && image.word(6) == 1 &&
          image.word(4) >= 2)
        return;
    }
    throw new AssertionError("Complete terrain packet reaches the fire solver");
  }
  private void awaitPayload(ClientGameTestContext context, TestServerContext server) {
    var words = server.computeOnServer(s
                                       -> s.getCommandStorage()
                                              .get(Identifier.parse("flame:tx"))
                                              .getListOrEmpty("colors")
                                              .stream()
                                              .map(v -> v.asInt().orElseThrow())
                                              .toList());
    for (int n = 0; n < 60; n++) {
      context.waitTicks(2);
      var packet = GpuReadback.read(context, "packet");
      boolean ok = packet != null && (packet.word(0) & 255) != 0;
      if (ok)
        for (int i = 0; i < words.size(); i++)
          if ((packet.word(i + 5) >>> 8) != Integer.toUnsignedLong(words.get(i))) {
            ok = false;
            break;
          }
      if (ok)
        return;
    }
    throw new AssertionError("The item_display RGB payload is complete");
  }
  private void record(String name, Map<String, Object> values) {
    values.put("case", name);
    checks.add(values);
    persist();
  }
  private double number(Map<String, Object> values, String name) {
    return ((Number)values.get(name)).doubleValue();
  }
  private void watch(ClientGameTestContext context, double seconds) {
    long end = System.nanoTime() + (long)(seconds * 1e9);
    context.waitFor(mc -> System.nanoTime() >= end, 12000);
  }
  private void stage(TestServerContext server, String text) {
    server.runCommand("title @a actionbar " + new GsonBuilder().create().toJson(text));
  }
  private void screenshot(ClientGameTestContext context, String name) {
    context.takeScreenshot(name);
  }
  private void persist() {
    try {
      Files.writeString(Path.of("flame-report.json"),
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
