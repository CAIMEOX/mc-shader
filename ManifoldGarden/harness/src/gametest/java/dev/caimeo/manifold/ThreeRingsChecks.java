package dev.caimeo.manifold;

import com.google.gson.JsonParser;
import com.mojang.blaze3d.platform.InputConstants;
import net.fabricmc.fabric.api.client.gametest.v1.context.ClientGameTestContext;
import net.fabricmc.fabric.api.client.gametest.v1.context.TestServerContext;
import net.minecraft.commands.arguments.EntityAnchorArgument;
import net.minecraft.nbt.CompoundTag;
import net.minecraft.resources.Identifier;
import net.minecraft.server.MinecraftServer;
import net.minecraft.world.entity.Interaction;
import net.minecraft.world.phys.EntityHitResult;
import net.minecraft.world.phys.Vec3;
import net.minecraft.world.scores.ScoreHolder;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.*;

final class ThreeRingsChecks {
  private static final Identifier STORE = Identifier.parse("manifold:runtime");
  private static final double[][][] FRAMES = frames();

  static void run(ClientGameTestContext context, TestServerContext server,
                  List<Map<String, Object>> checks) {
    server.runCommand("function manifold:three_rings/start");
    server.runCommand("function manifold:quality/low");
    waitNative(context, server);
    check(value(server, "h.level") == 2 && value(server, "period") == 64,
          "The rings use a sixty-four-block logical period");
    var gpu = GpuReadback.read(context, "probe");
    check(gpu != null && gpu.scalar(12) == 1 && gpu.scalar(72) == 2,
          "The renderer receives the active rings level");
    for (int id = 0; id < 3; id++) {
      var cube = cube(server, id);
      check(gpu.scalar(103 + id * 3) == cube.getInt("x").orElseThrow() &&
                gpu.scalar(104 + id * 3) == cube.getInt("y").orElseThrow() &&
                gpu.scalar(105 + id * 3) == cube.getInt("z").orElseThrow(),
            "Object bank reaches the GPU");
    }
    checks.add(
        Map.of("case", "rings_entry", "period", 64, "frame_ready", gpu.scalar(12)));
    context.takeScreenshot("manifold-rings-entry");
    MaterialChecks.initialCubes(context, server, checks);
    RuntimeMetrics.observe(context, server, checks, "puzzle_entry");
    int beforePublications = value(server, "r.bank_publications");
    context.waitTicks(20);
    check(value(server, "r.bank_publications") == beforePublications,
          "Resting object data remains cached while camera packets advance");
    checks.add(
        Map.of("case", "rings_object_transport", "idle_publications", 0, "ticks", 20));
    bankCoherence(context, server, checks);
    scaling(server, checks);
    server.runCommand("function manifold:reset");
    waitNative(context, server);
    physics(context, server, checks);
    server.runCommand("function manifold:reset");
    waitNative(context, server);
    context.getInput().lookAt(90, -90);
    context.waitTicks(3);
    context.getInput().holdKey(InputConstants.KEY_LCONTROL);
    context.waitTicks(4);
    context.getInput().releaseKey(InputConstants.KEY_LCONTROL);
    server.waitFor(s -> value(s, "h.mode") == 1 && value(s, "g.dy") == 1, 400);
    waitNative(context, server);
    check(value(server, "r.wy") == 1 &&
              Math.abs(value(server, "g.y") / 4096.0 - 62.6) < .02,
          "The upward fall enters the next local window");
    clickCube(context, server, 0);
    server.waitFor(s -> value(s, "r.held") == 0, 40);
    check(cube(server, 0).getInt("phase").orElseThrow() == 1,
          "Right-click carries the blue cube");
    checks.add(Map.of("case", "rings_back_face_pickup", "window_y", 32, "held", 0));
    context.takeScreenshot("manifold-rings-carry");
    HeldCubeChecks.run(context, checks, 0);
    walk(context, server, new Vec3(24, 62.6, 4), .25, 160);
    place(context, server, new Vec3(26, 63, 4));
    server.waitFor(s -> value(s, "r.gate0") == 1, 40);
    check(value(server, "r.held") == -1,
          "The blue temporary socket powers the gallery");
    checks.add(
        Map.of("case", "rings_blue_socket", "gate", 1, "cell", List.of(26, 63, 4)));
    context.takeScreenshot("manifold-rings-blue-socket");
    playCircuit(context, server, checks);
    RuntimeMetrics.observe(context, server, checks, "puzzle_complete");
    RuntimeMetrics.balanced(context, server, checks, "puzzle_complete_balanced");
    recovery(context, server, checks);
    server.runCommand("function manifold:stop");
    context.waitTicks(20);
  }

