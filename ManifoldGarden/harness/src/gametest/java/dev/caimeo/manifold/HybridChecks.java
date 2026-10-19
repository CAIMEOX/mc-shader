package dev.caimeo.manifold;

import com.mojang.blaze3d.platform.InputConstants;
import net.fabricmc.fabric.api.client.gametest.v1.context.ClientGameTestContext;
import net.fabricmc.fabric.api.client.gametest.v1.context.TestServerContext;
import net.minecraft.core.BlockPos;
import net.minecraft.core.registries.Registries;
import net.minecraft.resources.Identifier;
import net.minecraft.resources.ResourceKey;
import net.minecraft.world.level.GameType;
import net.minecraft.world.level.Level;
import net.minecraft.world.phys.Vec3;
import net.minecraft.world.scores.ScoreHolder;
import java.util.*;

/** Exercises native movement across a six-axis room transition. */
final class HybridChecks {
  private static final ResourceKey<Level> STAGE =
      ResourceKey.create(Registries.DIMENSION, Identifier.parse("manifold:stage"));
  static void run(ClientGameTestContext context, TestServerContext server,
                  List<Map<String, Object>> checks) {
    var originalPosition = server.computeOnServer(
        s -> s.getPlayerList().getPlayers().getFirst().position());
    var originalDimension = server.computeOnServer(
        s -> s.getPlayerList().getPlayers().getFirst().level().dimension());
    var originalMode = server.computeOnServer(
        s -> s.getPlayerList().getPlayers().getFirst().gameMode.getGameModeForPlayer());
    Set<Long> originalTickets = server.computeOnServer(
        s -> new HashSet<Long>(s.getLevel(STAGE).getForceLoadedChunks()));

    server.runCommand("function manifold:start");
    server.runCommand("function manifold:quality/low");
    server.waitFor(s -> {
      var player = s.getPlayerList().getPlayers().getFirst();
      return value(s, "h.mode") == 1 && player.level().dimension().equals(STAGE) &&
          player.gameMode.getGameModeForPlayer() == GameType.ADVENTURE;
    }, 400);
    context.waitFor(mc
                    -> mc.level != null && mc.player != null &&
                           mc.level.dimension().equals(STAGE) &&
                           !mc.player.isSpectator() &&
                           !mc.player.getAbilities().flying && mc.gui.screen() == null,
                    400);
    context.runOnClient(mc -> mc.mouseHandler.grabMouse());
    server.waitFor(s -> s.getPlayerList().getPlayers().getFirst().onGround(), 100);
    context.waitFor(mc -> mc.player.onGround(), 100);
    context.waitTicks(12);
    check(score(server, "h.mode") == 1 && score(server, "h.slot") == 0,
          "The session enters the first physical room");
    check(server.computeOnServer(s -> {
      var player = s.getPlayerList().getPlayers().getFirst();
      return player.level().dimension().equals(STAGE) &&
          player.gameMode.getGameModeForPlayer() == GameType.ADVENTURE;
    }),
          "Native adventure movement runs in the stage dimension");
    check(context.computeOnClient(mc -> mc.getCameraEntity() == mc.player),
          "The player's own camera controls the physical room");
    checks.add(Map.of("case", "hybrid_stage", "dimension", "manifold:stage", "slot", 0,
                      "mode", "adventure"));
    context.takeScreenshot("manifold-hybrid-entrance");

    nativeJump(context, server, checks);

    jumpAcrossSeam(context, server, checks);
    walkWithViewBobbing(context, server, checks);

    context.getInput().lookAt(90, 0);
    context.waitTicks(5);
    context.getInput().holdKey(InputConstants.KEY_LCONTROL);
    boolean transitionObserved = false;
    boolean landingObserved = false;
    boolean spectatorObserved = false;
    Vec3 landingPosition = null;
    Vec3 landingCenter = null;
    double waitingDrift = 0;
    List<Integer> modes = new ArrayList<>();
    try {
      for (int tick = 0; tick < 100; tick++) {
        int mode = score(server, "h.mode");
        if (modes.isEmpty() || modes.getLast() != mode)
          modes.add(mode);
        transitionObserved |= mode == 2;
        landingObserved |= mode == 3;
        spectatorObserved |= context.computeOnClient(mc -> mc.player.isSpectator());
        if (mode == 3) {
          if (landingPosition == null) {
            landingPosition = position(server);
            landingCenter = logicalPosition(server);
            context.getInput().holdKey(InputConstants.KEY_W);
          } else {
            waitingDrift =
                Math.max(waitingDrift, position(server).distanceTo(landingPosition));
          }
        } else if (landingPosition != null) {
          context.getInput().releaseKey(InputConstants.KEY_W);
        }
        if (tick == 4)
          context.getInput().releaseKey(InputConstants.KEY_LCONTROL);
        if (mode == 1 && score(server, "h.slot") == 1)
          break;
        context.waitTicks(1);
      }
    } finally {
      context.getInput().releaseKey(InputConstants.KEY_LCONTROL);
      context.getInput().releaseKey(InputConstants.KEY_W);
    }
    check(transitionObserved && spectatorObserved,
          "Native gravity input enters the virtual turn and fall");
    check(score(server, "h.mode") == 1 && score(server, "h.slot") == 1,
          "Wall landing hands control to the second physical room: modes=" + modes);
    server.waitFor(s -> s.getPlayerList().getPlayers().getFirst().onGround(), 60);
    check(server.computeOnServer(s -> {
      var player = s.getPlayerList().getPlayers().getFirst();
      return player.gameMode.getGameModeForPlayer() == GameType.ADVENTURE &&
          player.level().dimension().equals(STAGE);
    }),
          "The turned room supports native adventure interaction");
    check(score(server, "g.dx") == -1 && score(server, "g.dy") == 0 &&
              score(server, "g.dz") == 0,
          "The second room represents westward logical gravity");
    check(landingPosition != null && waitingDrift > .05,
          "Native forward input moves the temporary spectator during landing wait");
    double placementError = position(server).distanceTo(landingPosition);
    check(
        placementError < .35,
        "Native control resumes at the landing target after spectator movement: error=" +
            placementError);
    checks.add(Map.of("case", "hybrid_native_turn_land", "modes", modes,
                      "landing_observed", landingObserved, "slot", 1, "position",
                      coordinates(position(server))));
    context.waitTicks(10);
    var landedGpu = hybridProbe(context, 1, 1);
    Vec3 expectedEye = landingCenter.add(.72, 0, 0);
    double eyeError =
        new Vec3(landedGpu.scalar(0), landedGpu.scalar(1), landedGpu.scalar(2))
            .distanceTo(expectedEye);
    check(eyeError < .35,
          "The native eye stays near the logical landing eye: error=" + eyeError);
    checks.add(Map.of("case", "hybrid_landing_input", "spectator_drift", waitingDrift,
                      "placement_error", placementError, "eye_error", eyeError));
    context.takeScreenshot("manifold-hybrid-wall-room");

    server.runCommand("function manifold:stop");
    context.waitTicks(10);
    check(server.computeOnServer(s -> {
      var player = s.getPlayerList().getPlayers().getFirst();
      return player.level().dimension().equals(originalDimension) &&
          player.gameMode.getGameModeForPlayer() == originalMode &&
          !player.entityTags().contains("manifold.pilot");
    }),
          "Stopping restores the saved dimension, game mode and session ownership");
    double returnError = position(server).distanceTo(originalPosition);
    check(returnError < .05,
          "Stopping restores the saved player position: error=" + returnError);
    check(server.computeOnServer(
              s
              -> new HashSet<Long>(s.getLevel(STAGE).getForceLoadedChunks())
                     .equals(originalTickets)),
          "Stopping releases the session's forced stage chunks");
    checks.add(Map.of("case", "hybrid_session_stop", "return_error", returnError,
                      "dimension", originalDimension.identifier().toString(),
                      "restored_force_load_count", originalTickets.size()));
  }

