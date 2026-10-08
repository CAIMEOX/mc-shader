package dev.caimeo.backrooms;

import com.google.gson.GsonBuilder;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import com.mojang.serialization.JsonOps;
import com.mojang.blaze3d.platform.InputConstants;
import net.fabricmc.fabric.api.client.gametest.v1.FabricClientGameTest;
import net.fabricmc.fabric.api.client.gametest.v1.context.ClientGameTestContext;
import net.fabricmc.fabric.api.client.gametest.v1.context.TestServerContext;
import net.minecraft.core.BlockPos;
import net.minecraft.core.Direction;
import net.minecraft.world.level.block.StairBlock;
import net.minecraft.core.registries.Registries;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.world.level.block.Block;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.nbt.NbtUtils;
import net.minecraft.resources.Identifier;
import net.minecraft.resources.ResourceKey;
import net.minecraft.server.level.ServerLevel;
import net.minecraft.world.level.Level;
import net.minecraft.world.level.block.Blocks;
import net.minecraft.world.level.block.Rotation;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.level.levelgen.structure.PoolElementStructurePiece;
import net.minecraft.world.level.levelgen.structure.pools.SinglePoolElement;
import net.minecraft.world.level.levelgen.structure.templatesystem.StructurePlaceSettings;
import net.minecraft.world.level.levelgen.structure.templatesystem.StructureTemplate;
import net.minecraft.world.level.storage.LevelResource;
import java.awt.image.BufferedImage;
import javax.imageio.ImageIO;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.security.MessageDigest;
import java.util.*;
import java.util.zip.ZipFile;

import net.minecraft.world.level.levelgen.RandomState;
import net.minecraft.world.level.levelgen.densityfunction.DensitySampler;
import net.minecraft.world.level.levelgen.densityfunction.SamplerContext;
import net.minecraft.world.level.chunk.status.ChunkStatus;
public final class WorldGenClientTest implements FabricClientGameTest {
  private static final ResourceKey<Level> DIM =
      ResourceKey.create(Registries.DIMENSION, Identifier.parse("backrooms:interior"));
  private final Map<String, Object> report = new LinkedHashMap<>();
  private final List<Map<String, Object>> checks = new ArrayList<>();
  private record Placed(Identifier template, PoolElementStructurePiece piece,
                        JsonObject layout, Map<BlockPos, BlockState> blocks) {}
  private final List<Placed> placed = new ArrayList<>();
  private JsonObject descriptor;
  private int observedSight;
  private record View(BlockPos point, float yaw, String name) {}
  private final List<View> views = new ArrayList<>();
  private record Paint(String mask, BlockState state) {}
  private record Core(int kind, String name, BlockPos origin, boolean swapped, int size,
                      JsonObject spec) {}
  private final List<Core> cores = new ArrayList<>();