  private static void playCircuit(ClientGameTestContext context,
                                  TestServerContext server,
                                  List<Map<String, Object>> checks) {
    turn(context, server, new Vec3(-1, 0, 0));
    waitNative(context, server);
    check(Math.abs(position(server).x - 27.4) < .03,
          "A westward orbit lands on the frozen blue cube");
    walk(context, server, new Vec3(27.4, 1, 4), .25, 100);
    waitNative(context, server);
    clickCube(context, server, 1);
    server.waitFor(s -> value(s, "r.held") == 1, 40);
    HeldCubeChecks.run(context, checks, 1);
    walk(context, server, new Vec3(27.4, 3, 7.5), .25, 100);
    walk(context, server, new Vec3(6.4, 3, 16), .25, 140);
    waitNative(context, server);
    check(Math.abs(position(server).x - 6.4) < .03,
          "The gallery connects to the delivery ledge");
    placeAgainst(context, server, new Vec3(6, 3, 18), new Vec3(0, -.501, 0));
    boolean wrapped = false;
    int previous = 6;
    var trajectory = new ArrayList<Integer>();
    for (int tick = 0; tick < 80; tick++) {
      context.waitTicks(1);
      var amber = cube(server, 1);
      int x = amber.getInt("x").orElseThrow();
      wrapped |= x - previous > 32;
      previous = x;
      trajectory.add(x);
      if (x == 52 && amber.getInt("phase").orElseThrow() == 0)
        break;
    }
    check(wrapped && value(server, "r.gate1") == 1 &&
              cube(server, 1).getInt("x").orElseThrow() == 52,
          "The amber cube travels through the periodic shaft: " + trajectory);
    checks.add(Map.of("case", "rings_cube_delivery", "wrapped", wrapped, "trajectory",
                      trajectory, "gate", 1));
    context.takeScreenshot("manifold-rings-delivery");
    walk(context, server, new Vec3(53.4, 3, 18), .2, 80);
    waitNative(context, server);
    walk(context, server, new Vec3(52.4, 3, 25), .25, 120);
    waitNative(context, server);
    turn(context, server, new Vec3(0, 0, 1));
    waitNative(context, server);
    clickCube(context, server, 2);
    server.waitFor(s -> value(s, "r.held") == 2, 40);
    waitNative(context, server);
    walk(context, server, new Vec3(48, 3, 27.6), .25, 100);
    walk(context, server, new Vec3(48, 10, 27.6), .25, 100);
    walk(context, server, new Vec3(26, 10, 27.6), .25, 220);
    walk(context, server, new Vec3(26, 3, 27.6), .25, 100);
    place(context, server, new Vec3(24, 3, 28));
    check(value(server, "r.gate0") == 1 &&
              cube(server, 2).getInt("x").orElseThrow() == 24,
          "The green relay shares the gallery supply");
    checks.add(Map.of("case", "rings_green_relay", "gate", 1));
    walk(context, server, new Vec3(30, 3, 27.6), .25, 100);
    turn(context, server, new Vec3(0, 1, 0));
    waitNative(context, server);
    walk(context, server, new Vec3(26, 62.6, 24), .25, 100);
    walk(context, server, new Vec3(26, 62.6, 6), .25, 200);
    clickCube(context, server, 0);
    server.waitFor(s -> value(s, "r.held") == 0, 40);
    check(value(server, "r.gate0") == 1,
          "Green power keeps the gallery open after blue is recovered");
    walk(context, server, new Vec3(30, 62.6, 12), .25, 100);
    walk(context, server, new Vec3(36, 62.6, 12), .25, 100);
    place(context, server, new Vec3(38, 63, 12));
    checks.add(Map.of("case", "rings_blue_reuse", "final_cell", List.of(38, 63, 12),
                      "gallery_powered", true));
    walk(context, server, new Vec3(30, 62.6, 12), .25, 100);
    walk(context, server, new Vec3(26, 62.6, 25), .25, 160);
    turn(context, server, new Vec3(0, 0, 1));
    waitNative(context, server);
    walk(context, server, new Vec3(26, 3, 27.6), .25, 100);
    clickCube(context, server, 2);
    server.waitFor(s -> value(s, "r.held") == 2, 40);
    check(value(server, "r.gate0") == 1, "The blue main socket frees the green relay");
    walk(context, server, new Vec3(36, 3, 27.6), .25, 140);
    place(context, server, new Vec3(38, 3, 28));
    turn(context, server, new Vec3(-1, 0, 0));
    waitNative(context, server);
    walk(context, server, new Vec3(53.4, 3, 18), .2, 140);
    waitNative(context, server);
    clickCube(context, server, 1);
    server.waitFor(s -> value(s, "r.held") == 1, 40);
    walk(context, server, new Vec3(38.4, 3, 11), .25, 160);
    waitNative(context, server);
    place(context, server, new Vec3(38, 3, 9));
    server.waitFor(s -> value(s, "r.complete") == 1, 40);
    checks.add(Map.of("case", "rings_complete", "blue", List.of(38, 63, 12), "amber",
                      List.of(38, 3, 9), "green", List.of(38, 3, 28)));
    Vec3 monument = server.computeOnServer(s -> project(s, new Vec3(38, 25, 18)));
    context.runOnClient(
        mc -> mc.player.lookAt(EntityAnchorArgument.Anchor.EYES, monument));
    context.waitTicks(8);
    context.takeScreenshot("manifold-rings-complete");
  }