  private static void nativeJump(ClientGameTestContext context,
                                 TestServerContext server,
                                 List<Map<String, Object>> checks) {
    Vec3 standing = position(server);
    List<Map<String, Object>> samples = new ArrayList<>();
    Map<String, Object> observation = new LinkedHashMap<>();
    observation.put("case", "hybrid_native_collision");
    observation.put("standing_y", standing.y);
    observation.put("samples", samples);
    checks.add(observation);
    double clientPeak = standing.y;
    double serverPeak = standing.y;
    boolean inputObserved = false;
    boolean airborneObserved = false;
    context.getInput().holdKey(InputConstants.KEY_SPACE);
    try {
      for (int tick = 0; tick < 40; tick++) {
        context.waitTicks(1);
        var client = context.computeOnClient(
            mc
            -> Map.<String, Object>of(
                "y", mc.player.getY(), "grounded", mc.player.onGround(), "flying",
                mc.player.getAbilities().flying, "spectator", mc.player.isSpectator(),
                "key_down", mc.options.keyJump.isDown(), "jump_input",
                mc.player.input.keyPresses.jump(), "screen",
                mc.gui.screen() == null ? "game"
                                        : mc.gui.screen().getClass().getSimpleName()));
        var authoritative = server.computeOnServer(s -> {
          var player = s.getPlayerList().getPlayers().getFirst();
          return Map.<String, Object>of("y", player.getY(), "grounded",
                                        player.onGround(), "mode", value(s, "h.mode"),
                                        "logical_grounded", value(s, "g.grounded"));
        });
        samples.add(Map.of("tick", tick, "client", client, "server", authoritative));
        double clientY = (Double)client.get("y");
        double serverY = (Double)authoritative.get("y");
        clientPeak = Math.max(clientPeak, clientY);
        serverPeak = Math.max(serverPeak, serverY);
        inputObserved |= (Boolean)client.get("jump_input");
        airborneObserved |=
            !(Boolean)authoritative.get("grounded") && serverY > standing.y + .2;
        if (tick == 2)
          context.getInput().releaseKey(InputConstants.KEY_SPACE);
        if (tick > 3 && airborneObserved && (Boolean)authoritative.get("grounded") &&
            (Boolean)client.get("grounded"))
          break;
      }
    } finally {
      context.getInput().releaseKey(InputConstants.KEY_SPACE);
    }
    observation.put("client_peak_y", clientPeak);
    observation.put("server_peak_y", serverPeak);
    observation.put("jump_input_observed", inputObserved);
    check(inputObserved && airborneObserved && serverPeak > standing.y + .5,
          "Native jump input produces an airborne trajectory on the server: " +
              observation);
    waitForFloor(context, server, standing.y);
    observation.put("settled_y", position(server).y);
    check(Math.abs(position(server).y - standing.y) < .01 &&
              context.computeOnClient(mc -> mc.player.onGround()),
          "A native jump returns to the same physical floor");
    check(score(server, "h.mode") == 1,
          "Native floor contact preserves physical interaction mode");
  }