  @Override
  public void runTest(ClientGameTestContext context) {
    if (Boolean.getBoolean("backrooms.test.lab"))
      return;
    report.put("result", "running");
    report.put("minecraft", "26.3");
    report.put("mode", "WorldGen");
    report.put("architecture", "runtime density partitions");
    report.put("palette", "level0");
    report.put("layout_profile", "runtime_level0");
    report.put("checks", checks);
    try {
      try (var stream = getClass().getResourceAsStream("/worldgen.json")) {
        descriptor =
            JsonParser
                .parseString(new String(Objects.requireNonNull(stream).readAllBytes(),
                                        StandardCharsets.UTF_8))
                .getAsJsonObject();
      }
      var reload = context.computeOnClient(mc -> {
        var packs = mc.getResourcePackRepository();
        packs.reload();
        packs.setSelected(List.of("vanilla", "file/backrooms-level0.zip"));
        mc.options.renderDistance().set(5);
        mc.options.bobView().set(false);
        mc.options.enableVsync().set(false);
        mc.options.framerateLimit().set(60);
        mc.options.pauseOnLostFocus = false;
        mc.options.chatOpacity().set(0.0);
        mc.options.textBackgroundOpacity().set(0.0);
        mc.getWindow().setTitle("Backrooms · Runtime Architecture");
        return mc.reloadResourcePacks();
      });
      context.waitFor(mc -> reload.isDone(), 1200);
      reload.join();
      context.waitFor(mc -> mc.gui.overlay() == null, 500);
      verifyMaterials(context);
      try (var world =
               context.worldBuilder()
                   .adjustSettings(settings -> settings.setGenerateStructures(true))
                   .create()) {
        var server = world.getServer();
        var loading = server.computeOnServer(s -> {
          var directory = s.getWorldPath(LevelResource.DATAPACK_DIR);
          Files.createDirectories(directory);
          Files.copy(Path.of("backrooms-datapack.zip"),
                     directory.resolve("backrooms.zip"),
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
        verifyResources(server);
        var original = server.computeOnServer(
            s -> s.getPlayerList().getPlayers().getFirst().position());
        var mode = server.computeOnServer(s
                                          -> s.getPlayerList()
                                                 .getPlayers()
                                                 .getFirst()
                                                 .gameMode.getGameModeForPlayer());
        server.runOnServer(s
                           -> ((net.minecraft.client.server.IntegratedServer)s)
                                  .setWorldAllowCommands(true));
        server.runCommand("execute as @a at @s run function backrooms:enter");
        context.waitFor(
            mc -> mc.player != null && mc.player.level().dimension().equals(DIM), 1000);
        world.getConnection().waitForChunksRender(false, 1000);
        context.getInput().resizeWindow(1280, 720);
        context.waitTicks(20);
        context.takeScreenshot("runtime-entrance");
        server.runOnServer(s -> verifySeedRules(s.getLevel(DIM)));
        server.runOnServer(s -> verifySpatialDiversity(s.getLevel(DIM)));
        persist();
        context.waitTick();
        server.runOnServer(s -> verifyTerrain(s.getLevel(DIM)));
        server.runOnServer(s -> verifyLayeredTerrain(s.getLevel(DIM)));
        server.runOnServer(
            s
            -> verifyChunkOrder(
                s.getLevel(DIM),
                s.getLevel(ResourceKey.create(Registries.DIMENSION,
                                              Identifier.parse("backrooms:lobby")))));
        server.runOnServer(s -> verifyGenerationPerformance(s.getLevel(DIM)));
        verifyNativeWalk(context, server);
        persist();
        context.waitTick();
        for (var view : views) {
          teleport(server, view.point.getX() + .5, view.point.getY(),
                   view.point.getZ() + .5, view.yaw, -3);
          world.getConnection().waitForChunksRender(false, 1000);
          context.waitTicks(20);
          context.takeScreenshot("runtime-" + view.name);
        }
        check(observedSight <= 18,
              "Ordinary rooms retain enclosed sight distances: " + observedSight);
        server.runOnServer(s -> discoverLandmarks(s.getLevel(DIM)));
        persist();
        for (var plan : placed) {
          server.runOnServer(s -> {
            inspectLandmark(s.getLevel(DIM), plan);
            verifyConnectivity(s.getLevel(DIM), plan);
          });
          persist();
          context.waitTick();
        }
        verifyLandmarkMovement(context, server);
        verifyVerticalMovement(context, server);
        server.runCommand("execute as @a at @s run function backrooms:home");
        context.waitTicks(12);
        check(server.computeOnServer(s -> {
          var p = s.getPlayerList().getPlayers().getFirst();
          return Math.abs(p.getX() - .5) < .01 && Math.abs(p.getZ() - .5) < .01;
        }),
              "Home returns to the entrance");
        server.runCommand("execute as @a at @s run function backrooms:exit");
        context.waitTicks(12);
        check(server.computeOnServer(s -> {
          var p = s.getPlayerList().getPlayers().getFirst();
          return p.level().dimension().equals(Level.OVERWORLD) &&
              p.position().distanceTo(original) < .01 &&
              p.gameMode.getGameModeForPlayer() == mode;
        }),
              "Exit restores the player's session");
        checks.add(Map.of("case", "session_controls", "home", true, "exit", true));
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

  private final class Rules {
    final ServerLevel level;
    final RandomState random;
    final Map<String, DensitySampler.Bound> samplers = new HashMap<>();
    final List<Paint> paints = new ArrayList<>();
    final net.minecraft.world.level.levelgen.densityfunction.DensitySamplerSet bound;
    Rules(ServerLevel level, long seed) {
      this.level = level;
      for (var value : descriptor.getAsJsonArray("material_masks")) {
        var material = value.getAsJsonObject();
        paints.add(
            new Paint(material.get("mask").getAsString(),
                      BlockState.CODEC.parse(JsonOps.INSTANCE, material.get("state"))
                          .getOrThrow()));
      }
      var settings = level.registryAccess()
                         .lookupOrThrow(Registries.NOISE_SETTINGS)
                         .getValue(Identifier.parse("backrooms:interior"));
      random = RandomState.create(
          level.registryAccess().lookupOrThrow(Registries.NOISE), seed, settings);
      bound =
          random.samplersWithContext(SamplerContext.builder().enableCaches().build());
    }
    float value(String name, int x, int y, int z) {
      return samplers
          .computeIfAbsent(name,
                           key
                           -> bound.get(level.registryAccess()
                                            .lookupOrThrow(Registries.DENSITY_FUNCTION)
                                            .getValue(Identifier.parse(
                                                "backrooms:interior/" + key))))
          .sampleValue(x, y, z);
    }
    BlockState blockAt(int x, int y, int z) {
      if (value("solid", x, y, z) <= 0)
        return Blocks.AIR.defaultBlockState();
      for (var paint : paints)
        if (value(paint.mask, x, y, z) > 0)
          return paint.state;
      return Blocks.STONE.defaultBlockState();
    }
  }
  private void verifyNativeWalk(ClientGameTestContext context,
                                TestServerContext server) {
    var lane = server.computeOnServer(s -> {
      var level = s.getLevel(DIM);
      for (int x = -32; x <= 80; x += 16)
        for (int z = -40; z < 88; z++) {
          boolean free = true;
          for (int a = x - 4; a <= x + 4; a++)
            free &= clear(level, new BlockPos(a, 64, z));
          if (free)
            return new BlockPos(x, 64, z);
        }
      throw new IllegalStateException("A generated route must cross a chunk boundary");
    });
    teleport(server, lane.getX() - 3.5, 64, lane.getZ() + .5, -90, 0);
    context.waitTicks(12);
    context.getInput().holdKey(InputConstants.KEY_W);
    context.waitTicks(40);
    context.getInput().releaseKey(InputConstants.KEY_W);
    context.waitTicks(8);
    double x =
        server.computeOnServer(s -> s.getPlayerList().getPlayers().getFirst().getX());
    check(x > lane.getX() + 3,
          "Native walking crosses the runtime-generated chunk boundary");
    checks.add(
        Map.of("case", "runtime_native_walk", "boundary_x", lane.getX(), "final_x", x));
  }

  private int[] walkLevels() {
    var levels = descriptor.getAsJsonArray("walk_levels");
    int[] result = new int[levels.size()];
    for (int i = 0; i < result.length; i++)
      result[i] = levels.get(i).getAsInt();
    return result;
  }

  private BlockPos corePoint(Core core, BlockPos local) {
    return new BlockPos(
        core.origin.getX() + (core.swapped ? local.getZ() : local.getX()), local.getY(),
        core.origin.getZ() + (core.swapped ? local.getX() : local.getZ()));
  }

  private void verifyLayeredTerrain(ServerLevel level) throws Exception {
    var rules = new Rules(level, level.getSeed());
    var masks = boxes(level, -48, 192);
    var layouts = new HashSet<BitSet>();
    var samples = 0;
    var levels = walkLevels();
    var atlas = new BufferedImage(312 * levels.length, 328, BufferedImage.TYPE_INT_RGB);
    var graphics = atlas.createGraphics();
    for (int i = 0; i < levels.length; i++) {
      int floor = levels[i];
      var footprint = new BitSet(48 * 48);
      for (int x = 0; x < 48; x++)
        for (int z = 0; z < 48; z++)
          if (rules.value("wall", x, floor, z) > 0)
            footprint.set(x * 48 + z);
      layouts.add(footprint);
      graphics.setColor(java.awt.Color.WHITE);
      graphics.drawString("Y=" + floor, i * 312 + 12, 20);
      for (int x = -48; x < 96; x++)
        for (int z = -48; z < 96; z++) {
          var p = new BlockPos(x, floor, z);
          int color = !bodyClear(level, p.above()) ? 0x514933
                      : !bodyClear(level, p)       ? 0x8c633f
                      : !clear(level, p)           ? 0x172329
                                                   : 0xbcaa77;
          graphics.setColor(new java.awt.Color(color));
          graphics.fillRect(i * 312 + 12 + (x + 48) * 2, 32 + (z + 48) * 2, 2, 2);
          boolean feature = masks.stream().anyMatch(b -> b.isInside(p));
          if (feature || floor == 64)
            continue;
          for (int y = floor - 1; y < floor + 11; y++) {
            var position = new BlockPos(x, y, z);
            check(level.getBlockState(position).equals(rules.blockAt(x, y, z)),
                  "Layered terrain matches density and block states at " + position);
            samples++;
          }
        }
    }
    graphics.dispose();
    Files.createDirectories(Path.of("screenshots"));
    ImageIO.write(atlas, "png", Path.of("screenshots/runtime-floors.png").toFile());
    check(layouts.size() == levels.length, "Each floor has its own runtime room plan");
    var found = new TreeMap<Integer, Core>();
    for (int radius = 0;
         radius <= 8 &&
         found.size() < descriptor.getAsJsonArray("vertical_cores").size() * 2;
         radius++)
      for (int gx = -radius; gx <= radius; gx++)
        for (int gz = -radius; gz <= radius; gz++) {
          if (Math.max(Math.abs(gx), Math.abs(gz)) != radius)
            continue;
          int ox = gx * 48, oz = gz * 48;
          if (rules.value("vertical/active", ox, 64, oz) == 0)
            continue;
          int kind = Math.round(rules.value("vertical/kind", ox, 64, oz));
          boolean swapped = rules.value("vertical/transpose", ox, 64, oz) > 0;
          int key = kind * 2 + (swapped ? 1 : 0);
          if (found.containsKey(key))
            continue;
          var spec =
              descriptor.getAsJsonArray("vertical_cores").get(kind).getAsJsonObject();
          int lx = Math.round(rules.value("vertical/lo_x", ox, 64, oz)),
              lz = Math.round(rules.value("vertical/lo_z", ox, 64, oz));
          var core = new Core(kind, spec.get("name").getAsString(),
                              new BlockPos(ox + lx, 0, oz + lz), swapped,
                              spec.get("size").getAsInt(), spec);
          for (int floor : levels) {
            check(rules.value("vertical/lo_x", ox, floor, oz) == lx &&
                      rules.value("vertical/lo_z", ox, floor, oz) == lz &&
                      Math.round(rules.value("vertical/kind", ox, floor, oz)) == kind &&
                      (rules.value("vertical/transpose", ox, floor, oz) > 0) == swapped,
                  "All floors share the same vertical core descriptor");
          }
          found.put(key, core);
        }
    check(found.size() == descriptor.getAsJsonArray("vertical_cores").size() * 2,
          "Both orientations of every vertical core occur");
    cores.addAll(found.values());
    var catalog = new ArrayList<Map<String, Object>>();
    var cameraKinds = new HashSet<Integer>();
    for (var core : cores) {
      var landmarkBoxes =
          boxes(level, Math.min(core.origin.getX(), core.origin.getZ()) - 64,
                Math.max(core.origin.getX(), core.origin.getZ()) + core.size + 64);
      for (var box : landmarkBoxes)
        check(
            !(box.maxX() >= core.origin.getX() - 3 &&
              box.minX() < core.origin.getX() + core.size + 3 &&
              box.maxZ() >= core.origin.getZ() - 3 &&
              box.minZ() < core.origin.getZ() + core.size + 3),
            "Vertical core reservations and landmark pieces have disjoint footprints");
      for (int x = core.origin.getX() - 3; x < core.origin.getX() + core.size + 3; x++)
        for (int z = core.origin.getZ() - 3; z < core.origin.getZ() + core.size + 3;
             z++)
          for (int y = levels[0] - 1; y <= levels[levels.length - 1] + 5; y++) {
            var p = new BlockPos(x, y, z);
            var expected = rules.blockAt(x, y, z);
            check(level.getBlockState(p).equals(expected),
                  "Native core geometry and block properties match at " + p +
                      " expected " + expected + " got " + level.getBlockState(p));
            samples++;
          }
      if (cameraKinds.add(core.kind))
        for (int floor : levels) {
          var p = corePoint(core, new BlockPos(1, floor, 2));
          check(clear(level, p), "Core camera is on an accessible landing");
          views.add(new View(p, -45, "vertical-" + core.name + "-" + floor));
        }
      catalog.add(Map.of("kind", core.name, "origin",
                         List.of(core.origin.getX(), core.origin.getZ()), "transposed",
                         core.swapped));
    }
    var nodes = new HashSet<BlockPos>();
    for (int x = 0; x < 192; x++)
      for (int z = 0; z < 192; z++)
        for (int y = levels[0]; y <= levels[levels.length - 1] + 1; y++) {
          var p = new BlockPos(x, y, z);
          boolean route = Arrays.stream(levels).anyMatch(f -> f == p.getY()) ||
                          rules.value("vertical/owned", x, y, z) > 0 ||
                          masks.stream().anyMatch(box -> box.isInside(p));
          if (route && navigable(level, p))
            nodes.add(p);
        }
    var reached = flood3d(level, nodes, new BlockPos(0, 64, 0));
    check(reached.equals(nodes),
          "Three floors and their cores form a connected navigation graph: missing " +
              (nodes.size() - reached.size()) + " " +
              nodes.stream().filter(p -> !reached.contains(p)).limit(5).toList());
    checks.add(Map.of("case", "layered_native_geometry", "walk_levels",
                      Arrays.stream(levels).boxed().toList(), "distinct_floor_plans",
                      layouts.size(), "voxel_samples", samples, "nodes", nodes.size(),
                      "reachable", reached.size(), "cores", catalog));
    persist();
  }

  private Set<BlockPos> flood3d(ServerLevel level, Set<BlockPos> allowed,
                                BlockPos origin) {
    var seen = new HashSet<BlockPos>();
    var queue = new ArrayDeque<BlockPos>();
    seen.add(origin);
    queue.add(origin);
    while (!queue.isEmpty()) {
      var p = queue.remove();
      for (int[] d : new int[][] {{1, 0}, {-1, 0}, {0, 1}, {0, -1}})
        for (int dy : new int[] {0, -1, 1}) {
          var q = p.offset(d[0], dy, d[1]);
          if ((dy <= 0 || bodyClear(level, p.above(2))) && allowed.contains(q) &&
              seen.add(q))
            queue.add(q);
        }
      for (int dy : new int[] {-1, 1}) {
        var q = p.above(dy);
        if (onLadder(level, p) && onLadder(level, q) && allowed.contains(q) &&
            seen.add(q))
          queue.add(q);
      }
    }
    return seen;
  }

  private void verifyChunkOrder(ServerLevel first, ServerLevel second) {
    check(first.getSeed() == second.getSeed(),
          "Chunk-order fixtures share a world seed");
    var rules = new Rules(first, first.getSeed());
    int ox = descriptor.get("landmark_spacing").getAsInt() * 32 + 48, oz = ox;
    int minX = ox + Math.round(rules.value("vertical/lo_x", ox, 64, oz)) - 3;
    int minZ = oz + Math.round(rules.value("vertical/lo_z", ox, 64, oz)) - 3;
    int size = Math.round(rules.value("vertical/size", ox, 64, oz)) + 6;
    var chunks = new ArrayList<int[]>();
    for (int cx = Math.floorDiv(minX, 16); cx <= Math.floorDiv(minX + size - 1, 16);
         cx++)
      for (int cz = Math.floorDiv(minZ, 16); cz <= Math.floorDiv(minZ + size - 1, 16);
           cz++)
        chunks.add(new int[] {cx, cz});
    for (var chunk : chunks)
      first.getChunk(chunk[0], chunk[1]);
    Collections.reverse(chunks);
    for (var chunk : chunks)
      second.getChunk(chunk[0], chunk[1]);
    int samples = 0;
    for (int x = minX; x < minX + size; x++)
      for (int z = minZ; z < minZ + size; z++)
        for (int y = walkLevels()[0] - 1;
             y <= walkLevels()[walkLevels().length - 1] + 5; y++) {
          var p = new BlockPos(x, y, z);
          check(first.getBlockState(p).equals(second.getBlockState(p)),
                "Chunk generation order preserves layered block states at " + p);
          samples++;
        }
    checks.add(Map.of("case", "chunk_order_consistency", "chunks_per_dimension",
                      chunks.size(), "samples", samples));
  }

  private void walkTo(ClientGameTestContext context, TestServerContext server,
                      BlockPos target) {
    var origin = server.computeOnServer(
        s -> s.getPlayerList().getPlayers().getFirst().position());
    float yaw = (float)Math.toDegrees(
        Math.atan2(origin.x - target.getX() - .5, target.getZ() + .5 - origin.z));
    context.runOnClient(mc -> {
      mc.player.setYRot(yaw);
      mc.player.setXRot(0);
    });
    context.getInput().holdKey(InputConstants.KEY_W);
    try {
      context.waitFor(mc
                      -> mc.player != null &&
                             Math.hypot(mc.player.getX() - target.getX() - .5,
                                        mc.player.getZ() - target.getZ() - .5) < .55 &&
                             Math.abs(mc.player.getY() - target.getY()) < .15,
                      220);
    } catch (AssertionError error) {
      var position = server.computeOnServer(
          s -> s.getPlayerList().getPlayers().getFirst().position());
      context.takeScreenshot("vertical-walk-diagnostic");
      throw new IllegalStateException("Walking from " + origin + " to " + target +
                                          " stopped at " + position,
                                      error);
    } finally {
      context.getInput().releaseKey(InputConstants.KEY_W);
    }
    context.waitTicks(4);
    check(server.computeOnServer(
              s
              -> Math.abs(s.getPlayerList().getPlayers().getFirst().getY() -
                          target.getY()) < .15),
          "Walking reaches the planned landing at " + target);
  }

  private void verifyVerticalMovement(ClientGameTestContext context,
                                      TestServerContext server) {
    var visited = new HashSet<Integer>();
    for (var core : cores) {
      if (!visited.add(core.kind))
        continue;
      var path = new ArrayList<BlockPos>();
      for (var point : core.spec.getAsJsonArray("stair_path"))
        path.add(corePoint(core, readPoint(point.getAsJsonArray())));
      if (!path.isEmpty()) {
        var start = path.getFirst();
        teleport(server, start.getX() + .5, start.getY(), start.getZ() + .5, 0, 0);
        context.waitTicks(12);
        for (var target : path.subList(1, path.size()))
          walkTo(context, server, target);
        context.takeScreenshot("vertical-" + core.name + "-ascent");
        Collections.reverse(path);
        for (var target : path.subList(1, path.size()))
          walkTo(context, server, target);
        checks.add(Map.of("case", "native_vertical_stairs", "kind", core.name,
                          "lower_y", path.getLast().getY(), "upper_y",
                          path.getFirst().getY(), "round_trip", true));
      } else {
        var route = core.spec.getAsJsonObject("ladder");
        var lower = corePoint(core, readPoint(route.getAsJsonArray("lower")));
        var upper = corePoint(core, readPoint(route.getAsJsonArray("upper")));
        float yaw = core.swapped ? 0 : -90;
        teleport(server, lower.getX() + .5, lower.getY(), lower.getZ() + .5, yaw, -15);
        context.waitTicks(12);
        context.getInput().holdKey(InputConstants.KEY_W);
        context.waitTicks((upper.getY() - lower.getY()) * 8 + 35);
        context.getInput().releaseKey(InputConstants.KEY_W);
        context.waitTicks(8);
        check(server.computeOnServer(
                  s
                  -> Math.abs(s.getPlayerList().getPlayers().getFirst().getY() -
                              upper.getY()) < .1),
              "Vertical ladder exits onto the top floor");
        context.takeScreenshot("vertical-ladder-ascent");
        teleport(server, lower.getX() + .5, upper.getY(), lower.getZ() + .5, yaw, 35);
        context.waitTicks((upper.getY() - lower.getY()) * 10 + 30);
        check(server.computeOnServer(
                  s
                  -> Math.abs(s.getPlayerList().getPlayers().getFirst().getY() -
                              lower.getY()) < .1),
              "Vertical ladder returns to the bottom floor");
        teleport(server, lower.getX() + .5, lower.getY(), lower.getZ() + .5, yaw, -15);
        context.waitTicks(12);
        context.getInput().holdKey(InputConstants.KEY_W);
        context.waitFor(mc -> mc.player.getY() >= 64.05, 250);
        context.getInput().releaseKey(InputConstants.KEY_W);
        context.getInput().holdKey(InputConstants.KEY_LSHIFT);
        context.runOnClient(mc -> mc.player.setYRot(core.swapped ? -90 : 0));
        context.getInput().holdKey(InputConstants.KEY_W);
        context.waitTicks(25);
        context.getInput().releaseKey(InputConstants.KEY_W);
        context.getInput().releaseKey(InputConstants.KEY_LSHIFT);
        context.waitTicks(12);
        check(server.computeOnServer(s -> {
          var p = s.getPlayerList().getPlayers().getFirst();
          return Math.abs(p.getY() - 64) < .1 && p.onGround();
        }),
              "The intermediate floor can be entered from the ladder");
        checks.add(Map.of("case", "native_vertical_ladder", "lower_y", lower.getY(),
                          "upper_y", upper.getY(), "intermediate_exit_y", 64,
                          "round_trip", true));
      }
      persist();
    }
  }
  private void verifyGenerationPerformance(ServerLevel level) {
    var timings = new ArrayList<Double>();
    for (int i = 0; i < 4; i++) {
      int x = 8192 + i * 96, z = 8192 + i * 112;
      long began = System.nanoTime();
      level.getChunk(x >> 4, z >> 4);
      timings.add((System.nanoTime() - began) / 1e6);
    }
    double maximum = Collections.max(timings);
    check(maximum < 5000,
          "Cold chunk generation remains within the verification budget: " + maximum);
    checks.add(Map.of(
        "case", "cold_chunk_generation", "requests", 4, "milliseconds", timings,
        "max_ms", maximum, "mean_ms",
        timings.stream().mapToDouble(Double::doubleValue).average().orElseThrow()));
  }
  private BitSet footprint(Rules rules, int ox, int oz) {
    var bits = new BitSet(48 * 48);
    for (int x = 0; x < 48; x++)
      for (int z = 0; z < 48; z++)
        if (rules.value("wall", ox + x, 64, oz + z) > 0)
          bits.set(x * 48 + z);
    return bits;
  }
  private void verifySpatialDiversity(ServerLevel level) {
    var counts = new HashSet<Integer>();
    var styles = new TreeMap<Integer, Integer>();
    var layouts = new TreeMap<Integer, List<Integer>>();
    int emptyPatches = 0, patchSamples = 0, compact = 0;
    int rooms = 0, elongated = 0, large = 0, squares = 0, boundary = 0,
        boundaryWalls = 0;
    var aspects = new HashSet<Integer>();
    for (long seed : new long[] {level.getSeed(), level.getSeed() + 17}) {
      var rules = new Rules(level, seed);
      for (int ox : new int[] {-96, 0, 96})
        for (int oz : new int[] {-96, 0, 96}) {
          var seen = new HashSet<List<Integer>>();
          for (int x = 2; x < 48; x += 3)
            for (int z = 2; z < 48; z += 3) {
              if (rules.value("layout/circulation", ox + x, 64, oz + z) > 0)
                continue;
              var bounds = new ArrayList<Integer>();
              for (String key : new String[] {"lo_x", "hi_x", "lo_z", "hi_z"})
                bounds.add(Math.round(rules.value("room/" + key, ox + x, 64, oz + z)));
              if (!seen.add(bounds))
                continue;
              int w = bounds.get(1) - bounds.get(0) - 1,
                  d = bounds.get(3) - bounds.get(2) - 1;
              double aspect = (double)Math.max(w, d) / Math.min(w, d);
              rooms++;
              if (aspect >= 2.5)
                elongated++;
              if (w * d >= 180)
                large++;
              if (w * d <= 81)
                compact++;
              if (aspect <= 1.35)
                squares++;
              aspects.add(aspect >= 3.5   ? 3
                          : aspect >= 2.5 ? 2
                          : aspect >= 1.5 ? 1
                                          : 0);
              styles.merge(Math.round(rules.value("prop_kind", ox + x, 64, oz + z)), 1,
                           Integer::sum);
            }
          counts.add(seen.size());
          int layout = Math.round(rules.value("layout/kind", ox, 64, oz));
          layouts.computeIfAbsent(layout, key -> new ArrayList<>()).add(seen.size());
          int[][] occupied = new int[49][49];
          for (int x = 0; x < 48; x++)
            for (int z = 0; z < 48; z++)
              occupied[x + 1][z + 1] =
                  occupied[x][z + 1] + occupied[x + 1][z] - occupied[x][z] +
                  (rules.value("solid", ox + x, 65, oz + z) > 0 ? 1 : 0);
          for (int x = 4; x < 44; x++)
            for (int z = 4; z < 44; z++) {
              patchSamples++;
              if (occupied[x + 5][z + 5] - occupied[x - 4][z + 5] -
                      occupied[x + 5][z - 4] + occupied[x - 4][z - 4] ==
                  0)
                emptyPatches++;
            }
          for (int t = 0; t < 48; t++) {
            boundary += 2;
            if (rules.value("wall", ox, 64, oz + t) > 0)
              boundaryWalls++;
            if (rules.value("wall", ox + t, 64, oz) > 0)
              boundaryWalls++;
          }
        }
    }
    double narrow = (double)elongated / rooms, shared = (double)large / rooms,
           coverage = (double)boundaryWalls / boundary;
    checks.add(Map.of("case", "spatial_diversity", "rooms", rooms, "room_counts",
                      counts, "elongated_fraction", narrow, "large_fraction", shared,
                      "square_fraction", (double)squares / rooms,
                      "boundary_wall_coverage", coverage, "aspect_classes",
                      aspects.size(), "furniture_histogram", styles));
    persist();
    checks.add(Map.of("case", "regional_density", "rooms_by_layout", layouts,
                      "compact_fraction", (double)compact / rooms, "empty_9x9_fraction",
                      (double)emptyPatches / patchSamples));
    check(
        narrow >= .10 && shared >= .04 && shared <= .16 && counts.size() >= 3 &&
            coverage <= .75 && aspects.size() == 4,
        "Runtime architecture includes varied room proportions and interrupted planning boundaries");
    check(styles.size() >= 6 && Collections.max(styles.values()) < rooms * .4,
          "Furniture families are broadly represented");
    check(layouts.size() == descriptor.getAsJsonArray("layout_kinds").size(),
          "Every circulation strategy occurs in native seed samples");
    double denseMean =
        layouts.get(0).stream().mapToInt(Integer::intValue).average().orElseThrow();
    double suitesMean =
        layouts.get(1).stream().mapToInt(Integer::intValue).average().orElseThrow();
    check(denseMean >= suitesMean * 1.4,
          "Dense regions support substantially more rooms: " + denseMean + " / " +
              suitesMean);
    check((double)emptyPatches / patchSamples <= .08,
          "Eye-height empty nine-by-nine patches remain localized");
  }
  private void verifySeedRules(ServerLevel level) {
    var patterns = new HashSet<BitSet>();
    var seedMaps = new ArrayList<BitSet>();
    long begin = System.nanoTime();
    for (long seed : new long[] {level.getSeed(), level.getSeed() + 1,
                                 level.getSeed() + 2, level.getSeed() + 17}) {
      var rules = new Rules(level, seed);
      seedMaps.add(footprint(rules, 0, 0));
      for (int x : new int[] {-96, -48, 0, 48, 96, 144})
        for (int z : new int[] {0, 48})
          patterns.add(footprint(rules, x, z));
      for (int x :
           new int[] {-29000001, -16385, -49, -48, -1, 0, 47, 48, 16384, 29000001})
        check(rules.value("coordinate_x", x, 64, 0) == Math.floorMod(x, 48),
              "Density coordinates retain block precision at " + x);
    }
    check(new HashSet<>(seedMaps).size() == 4,
          "Changing the world seed changes interior walls");
    check(
        seedMaps.getFirst().equals(footprint(new Rules(level, level.getSeed()), 0, 0)),
        "World seed reproduces the same interior geometry");
    check(patterns.size() >= 40,
          "Regions have independently generated partition layouts: " + patterns.size());
    checks.add(Map.of("case", "runtime_seed_variation", "seeds", 4, "regions", 48,
                      "distinct_layouts", patterns.size(), "elapsed_seconds",
                      (System.nanoTime() - begin) / 1e9));
  }
  private net.minecraft.world.level.levelgen.structure.Structure
  structure(ServerLevel level) {
    return level.registryAccess()
        .lookupOrThrow(Registries.STRUCTURE)
        .getValue(Identifier.parse("backrooms:interior"));
  }
  private List<net.minecraft.world.level.levelgen.structure.BoundingBox>
  boxes(ServerLevel level, int lo, int hi) {
    var result =
        new ArrayList<net.minecraft.world.level.levelgen.structure.BoundingBox>();
    int spacing = descriptor.get("landmark_spacing").getAsInt();
    for (int gx = Math.floorDiv(lo - 64, spacing);
         gx <= Math.floorDiv(hi + 64, spacing); gx++)
      for (int gz = Math.floorDiv(lo - 64, spacing);
           gz <= Math.floorDiv(hi + 64, spacing); gz++) {
        var start = level
                        .getChunk(gx * spacing / 16, gz * spacing / 16,
                                  ChunkStatus.STRUCTURE_STARTS)
                        .getStartForStructure(structure(level));
        if (start != null && start.isValid())
          result.add(start.getBoundingBox());
      }
    return result;
  }
  private void verifyTerrain(ServerLevel level) throws Exception {
    long begin = System.nanoTime();
    var masks = boxes(level, -48, 96);
    var rules = new Rules(level, level.getSeed());
    int samples = 0, lamps = 0;
    var free = new HashSet<Long>();
    var distances = new ArrayList<Integer>();
    int[] pixels = new int[144 * 144];
    for (int x = -48; x < 96; x++)
      for (int z = -48; z < 96; z++) {
        boolean feature = false;
        for (var b : masks)
          feature |= x >= b.minX() && x <= b.maxX() && z >= b.minZ() && z <= b.maxZ();
        var p = new BlockPos(x, 64, z);
        var state = level.getBlockState(p);
        pixels[(z + 48) * 144 + x + 48] = !state.isAir() ? 0x514933
                                          : !level.getBlockState(p.below()).isAir()
                                              ? 0xbcaa77
                                              : 0x10171e;
        if (clear(level, p))
          free.add(key(x, z));
        if (feature)
          continue;
        for (int y = 63; y < 75; y++) {
          var actual = level.getBlockState(new BlockPos(x, y, z));
          var expected = rules.blockAt(x, y, z);
          check(actual.equals(expected),
                "Native terrain matches its runtime density and material rules at " +
                    x + "," + y + "," + z + ": " + actual + " expected " + expected);
          samples++;
          if (actual.is(Blocks.SEA_LANTERN))
            lamps++;
        }
        if (x % 4 == 0 && z % 4 == 0 && clear(level, p))
          for (int[] d : new int[][] {{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) {
            int length = 0;
            while (length < 32 && level
                                      .getBlockState(p.offset(d[0] * (length + 1), 1,
                                                              d[1] * (length + 1)))
                                      .isAir())
              length++;
            distances.add(length);
          }
      }
    chooseRoomViews(level, rules, boxes(level, -96, 192));
    chooseLayoutViews(level, rules);
    for (int origin : new int[] {-16384, 16384})
      for (int x = origin; x < origin + 16; x++)
        for (int z = 80; z < 96; z++)
          for (int y = 63; y < 69; y++) {
            var p = new BlockPos(x, y, z);
            check(level.getBlockState(p).equals(rules.blockAt(x, y, z)),
                  "Distant chunk follows runtime rules at " + p);
            samples++;
          }
    Collections.sort(distances);
    int p90 = distances.get((distances.size() - 1) * 9 / 10);
    observedSight = p90;
    check(lamps > 100, "Runtime lighting follows the generated room ceilings");
    var reached = flood2d(free, key(0, 0));
    check(reached.equals(free),
          "Runtime rooms connect across nine neighboring regions");
    var img = new BufferedImage(576, 576, BufferedImage.TYPE_INT_RGB);
    for (int x = 0; x < 576; x++)
      for (int z = 0; z < 576; z++)
        img.setRGB(x, z, pixels[(z / 4) * 144 + x / 4]);
    Files.createDirectories(Path.of("screenshots"));
    ImageIO.write(img, "png", Path.of("screenshots/runtime-floorplan.png").toFile());
    checks.add(Map.of("case", "runtime_native_geometry", "samples", samples, "lamps",
                      lamps, "p90_sight", p90, "walkable", free.size(), "reachable",
                      reached.size(), "elapsed_seconds",
                      (System.nanoTime() - begin) / 1e9));
  }
  private void chooseRoomViews(
      ServerLevel level, Rules rules,
      List<net.minecraft.world.level.levelgen.structure.BoundingBox> masks) {
    var seen = new HashSet<List<Integer>>();
    var selected = new TreeMap<Integer, View>();
    var scores = new HashMap<Integer, Integer>();
    var names = new HashMap<Integer, String>();
    for (var value : descriptor.getAsJsonArray("room_families")) {
      var family = value.getAsJsonObject();
      names.put(family.get("id").getAsInt(), family.get("name").getAsString());
    }
    for (int x = -96; x < 192; x += 3)
      for (int z = -96; z < 192; z += 3) {
        int ox = Math.floorDiv(x, 48) * 48, oz = Math.floorDiv(z, 48) * 48;
        int a = Math.round(rules.value("room/lo_x", x, 64, z)),
            b = Math.round(rules.value("room/hi_x", x, 64, z)),
            c = Math.round(rules.value("room/lo_z", x, 64, z)),
            d = Math.round(rules.value("room/hi_z", x, 64, z));
        boolean transpose = rules.value("transpose", x, 64, z) > .5;
        int x0 = ox + (transpose ? c : a), x1 = ox + (transpose ? d : b),
            z0 = oz + (transpose ? a : c), z1 = oz + (transpose ? b : d);
        if (!seen.add(List.of(x0, x1, z0, z1)) || Math.min(x1 - x0, z1 - z0) < 8)
          continue;
        boolean feature = false;
        for (var mask : masks)
          feature |= x1 >= mask.minX() && x0 <= mask.maxX() && z1 >= mask.minZ() &&
                     z0 <= mask.maxZ();
        if (feature)
          continue;
        int kind = Math.round(rules.value("prop_kind", x, 64, z)), furniture = 0;
        for (int xx = x0 + 1; xx < x1; xx++)
          for (int zz = z0 + 1; zz < z1; zz++)
            if (rules.value("furniture", xx, 64, zz) > 0)
              furniture++;
        if (furniture <= scores.getOrDefault(kind, 0))
          continue;
        for (int[] corner : new int[][] {{x0 + 2, z0 + 2},
                                         {x1 - 2, z0 + 2},
                                         {x0 + 2, z1 - 2},
                                         {x1 - 2, z1 - 2}}) {
          var point = new BlockPos(corner[0], 64, corner[1]);
          if (!clear(level, point))
            continue;
          float yaw = (float)Math.toDegrees(Math.atan2(
              -(x0 + x1) * .5 + point.getX() + .5, (z0 + z1) * .5 - point.getZ() - .5));
          selected.put(kind, new View(point, yaw, names.get(kind)));
          scores.put(kind, furniture);
          break;
        }
      }
    check(selected.size() >= 6,
          "Native camera catalog covers several architectural families: " +
              selected.keySet());
    views.addAll(selected.values());
    checks.add(Map.of("case", "room_catalog", "families", selected.keySet(),
                      "visible_furniture", scores));
  }
  private Set<Long> flood2d(Set<Long> allowed, long origin) {
    var seen = new HashSet<Long>();
    var queue = new ArrayDeque<Long>();
    seen.add(origin);
    queue.add(origin);
    while (!queue.isEmpty()) {
      long p = queue.remove();
      int x = (int)(p >> 32), z = (int)p;
      for (long q :
           new long[] {key(x - 1, z), key(x + 1, z), key(x, z - 1), key(x, z + 1)})
        if (allowed.contains(q) && seen.add(q))
          queue.add(q);
    }
    return seen;
  }

  private void chooseLayoutViews(ServerLevel level, Rules rules) throws Exception {
    var origins = new TreeMap<Integer, BlockPos>();
    var names = new TreeMap<Integer, String>();
    for (var value : descriptor.getAsJsonArray("layout_kinds")) {
      var layout = value.getAsJsonObject();
      names.put(layout.get("id").getAsInt(), layout.get("name").getAsString());
    }
    for (int radius = 0; radius <= 5 && origins.size() < names.size(); radius++)
      for (int gx = -radius; gx <= radius; gx++)
        for (int gz = -radius; gz <= radius; gz++) {
          if (Math.max(Math.abs(gx), Math.abs(gz)) != radius)
            continue;
          int ox = gx * 48, oz = gz * 48;
          int kind = Math.round(rules.value("layout/kind", ox, 64, oz));
          if (origins.containsKey(kind))
            continue;
          var landmarks = boxes(level, Math.min(ox, oz) - 64, Math.max(ox, oz) + 64);
          boolean feature =
              landmarks.stream().anyMatch(b
                                          -> b.maxX() >= ox && b.minX() < ox + 48 &&
                                                 b.maxZ() >= oz && b.minZ() < oz + 48);
          if (feature)
            continue;
          View selected = null;
        search:
          for (int x = ox + 3; x < ox + 45; x++)
            for (int z = oz + 3; z < oz + 45; z++) {
              if (kind >= 2 && rules.value("layout/circulation", x, 64, z) == 0)
                continue;
              var point = new BlockPos(x, 64, z);
              if (!clear(level, point))
                continue;
              for (int[] direction : new int[][] {{1, 0}, {0, 1}}) {
                boolean free = true;
                for (int step = 1; step <= 8; step++) {
                  var next = point.offset(direction[0] * step, 0, direction[1] * step);
                  free &= clear(level, next) &&
                          (kind < 2 || rules.value("layout/circulation", next.getX(),
                                                   64, next.getZ()) > 0);
                }
                if (free) {
                  selected = new View(point, direction[0] == 1 ? -90 : 0,
                                      "layout-" + names.get(kind));
                  break search;
                }
              }
            }
          if (selected != null) {
            views.add(selected);
            origins.put(kind, new BlockPos(ox, 64, oz));
          }
        }
    check(origins.size() == names.size(), "Native views cover every layout strategy");
    var atlas = new BufferedImage(432, ((names.size() + 1) / 2) * 240,
                                  BufferedImage.TYPE_INT_RGB);
    var graphics = atlas.createGraphics();
    var positions = new TreeMap<String, List<Integer>>();
    for (var item : origins.entrySet()) {
      int kind = item.getKey(), left = (kind % 2) * 216 + 12,
          top = (kind / 2) * 240 + 32;
      var origin = item.getValue();
      graphics.setColor(java.awt.Color.WHITE);
      graphics.drawString(names.get(kind), left, top - 10);
      for (int x = 0; x < 48; x++)
        for (int z = 0; z < 48; z++) {
          var point = origin.offset(x, 0, z);
          int color =
              !level.getBlockState(point.above()).isAir() ? 0x514933
              : !level.getBlockState(point).isAir()       ? 0x8c633f
              : rules.value("layout/circulation", point.getX(), 64, point.getZ()) > 0
                  ? 0x94aba0
                  : 0xbcaa77;
          graphics.setColor(new java.awt.Color(color));
          graphics.fillRect(left + x * 4, top + z * 4, 4, 4);
        }
      positions.put(names.get(kind), List.of(origin.getX(), origin.getZ()));
    }
    graphics.dispose();
    Files.createDirectories(Path.of("screenshots"));
    ImageIO.write(atlas, "png", Path.of("screenshots/runtime-layouts.png").toFile());
    checks.add(Map.of("case", "layout_catalog", "origins", positions));
  }
  private JsonObject layout(Identifier id) {
    for (var value : descriptor.getAsJsonArray("landmarks")) {
      var object = value.getAsJsonObject();
      if (object.get("id").getAsString().equals(id.toString()))
        return object;
    }
    throw new IllegalStateException("Unknown landmark " + id);
  }
  private void discoverLandmarks(ServerLevel level) {
    var found = new HashSet<Identifier>();
    for (int radius = 0; radius <= 8 && found.size() < 3; radius++)
      for (int gx = -radius; gx <= radius; gx++)
        for (int gz = -radius; gz <= radius; gz++) {
          if (Math.max(Math.abs(gx), Math.abs(gz)) != radius)
            continue;
          int spacing = descriptor.get("landmark_spacing").getAsInt() / 16;
          var start =
              level.getChunk(gx * spacing, gz * spacing, ChunkStatus.STRUCTURE_STARTS)
                  .getStartForStructure(structure(level));
          if (start == null || !start.isValid())
            continue;
          var piece = (PoolElementStructurePiece)start.getPieces().getFirst();
          var id = ((SinglePoolElement)piece.getElement()).getTemplateLocation();
          if (!found.add(id))
            continue;
          var info = layout(id);
          var wrapper = info.deepCopy();
          var array = new com.google.gson.JsonArray();
          array.add(info);
          wrapper.add("landmarks", array);
          var tag = level.getStructureTemplateManager().getOrCreate(id).save(
              new CompoundTag());
          var palette = tag.getListOrEmpty("palette");
          var states = new ArrayList<BlockState>();
          for (int i = 0; i < palette.size(); i++)
            states.add(NbtUtils.readBlockState(
                level.registryAccess().lookupOrThrow(Registries.BLOCK),
                palette.getCompoundOrEmpty(i)));
          var blocks = new HashMap<BlockPos, BlockState>();
          var entries = tag.getListOrEmpty("blocks");
          for (int i = 0; i < entries.size(); i++) {
            var entry = entries.getCompoundOrEmpty(i);
            var position = entry.getListOrEmpty("pos");
            var p = new BlockPos(position.getIntOr(0, 0), position.getIntOr(1, 0),
                                 position.getIntOr(2, 0));
            var state = states.get(entry.getIntOr("state", -1));
            if (state.is(Blocks.JIGSAW))
              state = block("minecraft:brown_wool").defaultBlockState();
            blocks.put(p, state);
          }
          placed.add(new Placed(id, piece, wrapper, blocks));
        }
    check(found.size() == 3,
          "Native world generation places all three landmark families");
  }
  private void inspectLandmark(ServerLevel level, Placed plan) {
    var box = plan.piece.getBoundingBox();
    for (int cx = box.minX() >> 4; cx <= box.maxX() >> 4; cx++)
      for (int cz = box.minZ() >> 4; cz <= box.maxZ() >> 4; cz++)
        level.getChunk(cx, cz);
    for (var entry : plan.blocks.entrySet()) {
      var p = transformRaw(plan, entry.getKey());
      var expected = entry.getValue().rotate(plan.piece.getRotation());
      check(level.getBlockState(p).equals(expected),
            "Compact landmark voxel and rotation match its decoded template: " + p +
                " " + level.getBlockState(p) + " expected " + expected);
    }
    check(box.getXSpan() <= 50 && box.getZSpan() <= 50,
          "Landmarks occupy compact reusable footprints");
    checks.add(Map.of("case", "native_landmark", "template", plan.template.toString(),
                      "rotation", plan.piece.getRotation().toString(), "blocks",
                      plan.blocks.size(), "bounds",
                      List.of(box.minX(), box.minY(), box.minZ(), box.maxX(),
                              box.maxY(), box.maxZ())));
  }
  private void verifyConnectivity(ServerLevel level, Placed plan) {
    var box = plan.piece.getBoundingBox();
    int minX = Math.floorDiv(box.minX(), 48) * 48 - 48,
        minZ = Math.floorDiv(box.minZ(), 48) * 48 - 48,
        maxX = (Math.floorDiv(box.maxX(), 48) + 2) * 48,
        maxZ = (Math.floorDiv(box.maxZ(), 48) + 2) * 48;
    var nodes = new HashSet<BlockPos>();
    for (int x = minX; x < maxX; x++)
      for (int z = minZ; z < maxZ; z++)
        for (int floor : walkLevels()) {
          var p = new BlockPos(x, floor, z);
          if (clear(level, p))
            nodes.add(p);
        }
    var feature = plan.layout;
    var size = feature.getAsJsonArray("size");
    for (int x = 0; x < size.get(0).getAsInt(); x++)
      for (int z = 0; z < size.get(2).getAsInt(); z++)
        for (int y = feature.get("minimum_y").getAsInt() + 1;
             y <= feature.get("maximum_floor_y").getAsInt() + 1; y++) {
          var p = transform(plan, new BlockPos(x, y, z));
          if (navigable(level, p))
            nodes.add(p);
        }
    var origin = transform(plan, new BlockPos(2, 1, 2));
    var reached = new HashSet<BlockPos>();
    var queue = new ArrayDeque<BlockPos>();
    reached.add(origin);
    queue.add(origin);
    while (!queue.isEmpty()) {
      var p = queue.remove();
      for (int[] d : new int[][] {{1, 0}, {-1, 0}, {0, 1}, {0, -1}})
        for (int dy : new int[] {0, -1, 1}) {
          var q = p.offset(d[0], dy, d[1]);
          if ((dy <= 0 || bodyClear(level, p.above(2))) && nodes.contains(q) &&
              reached.add(q))
            queue.add(q);
        }
      for (int dy : new int[] {-1, 1}) {
        var q = p.above(dy);
        if (onLadder(level, p) && onLadder(level, q) && nodes.contains(q) &&
            reached.add(q))
          queue.add(q);
      }
    }
    check(reached.equals(nodes),
          "Landmark and surrounding runtime rooms connect: " + plan.template +
              " missing " + (nodes.size() - reached.size()));
    for (var point : feature.getAsJsonArray("required"))
      check(reached.contains(transform(plan, readPoint(point.getAsJsonArray()))),
            "Required landmark landing connects to the runtime maze");
    checks.add(Map.of("case", "landmark_runtime_connectivity", "template",
                      plan.template.toString(), "nodes", nodes.size(), "reachable",
                      reached.size()));
  }
  private void verifyMaterials(ClientGameTestContext context) throws Exception {
    int count = context.computeOnClient(mc -> {
      int checked = 0;
      try (var archive = new ZipFile("resourcepacks/backrooms-level0.zip")) {
        for (var entry : Collections.list(archive.entries())) {
          if (!entry.getName().startsWith("assets/") || entry.isDirectory())
            continue;
          var parts = entry.getName().split("/", 3);
          var resource =
              mc.getResourceManager()
                  .getResource(Identifier.fromNamespaceAndPath(parts[1], parts[2]))
                  .orElseThrow();
          try (var expected = archive.getInputStream(entry);
               var actual = resource.open()) {
            check(Arrays.equals(MessageDigest.getInstance("SHA-256").digest(
                                    expected.readAllBytes()),
                                MessageDigest.getInstance("SHA-256").digest(
                                    actual.readAllBytes())),
                  "Loaded material resources match the delivery pack");
          }
          if (entry.getName().endsWith(".png")) {
            try (var stream = resource.open()) {
              var decoded = ImageIO.read(stream);
              check(decoded.getWidth() == 64 && decoded.getHeight() == 64,
                    "Material atlases use the authored pixel dimensions");
            }
            checked++;
          }
        }
      }
      return checked;
    });
    check(count == 4, "The Level 0 material set loads completely");
    checks.add(Map.of("case", "level0_materials", "textures", count));
    persist();
  }
  private void verifyLandmarkMovement(ClientGameTestContext context,
                                      TestServerContext server) {
    for (var plan : placed)
      for (var entry : plan.layout.getAsJsonArray("landmarks")) {
        var feature = entry.getAsJsonObject();
        String kind = feature.get("kind").getAsString();
        float rotation;
        switch (plan.piece.getRotation()) {
        case CLOCKWISE_90:
          rotation = 90;
          break;
        case CLOCKWISE_180:
          rotation = 180;
          break;
        case COUNTERCLOCKWISE_90:
          rotation = -90;
          break;
        default:
          rotation = 0;
          break;
        }
        for (var camera : feature.getAsJsonArray("views")) {
          var view = camera.getAsJsonObject();
          var p = transform(plan, readPoint(view.getAsJsonArray("point")));
          teleport(server, p.getX() + .5, p.getY(), p.getZ() + .5,
                   view.get("yaw").getAsFloat() + rotation,
                   view.get("pitch").getAsFloat());
          context.waitTicks(30);
          context.takeScreenshot(view.get("name").getAsString());
        }
        for (var point : feature.getAsJsonArray("falls")) {
          var fall = transform(plan, readPoint(point.getAsJsonArray()));
          float health = server.computeOnServer(
              s -> s.getPlayerList().getPlayers().getFirst().getHealth());
          teleport(server, fall.getX() + .5, fall.getY(), fall.getZ() + .5, 0, 45);
          context.waitTicks(85);
          var landed = server.computeOnServer(s -> {
            var p = s.getPlayerList().getPlayers().getFirst();
            check(p.isAlive() && p.getHealth() >= health,
                  "The landmark catch pool supports a survivable fall");
            check(p.getY() < 54, "The player falls into the actual lower geometry");
            return List.of(p.getX(), p.getY(), p.getZ());
          });
          checks.add(Map.of("case", "landmark_fall", "kind", kind, "position", landed));
          persist();
        }
        for (var flight : feature.getAsJsonArray("stairs")) {
          var stairs = flight.getAsJsonObject();
          var lower = transform(plan, readPoint(stairs.getAsJsonArray("lower")));
          var upper = transform(plan, readPoint(stairs.getAsJsonArray("upper")));
          teleport(server, lower.getX() + .5, lower.getY(), lower.getZ() + .5,
                   stairs.get("yaw").getAsFloat() + rotation, 0);
          context.waitTicks(12);
          context.getInput().holdKey(InputConstants.KEY_W);
          context.waitTicks(85);
          context.getInput().releaseKey(InputConstants.KEY_W);
          context.waitTicks(8);
          double actual = server.computeOnServer(
              s -> s.getPlayerList().getPlayers().getFirst().getY());
          check(Math.abs(actual - upper.getY()) < .1,
                "Native walking ascends the landmark staircase: " + kind +
                    " y=" + actual + " expected=" + upper.getY());
          checks.add(Map.of("case", "landmark_stairs", "kind", kind, "from_y",
                            lower.getY(), "to_y", actual));
          persist();
        }
        for (var route : feature.getAsJsonArray("ladders")) {
          var ladder = route.getAsJsonObject();
          var lower = transform(plan, readPoint(ladder.getAsJsonArray("lower")));
          var upper = transform(plan, readPoint(ladder.getAsJsonArray("upper")));
          int rise = upper.getY() - lower.getY();
          teleport(server, lower.getX() + .5, lower.getY(), lower.getZ() + .5,
                   ladder.get("yaw").getAsFloat() + rotation, -15);
          context.waitTicks(12);
          context.getInput().holdKey(InputConstants.KEY_W);
          context.waitTicks(rise * 8 + 35);
          context.getInput().releaseKey(InputConstants.KEY_W);
          context.waitTicks(8);
          double climbed = server.computeOnServer(
              s -> s.getPlayerList().getPlayers().getFirst().getY());
          check(Math.abs(climbed - upper.getY()) < .1,
                "Native climbing exits onto the raised gallery: y=" + climbed +
                    " expected=" + upper.getY());
          context.takeScreenshot(kind + "-ladder-" + rise);
          float health = server.computeOnServer(
              s -> s.getPlayerList().getPlayers().getFirst().getHealth());
          teleport(server, lower.getX() + .5, upper.getY(), lower.getZ() + .5,
                   ladder.get("yaw").getAsFloat() + rotation, 35);
          context.waitTicks(10);
          double midway = server.computeOnServer(
              s -> s.getPlayerList().getPlayers().getFirst().getY());
          check(midway < upper.getY() && midway > upper.getY() - 2,
                "The ladder controls descent speed");
          context.waitTicks(rise * 10 + 20);
          double descended = server.computeOnServer(s -> {
            var player = s.getPlayerList().getPlayers().getFirst();
            check(player.isAlive() && player.getHealth() >= health,
                  "Ladder descent preserves the player's health");
            return player.getY();
          });
          check(Math.abs(descended - lower.getY()) < .1,
                "Ladder descent reaches its lower landing: " + descended);
          checks.add(Map.of("case", "landmark_ladder", "kind", kind, "rise", rise,
                            "upper_y", climbed, "lower_y", descended));
          persist();
        }
      }
  }
  private static BlockPos readPoint(com.google.gson.JsonArray values) {
    return new BlockPos(values.get(0).getAsInt(), values.get(1).getAsInt(),
                        values.get(2).getAsInt());
  }
  private static boolean clear(ServerLevel level, BlockPos p) {
    return bodyClear(level, p) && bodyClear(level, p.above()) &&
        (level.getBlockState(p.below()).isFaceSturdy(level, p.below(), Direction.UP) ||
         level.getBlockState(p.below()).getBlock() instanceof StairBlock);
  }
  private static boolean bodyClear(ServerLevel level, BlockPos p) {
    return level.getBlockState(p).isAir() || level.getBlockState(p).is(Blocks.WATER) ||
        level.getBlockState(p).is(Blocks.LADDER);
  }
  private static boolean onLadder(ServerLevel level, BlockPos p) {
    return level.getBlockState(p).is(Blocks.LADDER) ||
        level.getBlockState(p.below()).is(Blocks.LADDER);
  }
  private static boolean navigable(ServerLevel level, BlockPos p) {
    return clear(level, p) ||
        onLadder(level, p) && bodyClear(level, p) && bodyClear(level, p.above());
  }
  private static BlockPos transform(Placed plan, BlockPos p) {
    return transformRaw(plan, p.above(plan.layout.get("floor_offset").getAsInt()));
  }
  private static BlockPos transformRaw(Placed plan, BlockPos p) {
    return StructureTemplate
        .calculateRelativePosition(
            new StructurePlaceSettings().setRotation(plan.piece.getRotation()), p)
        .offset(plan.piece.getPosition());
  }
  private void verifyResources(TestServerContext server) throws Exception {
    int count = server.computeOnServer(s -> {
      int checked = 0;
      try (var zip = new ZipFile("backrooms-datapack.zip")) {
        for (var entry : Collections.list(zip.entries())) {
          if (!entry.getName().startsWith("data/") || entry.isDirectory())
            continue;
          var parts = entry.getName().split("/", 3);
          var resource =
              s.getResourceManager()
                  .getResource(Identifier.fromNamespaceAndPath(parts[1], parts[2]))
                  .orElseThrow();
          try (var expected = zip.getInputStream(entry); var actual = resource.open()) {
            check(Arrays.equals(MessageDigest.getInstance("SHA-256").digest(
                                    expected.readAllBytes()),
                                MessageDigest.getInstance("SHA-256").digest(
                                    actual.readAllBytes())),
                  "Loaded resources agree with the delivery pack");
          }
          checked++;
        }
      }
      return checked;
    });
    checks.add(Map.of("case", "loaded_resources", "files", count));
    persist();
  }
  private static Block block(String id) {
    return BuiltInRegistries.BLOCK.getValue(Identifier.parse(id));
  }
  private static long key(int x, int z) {
    return ((long)x << 32) | (z & 0xffffffffL);
  }
  private static void teleport(TestServerContext server, double x, double y, double z,
                               float yaw, float pitch) {
    server.runCommand("execute in backrooms:interior run tp @a " + x + " " + y + " " +
                      z + " " + yaw + " " + pitch);
  }
  private static void check(boolean value, String message) {
    if (!value)
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