  private static void physics(ClientGameTestContext context, TestServerContext server,
                              List<Map<String, Object>> checks) {
    server.runCommand(
        "data modify storage manifold:runtime registration set value {id:3,x:10,y:3,z:4,gravity:0}");
    server.runCommand(
        "execute as @a[tag=manifold.pilot] at @s run function manifold:objects/register with storage manifold:runtime registration");
    server.runCommand(
        "execute as @a[tag=manifold.pilot] at @s run function manifold:objects/wake");
    context.waitTicks(8);
    check(cube(server, 3).getInt("y").orElseThrow() == 3,
          "A moving cube waits before entering the player's body");
    walk(context, server, new Vec3(13, 1.4, 4), .2, 60);
    context.waitTicks(8);
    check(cube(server, 3).getInt("y").orElseThrow() == 1 &&
              cube(server, 3).getInt("phase").orElseThrow() == 0,
          "The cube sleeps after reaching a clear support");
    server.runOnServer(s -> {
      var source = s.createCommandSourceStack();
      for (
          String command : List.of(
              "data modify storage manifold:runtime registration set value {id:4,x:16,y:8,z:4,gravity:0}",
              "execute as @a[tag=manifold.pilot] at @s run function manifold:objects/register with storage manifold:runtime registration",
              "execute as @a[tag=manifold.pilot] at @s run function manifold:objects/wake",
              "execute as @a[tag=manifold.pilot] at @s as @e[tag=manifold.object.active] run function manifold:objects/step",
              "scoreboard players set #g.dy manifold 1",
              "execute as @a[tag=manifold.pilot] at @s run function manifold:objects/gravity"))
        s.getCommands().performPrefixedCommand(source, command);
    });
    int frozenY = cube(server, 4).getInt("y").orElseThrow();
    context.waitTicks(5);
    check(cube(server, 4).getInt("phase").orElseThrow() == 0 &&
              cube(server, 4).getInt("y").orElseThrow() == frozenY,
          "Changing gravity freezes an airborne cube");
    server.runCommand("function manifold:gravity/bounds");
    context.waitTicks(12);
    check(cube(server, 4).getInt("y").orElseThrow() == 1,
          "Returning to the cube's gravity resumes its motion");
    server.runCommand(
        "data modify storage manifold:runtime registration set value {id:5,x:10,y:2,z:4,gravity:0}");
    server.runCommand(
        "execute as @a[tag=manifold.pilot] at @s run function manifold:objects/register with storage manifold:runtime registration");
    server.runCommand(
        "execute as @a[tag=manifold.pilot] at @s run function manifold:objects/project_both");
    clickCube(context, server, 3);
    server.waitFor(s -> value(s, "r.held") == 3, 40);
    context.waitTicks(8);
    check(cube(server, 5).getInt("y").orElseThrow() == 1,
          "Removing support wakes the cube above it");
    checks.add(Map.of("case", "rings_object_physics", "body_clearance", true,
                      "frozen_cell_y", frozenY, "support_wakeup", true));
  }