  private static void walkWithViewBobbing(ClientGameTestContext context,
                                          TestServerContext server,
                                          List<Map<String, Object>> checks) {
    Vec3 start = position(server);
    boolean previousBobbing = context.computeOnClient(mc -> {
      boolean previous = mc.options.bobView().get();
      mc.options.bobView().set(true);
      mc.mouseHandler.grabMouse();
      return previous;
    });
    context.getInput().lookAt(90, 60);
    context.waitTicks(3);
    List<List<Double>> surfacePoints = new ArrayList<>();
    double maximumSurfaceError = 0;
    context.getInput().holdKey(InputConstants.KEY_W);
    try {
      for (int sample = 0; sample < 8; sample++) {
        context.waitTicks(1);
        var gpu = hybridProbe(context, 1, 0);
        double floorError = Math.abs(gpu.scalar(57) - 1.5);
        maximumSurfaceError = Math.max(maximumSurfaceError, floorError);
        check(gpu.scalar(55) == 1 && gpu.scalar(54) > 0 &&
                  Double.isFinite(gpu.scalar(54)),
              "View bobbing keeps the native floor inside the interaction window");
        check(
            floorError < .03,
            "Inverse-projected native depth lies on the physical floor during bobbing: error=" +
                floorError);
        surfacePoints.add(List.of(gpu.scalar(56), gpu.scalar(57), gpu.scalar(58)));
      }
    } finally {
      context.getInput().releaseKey(InputConstants.KEY_W);
      context.runOnClient(mc -> mc.options.bobView().set(previousBobbing));
    }
    double distance = position(server).distanceTo(start);
    check(distance > .5, "The depth samples cover native walking with view bobbing");
    checks.add(Map.of("case", "hybrid_walking_bob_depth", "walked", distance,
                      "maximum_surface_error", maximumSurfaceError,
                      "logical_floor_points", surfacePoints));
    server.runCommand("execute as @a[tag=manifold.pilot] at @s run tp @s " + start.x +
                      " " + start.y + " " + start.z + " 0 20");
    context.waitTicks(8);
  }