  private static void scaling(TestServerContext server,
                              List<Map<String, Object>> checks) {
    var counts = new ArrayList<Integer>();
    var projections = new ArrayList<Integer>();
    int registered = 3;
    for (int total : new int[] {3, 30, 300}) {
      final int from = registered;
      server.runOnServer(s -> {
        for (int id = from; id < total; id++) {
          var source = s.createCommandSourceStack();
          String record = "{id:" + id + ",x:" + (42 + (id % 12)) +
                          ",y:" + (40 + (id / 12) % 12) + ",z:" + (44 + (id / 144)) +
                          ",gravity:1}";
          s.getCommands().performPrefixedCommand(
              source,
              "data modify storage manifold:runtime registration set value " + record);
          s.getCommands().performPrefixedCommand(
              source,
              "execute as @a[tag=manifold.pilot] at @s run function manifold:objects/register with storage manifold:runtime registration");
        }
      });
      registered = total;
      TickTrace.capture(server, "rings_idle_" + total);
      counts.add(value(server, "o.visits"));
      server.runCommand("scoreboard players set #h.cache1 manifold -1");
      TickTrace.capture(server, "rings_build_" + total, "manifold:rooms/build/1/0");
      projections.add(value(server, "r.projections"));
    }
    check(counts.equals(List.of(0, 0, 0)),
          "Sleeping registries do not enter the movement loop");
    checks.add(Map.of("case", "rings_sleeping_objects", "registered",
                      List.of(3, 30, 300), "movement_visits", counts));
    check(projections.get(0).equals(projections.get(1)) &&
              projections.get(1).equals(projections.get(2)),
          "Window materialization visits only its spatial buckets");
    checks.add(Map.of("case", "rings_local_projection", "registered",
                      List.of(3, 30, 300), "projected_candidates", projections));
  }

  private static void recovery(ClientGameTestContext context, TestServerContext server,
                               List<Map<String, Object>> checks) {
    var saved = new ArrayList<CompoundTag>();
    for (int id = 0; id < 3; id++)
      saved.add(cube(server, id));
    Vec3 before = position(server);
    clickCube(context, server, 1);
    server.waitFor(s -> value(s, "r.held") == 1 && value(s, "r.complete") == 0, 40);
    server.runCommand("function manifold:three_rings/checkpoint/restore");
    waitNative(context, server);
    for (int id = 0; id < 3; id++)
      check(cube(server, id).equals(saved.get(id)), "Checkpoint restores cube " + id);
    check(value(server, "r.complete") == 1 && value(server, "r.held") == -1 &&
              position(server).distanceTo(before) < .05,
          "Checkpoint restores puzzle state and player pose together");
    server.runCommand("reload");
    context.waitTicks(45);
    for (int id = 0; id < 3; id++)
      check(cube(server, id).equals(saved.get(id)), "Reload preserves cube " + id);
    var gpu = GpuReadback.read(context, "probe");
    check(gpu.scalar(12) == 1 && gpu.scalar(102) == 1,
          "The complete object snapshot survives reload");
    checks.add(Map.of("case", "rings_checkpoint_reload", "complete", true,
                      "position_error", position(server).distanceTo(before)));
    server.runCommand("kill @a");
    context.waitFor(mc -> mc.player != null && !mc.player.isAlive(), 80);
    context.waitTicks(25);
    context.runOnClient(mc -> mc.player.respawn());
    waitNative(context, server);
    check(value(server, "r.complete") == 1 && position(server).distanceTo(before) < .05,
          "Respawn resumes the saved rings checkpoint");
    checks.add(Map.of("case", "rings_checkpoint_respawn", "complete", true));
  }

  private static void bankCoherence(ClientGameTestContext context,
                                    TestServerContext server,
                                    List<Map<String, Object>> checks) {
    server.runCommand(
        "execute in manifold:stage run data modify entity @e[tag=manifold.object.bank,limit=1] item.components.\"minecraft:custom_model_data\".colors[-1] set value 16777215");
    context.waitTicks(4);
    var packet = GpuReadback.read(context, "packet");
    var probe = GpuReadback.read(context, "probe");
    check((packet.rgba()[0] & 255) < 230 && probe.scalar(12) == 1,
          "A mismatched object revision retains the complete frame");
    server.runCommand("scoreboard players set #r.bank_dirty manifold 1");
    context.waitTicks(6);
    packet = GpuReadback.read(context, "packet");
    check((packet.rgba()[0] & 255) == 255,
          "The renderer resumes with a matching full object snapshot");
    checks.add(Map.of("case", "rings_bank_coherence", "retained_frame", true,
                      "recovered", true));
  }

  private static void walk(ClientGameTestContext context, TestServerContext server,
                           Vec3 target, double tolerance, int limit) {
    try {
      for (int tick = 0; tick < limit; tick++) {
        var delta = server.computeOnServer(s -> {
          var logical = new Vec3(value(s, "g.x") / 4096.0, value(s, "g.y") / 4096.0,
                                 value(s, "g.z") / 4096.0);
          Vec3 d = target.subtract(logical);
          d = new Vec3(wrap(d.x), wrap(d.y), wrap(d.z));
          var basis = FRAMES[value(s, "g.frame")];
          return new Vec3(dot(d, basis[0]), 0, dot(d, basis[2]));
        });
        if (delta.length() < tolerance)
          return;
        context.getInput().lookAt((float)Math.toDegrees(Math.atan2(-delta.x, delta.z)),
                                  0);
        context.getInput().holdKey(InputConstants.KEY_W);
        context.waitTicks(1);
      }
      throw new AssertionError("Native walking reaches " + target + ": " +
                               position(server));
    } finally {
      context.getInput().releaseKey(InputConstants.KEY_W);
    }
  }

  private static void clickCube(ClientGameTestContext context, TestServerContext server,
                                int id) {
    var target = server.computeOnServer(s -> {
      var player = s.getPlayerList().getPlayers().getFirst();
      Interaction nearest = null;
      for (var entity : player.level().getAllEntities()) {
        var score = s.getScoreboard().getPlayerScoreInfo(
            entity, s.getScoreboard().getObjective("manifold"));
        if (entity instanceof Interaction interaction &&
            entity.entityTags().contains("manifold.object.proxy") && score != null &&
            score.value() == id &&
            (nearest == null ||
             entity.distanceToSqr(player) < nearest.distanceToSqr(player)))
          nearest = interaction;
      }
      if (nearest == null)
        throw new AssertionError("A proxy exists for cube " + id);
      return nearest.getBoundingBox().getCenter();
    });
    context.runOnClient(mc -> {
      mc.mouseHandler.grabMouse();
      mc.player.lookAt(EntityAnchorArgument.Anchor.EYES, target);
    });
    context.waitTicks(3);
    context.waitFor(mc -> mc.hitResult instanceof EntityHitResult, 60);
    context.getInput().pressMouse(InputConstants.MOUSE_BUTTON_RIGHT);
    context.waitTicks(4);
  }

  private static void place(ClientGameTestContext context, TestServerContext server,
                            Vec3 target) {
    Vec3 support = server.computeOnServer(
        s
        -> new Vec3(value(s, "g.dx"), value(s, "g.dy"), value(s, "g.dz")).scale(.501));
    placeAgainst(context, server, target, support);
  }

  private static void placeAgainst(ClientGameTestContext context,
                                   TestServerContext server, Vec3 target,
                                   Vec3 support) {
    Vec3 physical = server.computeOnServer(s -> project(s, target.add(support)));
    context.runOnClient(
        mc -> mc.player.lookAt(EntityAnchorArgument.Anchor.EYES, physical));
    context.waitTicks(5);
    server.waitFor(s -> value(s, "r.preview") == 1, 60);
    int cursor = server.computeOnServer(s -> {
      for (var entity :
           s.getPlayerList().getPlayers().getFirst().level().getAllEntities())
        if (entity.entityTags().contains("manifold.object.cursor"))
          return entity.getId();
      throw new AssertionError("A placement cursor exists");
    });
    context.waitFor(mc
                    -> mc.hitResult instanceof EntityHitResult hit &&
                           hit.getEntity().getId() == cursor,
                    60);
    context.getInput().pressMouse(InputConstants.MOUSE_BUTTON_RIGHT);
    context.waitTicks(4);
  }