  private static void jumpAcrossSeam(ClientGameTestContext context,
                                     TestServerContext server,
                                     List<Map<String, Object>> checks) {
    Vec3 returnPosition = position(server);
    int originalFrame = score(server, "g.frame");
    server.runCommand(
        "execute as @a[tag=manifold.pilot] at @s run tp @s 31.7 202 8.5 -90 0");
    context.waitTicks(8);
    context.runOnClient(mc -> mc.mouseHandler.grabMouse());
    double floor = position(server).y;
    List<Map<String, Object>> trajectory = new ArrayList<>();
    Map<String, Object> observation = new LinkedHashMap<>();
    observation.put("case", "hybrid_native_jump_seam");
    observation.put("floor_y", floor);
    observation.put("fixture_position", coordinates(position(server)));
    observation.put("trajectory", trajectory);
    checks.add(observation);
    var fixture = server.computeOnServer(s -> {
      var player = s.getPlayerList().getPlayers().getFirst();
      var level = s.getLevel(STAGE);
      var body = player.getBoundingBox();
      var support =
          BlockPos.containing(player.getX(), player.getY() - .01, player.getZ());
      return Map.of(
          "support",
          !level.getBlockState(support).getCollisionShape(level, support).isEmpty(),
          "body_clear", level.noCollision(player, body), "jump_clear",
          level.noCollision(player, body.expandTowards(0, 1.3, 0)));
    });
    observation.put("fixture_collision", fixture);
    check(fixture.get("support") && fixture.get("body_clear") &&
              fixture.get("jump_clear"),
          "The periodic jump fixture has physical support and full jump clearance: " +
              fixture);
    waitForFloor(context, server, floor);
    Vec3 previous = context.computeOnClient(mc -> mc.player.position());
    double maximumHeight = floor;
    double seamHeightChange = 0;
    int crossingTick = -1;
    context.getInput().holdKey(InputConstants.KEY_W);
    context.getInput().holdKey(InputConstants.KEY_SPACE);
    try {
      for (int tick = 0; tick < 45; tick++) {
        context.waitTicks(1);
        Vec3 current = context.computeOnClient(mc -> mc.player.position());
        var state =
            server.computeOnServer(s
                                   -> List.of(value(s, "h.mode"), value(s, "g.frame"),
                                              value(s, "g.grounded")));
        maximumHeight = Math.max(maximumHeight, current.y);
        trajectory.add(Map.of("tick", tick, "position", coordinates(current),
                              "grounded", state.get(2), "mode", state.get(0), "frame",
                              state.get(1)));
        observation.put("maximum_height", maximumHeight);
        check(
            state.get(0) == 1 && state.get(1) == originalFrame,
            "Gravity selection during an airborne seam crossing preserves the room orientation");
        if (tick == 1)
          context.getInput().releaseKey(InputConstants.KEY_SPACE);
        if (previous.x - current.x > 16) {
          check(crossingTick < 0, "The jump crosses one native period boundary");
          crossingTick = tick;
          seamHeightChange = Math.abs(current.y - previous.y);
          observation.put("crossing_tick", crossingTick);
          observation.put("height_change", seamHeightChange);
          check(current.y > floor + .2 && state.get(2) == 0,
                "Period wrapping preserves airborne contact state");
          context.getInput().holdKey(InputConstants.KEY_LCONTROL);
        }
        if (crossingTick >= 0 && tick >= crossingTick + 2) {
          context.getInput().releaseKey(InputConstants.KEY_LCONTROL);
          context.getInput().releaseKey(InputConstants.KEY_W);
        }
        previous = current;
        if (crossingTick >= 0 && tick > crossingTick + 3 &&
            Math.abs(current.y - floor) < .01 && state.get(2) == 1)
          break;
      }
    } finally {
      context.getInput().releaseKey(InputConstants.KEY_SPACE);
      context.getInput().releaseKey(InputConstants.KEY_W);
      context.getInput().releaseKey(InputConstants.KEY_LCONTROL);
    }
    observation.put("crossing_tick", crossingTick);
    observation.put("height_change", seamHeightChange);
    observation.put("maximum_height", maximumHeight);
    check(
        crossingTick >= 0 && maximumHeight > floor + .5 && seamHeightChange < .5,
        "A native jump has a continuous vertical trajectory through the periodic seam");
    waitForFloor(context, server, floor);
    check(Math.abs(position(server).y - floor) < .01 &&
              score(server, "g.grounded") == 1,
          "The seam-crossing jump lands on the repeated physical floor");
    observation.put("settled_y", position(server).y);
    server.runCommand("execute as @a[tag=manifold.pilot] at @s run tp @s " +
                      returnPosition.x + " " + returnPosition.y + " " +
                      returnPosition.z + " 0 20");
    context.waitTicks(8);
  }

  private static void waitForFloor(ClientGameTestContext context,
                                   TestServerContext server, double floor) {
    server.waitFor(s -> {
      var player = s.getPlayerList().getPlayers().getFirst();
      return Math.abs(player.getY() - floor) < .01 && player.onGround() &&
          value(s, "g.grounded") == 1;
    }, 60);
    context.waitFor(
        mc -> Math.abs(mc.player.getY() - floor) < .01 && mc.player.onGround(), 60);
  }

  private static GpuReadback.Image hybridProbe(ClientGameTestContext context, int mode,
                                               int slot) {
    var probe = Objects.requireNonNull(GpuReadback.read(context, "probe"));
    check(probe.scalar(48) == mode && probe.scalar(51) == slot,
          "The rendered camera follows the authoritative mode and native slot");
    return probe;
  }

  private static Vec3 position(TestServerContext server) {
    return server.computeOnServer(
        s -> s.getPlayerList().getPlayers().getFirst().position());
  }

  private static Vec3 logicalPosition(TestServerContext server) {
    return server.computeOnServer(s
                                  -> new Vec3(value(s, "g.x") / 4096.0,
                                              value(s, "g.y") / 4096.0,
                                              value(s, "g.z") / 4096.0));
  }

  private static List<Double> coordinates(Vec3 position) {
    return List.of(position.x, position.y, position.z);
  }

  private static int score(TestServerContext server, String name) {
    return server.computeOnServer(s -> value(s, name));
  }

  private static int value(net.minecraft.server.MinecraftServer server, String name) {
    var board = server.getScoreboard();
    var score = board.getPlayerScoreInfo(ScoreHolder.forNameOnly("#" + name),
                                         board.getObjective("manifold"));
    if (score == null)
      throw new AssertionError("Missing controller state " + name);
    return score.value();
  }

  private static void check(boolean condition, String message) {
    if (!condition)
      throw new AssertionError(message);
  }
}