  private static void turn(ClientGameTestContext context, TestServerContext server,
                           Vec3 direction) {
    var local = server.computeOnServer(s -> {
      var frame = FRAMES[value(s, "g.frame")];
      return new Vec3(dot(direction, frame[0]), dot(direction, frame[1]),
                      dot(direction, frame[2]));
    });
    context.getInput().lookAt((float)Math.toDegrees(Math.atan2(-local.x, local.z)),
                              (float)Math.toDegrees(Math.asin(-local.y)));
    context.waitTicks(3);
    context.getInput().holdKey(InputConstants.KEY_LCONTROL);
    context.waitTicks(4);
    context.getInput().releaseKey(InputConstants.KEY_LCONTROL);
    server.waitFor(s
                   -> value(s, "g.dx") == direction.x &&
                          value(s, "g.dy") == direction.y &&
                          value(s, "g.dz") == direction.z,
                   60);
  }

  private static Vec3 project(MinecraftServer server, Vec3 logical) {
    var local = logical.subtract(new Vec3(value(server, "r.wx") * 32,
                                          value(server, "r.wy") * 32,
                                          value(server, "r.wz") * 32));
    local = new Vec3(image(local.x), image(local.y), image(local.z));
    var basis = FRAMES[value(server, "g.frame")];
    return new Vec3(dot(local, basis[0]) + value(server, "h.slot") * 80 + .5,
                    dot(local, basis[1]) + 200.5, dot(local, basis[2]) + .5);
  }
  private static double image(double x) {
    return x - 64 * Math.floor((x + 16) / 64);
  }
  private static double wrap(double x) {
    return x - 64 * Math.floor((x + 32) / 64);
  }
  private static double dot(Vec3 p, double[] v) {
    return p.x * v[0] + p.y * v[1] + p.z * v[2];
  }
  private static Vec3 position(TestServerContext server) {
    return server.computeOnServer(s
                                  -> new Vec3(value(s, "g.x") / 4096.0,
                                              value(s, "g.y") / 4096.0,
                                              value(s, "g.z") / 4096.0));
  }
  private static CompoundTag cube(TestServerContext server, int id) {
    return server.computeOnServer(s
                                  -> s.getCommandStorage()
                                         .get(STORE)
                                         .getList("cubes")
                                         .orElseThrow()
                                         .getCompound(id)
                                         .orElseThrow()
                                         .copy());
  }
  private static int value(TestServerContext server, String name) {
    return server.computeOnServer(s -> value(s, name));
  }
  private static int value(MinecraftServer server, String name) {
    return TransportChecks.value(server, name);
  }
  private static void waitNative(ClientGameTestContext context,
                                 TestServerContext server) {
    server.waitFor(s
                   -> value(s, "h.mode") == 1 &&
                          s.getPlayerList().getPlayers().getFirst().onGround(),
                   400);
    context.waitFor(mc
                    -> mc.player != null && !mc.player.isSpectator() &&
                           mc.player.onGround() && mc.gui.screen() == null,
                    200);
    context.waitTicks(8);
  }
  private static double[][][] frames() {
    try (var stream =
             ThreeRingsChecks.class.getResourceAsStream("/manifold-build.json")) {
      var array = JsonParser
                      .parseReader(new InputStreamReader(Objects.requireNonNull(stream),
                                                         StandardCharsets.UTF_8))
                      .getAsJsonObject()
                      .getAsJsonArray("frames");
      var frames = new double[array.size()][3][3];
      for (int i = 0; i < frames.length; i++)
        for (int j = 0; j < 3; j++)
          for (int k = 0; k < 3; k++)
            frames[i][j][k] = array.get(i)
                                  .getAsJsonArray()
                                  .get(j)
                                  .getAsJsonArray()
                                  .get(k)
                                  .getAsDouble();
      return frames;
    } catch (Exception error) {
      throw new RuntimeException(error);
    }
  }
  private static void check(boolean value, String message) {
    if (!value)
      throw new AssertionError(message);
  }
}
