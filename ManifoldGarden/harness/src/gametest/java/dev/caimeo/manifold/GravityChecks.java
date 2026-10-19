package dev.caimeo.manifold;

import com.mojang.blaze3d.platform.InputConstants;
import net.fabricmc.fabric.api.client.gametest.v1.context.ClientGameTestContext;
import net.fabricmc.fabric.api.client.gametest.v1.context.TestServerContext;
import net.minecraft.world.scores.ScoreHolder;
import java.util.*;

/** Observes vanilla input packets, generated commands and rendered camera state. */
final class GravityChecks {
  private static final int UNIT = 4096, PERIOD = 32 * UNIT;
  private static final String[] AXES = {"x", "y", "z"};
  private static final String[] DIRECTIONS = {"floor", "ceiling", "west",
                                              "east",  "north",   "south"};
  private static final int[][] DOWN = {{0, -1, 0}, {0, 1, 0},  {-1, 0, 0},
                                       {1, 0, 0},  {0, 0, -1}, {0, 0, 1}};

  static void run(ClientGameTestContext context, TestServerContext server,
                  List<Map<String, Object>> checks) {
    var originalMode = server.computeOnServer(
        s -> s.getPlayerList().getPlayers().getFirst().gameMode.getGameModeForPlayer());
    var originalPosition = server.computeOnServer(
        s -> s.getPlayerList().getPlayers().getFirst().position());
    server.runCommand("function manifold:flight");
    server.runCommand("function manifold:quality/low");
    context.waitTicks(25);
    var ready = probe(context);
    check(ready.scalar(12) == 1 && ready.scalar(15) == 1,
          "Gravity scene and camera packet reach the GPU");
    check(context.computeOnClient(
              mc -> mc.player.isSpectator() && mc.getCameraEntity() == mc.player),
          "The player's own spectator camera supplies native mouse input");
    context.takeScreenshot("manifold-gravity-flight");
    checks.add(Map.of("case", "gravity_scene", "camera", "player", "logical_position",
                      vector(server, "")));

    // The input keys pass through the actual client keyboard and vanilla input
    // predicates.
    int[] keys = {InputConstants.KEY_W,     InputConstants.KEY_S,
                  InputConstants.KEY_A,     InputConstants.KEY_D,
                  InputConstants.KEY_SPACE, InputConstants.KEY_LSHIFT};
    String[] scores = {"forward", "forward", "left", "left", "jump", "sneak"};
    int[] expected = {1, -1, 1, -1, 1, 1};
    for (int i = 0; i < keys.length; i++) {
      context.getInput().holdKey(keys[i]);
      context.waitTicks(5);
      check(score(server, scores[i]) == expected[i],
            "Spectator key reaches controller: " + scores[i]);
      context.getInput().releaseKey(keys[i]);
      context.waitTicks(5);
      check(score(server, scores[i]) == 0, "Spectator key releases: " + scores[i]);
    }
    checks.add(Map.of("case", "gravity_native_keys", "keys", 6));

    call(server, "reset");
    context.waitTicks(3);
    context.getInput().holdKey(InputConstants.KEY_SPACE);
    context.getInput().holdKey(InputConstants.KEY_LSHIFT);
    context.waitTicks(12);
    check(score(server, "fly") == 0, "Holding the flight chord toggles exactly once");
    context.getInput().releaseKey(InputConstants.KEY_SPACE);
    context.getInput().releaseKey(InputConstants.KEY_LSHIFT);
    context.waitTicks(4);
    checks.add(Map.of("case", "gravity_flight_chord", "flight", score(server, "fly")));

    call(server, "reset");
    set(server, "running", 0);
    context.waitTicks(12);
    context.runOnClient(mc -> mc.mouseHandler.grabMouse());
    context.getInput().moveCursor(1, 1);
    context.waitTicks(2);
    var beforeMouse = probe(context);
    float yawBefore = context.computeOnClient(mc -> mc.player.getYRot());
    for (int i = 0; i < 4; i++) {
      context.getInput().moveCursor(25, 5);
      context.waitTicks(1);
    }
    context.waitTicks(5);
    var afterMouse = probe(context);
    float yawAfter = context.computeOnClient(mc -> mc.player.getYRot());
    double viewDifference = 0;
    for (int i = 3; i < 12; i++)
      viewDifference += Math.abs(afterMouse.scalar(i) - beforeMouse.scalar(i));
    check(Math.abs(yawAfter - yawBefore) > .1 && viewDifference > .01,
          "Mouse motion changes the rendered logical camera: yaw=" + yawBefore +
              " -> " + yawAfter + ", basis=" + viewDifference);
    checks.add(
        Map.of("case", "gravity_native_mouse", "basis_difference", viewDifference));
    context.runOnClient(mc -> mc.mouseHandler.releaseMouse());

    // Every orientation uses the same periodic beams and preserves world momentum.
    for (int direction = 0; direction < 6; direction++) {
      setVector(server, "", 8 * UNIT, 8 * UNIT, 8 * UNIT);
      setVector(server, "v", -1000, 350, 90);
      setVector(server, "a", 0, 0, 0);
      set(server, "cooldown", 0);
      call(server, "down/" + DIRECTIONS[direction]);
      check(vector(server, "v").equals(List.of(-1000, 350, 90)),
            "Gravity switching preserves world velocity");
      for (int i = 0; i < 3; i++)
        check(score(server, "d" + AXES[i]) == DOWN[direction][i],
              "Selected gravity axis");
      int axis = DOWN[direction][0] != 0 ? 0 : DOWN[direction][1] != 0 ? 1 : 2;
      int sign = DOWN[direction][axis];
      int[] p = {0, 0, 0}, v = {0, 0, 0};
      p[(axis + 1) % 3] = 8 * UNIT;
      p[axis] = sign < 0 ? 4 * UNIT : PERIOD - 4 * UNIT;
      v[axis] = sign * 20 * UNIT;
      setVector(server, "", p[0], p[1], p[2]);
      setVector(server, "v", v[0], v[1], v[2]);
      call(server, "move");
      int bound = 6144 + 3686;
      check(score(server, AXES[axis]) == (sign < 0 ? bound : PERIOD - bound),
            "Swept collision stops at the first beam face");
      check(score(server, "grounded") == 1 && score(server, "v" + AXES[axis]) == 0,
            "Contact establishes grounded along the selected axis");
      var contact = vector(server, "");
      for (int tick = 0; tick < 5; tick++)
        call(server, "step");
      check(vector(server, "").equals(contact), "Standing contact is stable");
      checks.add(Map.of("case", "gravity_face_contact", "direction",
                        DIRECTIONS[direction], "position", contact));
    }

    // Exercise signed wrapping on all axes at empty points, including corner crossings.
    for (int axis = 0; axis < 3; axis++)
      for (int sign : new int[] {-1, 1}) {
        int[] p = {8 * UNIT, 8 * UNIT, 8 * UNIT}, v = {0, 0, 0};
        p[axis] = sign > 0 ? PERIOD - 20 : 20;
        v[axis] = sign * 100;
        setVector(server, "", p[0], p[1], p[2]);
        setVector(server, "v", v[0], v[1], v[2]);
        call(server, "move");
        check(score(server, AXES[axis]) == (sign > 0 ? 80 : PERIOD - 80),
              "Periodic coordinates wrap in both directions");
        check(score(server, "v" + AXES[axis]) == sign * 100,
              "A seam preserves momentum");
      }
    checks.add(Map.of("case", "gravity_six_seams", "crossings", 6));

    // A narrow clearance admits the sideways body but rejects a taller one.
    setVector(server, "", 8 * UNIT, 6144 + 1229, 0);
    set(server, "cooldown", 0);
    call(server, "down/west");
    set(server, "cooldown", 0);
    int frameBefore = score(server, "frame");
    call(server, "down/floor");
    check(score(server, "blocked") == 1 && score(server, "frame") == frameBefore,
          "A turn that intersects a beam leaves the body frame unchanged");
    checks.add(Map.of("case", "gravity_turn_clearance", "blocked", true));

    // Trigger a visible quarter turn at rest and sample the actual GPU quaternion.
    call(server, "reset");
    set(server, "running", 0);
    setVector(server, "", 8 * UNIT, 8 * UNIT, 8 * UNIT);
    call(server, "publish");
    context.waitTicks(14);
    call(server, "down/west");
    List<List<Double>> orientations = new ArrayList<>();
    boolean intermediate = false;
    for (int i = 0; i < 16; i++) {
      var gpu = probe(context);
      List<Double> q = new ArrayList<>();
      for (int j = 36; j < 40; j++)
        q.add(gpu.scalar(j));
      double norm = q.stream().mapToDouble(x -> x * x).sum();
      check(Math.abs(norm - 1) < .001, "Rendered gravity orientation stays normalized");
      if (gpu.scalar(13) > .005 && gpu.scalar(13) < .395)
        intermediate = true;
      orientations.add(q);
      context.waitTicks(1);
    }
    check(intermediate, "The GPU renders intermediate gravity orientations");
    var settled = probe(context);
    check(Math.abs(settled.scalar(0) - (8 + .72)) < .002 &&
              Math.abs(settled.scalar(1) - 8) < .002,
          "The eye offset rotates with gravity");
    checks.add(Map.of("case", "gravity_camera_turn", "quaternions", orientations));
    context.takeScreenshot("manifold-gravity-wall");

    // A physical player teleport is absent from the logical camera.
    var logicalBefore = GpuReadback.read(context, "scene_low");
    var eyeBefore = probe(context);
    server.runCommand(
        "execute as @a[tag=manifold.pilot] at @s run tp @s 15 210 12 ~ ~");
    context.waitTicks(8);
    var logicalAfter = GpuReadback.read(context, "scene_low");
    var eyeAfter = probe(context);
    for (int i = 0; i < 3; i++)
      check(Math.abs(eyeAfter.scalar(i) - eyeBefore.scalar(i)) < .0001,
            "Physical position does not move the virtual eye");
    double difference = imageDifference(logicalBefore, logicalAfter);
    check(difference < .2,
          "Rebasing preserves the rendered scene: mean RGB error=" + difference);
    checks.add(Map.of("case", "gravity_input_rebase", "mean_rgb_error", difference));

    set(server, "cooldown", 0);
    call(server, "down/east");
    context.waitTicks(14);
    var opposite = probe(context);
    double qnorm = 0;
    for (int i = 36; i < 40; i++)
      qnorm += opposite.scalar(i) * opposite.scalar(i);
    check(Math.abs(qnorm - 1) < .001 && Math.abs(opposite.scalar(0) - (8 - .72)) < .002,
          "A half turn reaches the opposite gravity with a finite camera pose");
    checks.add(Map.of("case", "gravity_half_turn", "eye_x", opposite.scalar(0)));

    // Complete the playable loop with vanilla W and Ctrl input.
    call(server, "reset");
    server.runCommand("tp @a[tag=manifold.pilot] 0 200 0 90 0");
    context.waitTicks(8);
    check(Math.abs(context.computeOnClient(mc -> mc.player.getYRot()) - 90) < .1,
          "The flight fixture faces west");
    check(Math.abs(score(server, "fx") + UNIT) <= 1 &&
              Math.abs(score(server, "fz")) <= 1,
          "World-space input agrees with the native camera direction");
    context.getInput().holdKey(InputConstants.KEY_W);
    context.waitTicks(8);
    context.getInput().releaseKey(InputConstants.KEY_W);
    int flyingX = score(server, "x");
    check(flyingX < 8 * UNIT, "Flying follows the player's view");
    context.getInput().holdKey(InputConstants.KEY_LCONTROL);
    context.waitTicks(3);
    checks.add(Map.of("case", "gravity_switch_input", "sprint", score(server, "sprint"),
                      "want", score(server, "want"), "blocked",
                      score(server, "blocked"), "direction", vector(server, "d"),
                      "position", vector(server, ""), "forward", vector(server, "f"),
                      "yaw", context.computeOnClient(mc -> mc.player.getYRot())));
    context.getInput().releaseKey(InputConstants.KEY_LCONTROL);
    context.waitTicks(30);
    check(score(server, "dx") == -1 && score(server, "grounded") == 1,
          "Flying west, selecting gravity and landing on the wall completes: down=" +
              vector(server, "d") + ", position=" + vector(server, "") + ", velocity=" +
              vector(server, "v") + ", grounded=" + score(server, "grounded"));
    context.takeScreenshot("manifold-gravity-landing");
    checks.add(Map.of("case", "gravity_fly_turn_land", "flight_x", flyingX, "position",
                      vector(server, ""), "fps",
                      context.computeOnClient(mc -> mc.getFps())));

    call(server, "stop");
    context.waitTicks(8);
    check(server.computeOnServer(
              s
              -> !s.getPlayerList().getPlayers().getFirst().entityTags().contains(
                  "manifold.pilot")),
          "The session releases its player");
    check(score(server, "running") == 0, "Session stop ends logical simulation");
    double returnError = server.computeOnServer(
        s
        -> s.getPlayerList().getPlayers().getFirst().position().distanceTo(
            originalPosition));
    check(returnError < .05,
          "Session stop restores the saved position: error=" + returnError);
    check(server.computeOnServer(s
                                 -> s.getPlayerList()
                                        .getPlayers()
                                        .getFirst()
                                        .gameMode.getGameModeForPlayer()) ==
              originalMode,
          "Session stop restores the original game mode");
    checks.add(Map.of("case", "gravity_session_stop", "running", 0, "return_error",
                      returnError));

    context.waitTicks(12);
  }

  private static GpuReadback.Image probe(ClientGameTestContext c) {
    var result = GpuReadback.read(c, "probe");
    check(result != null, "GPU probe is available");
    return result;
  }
  private static void call(TestServerContext s, String function) {
    s.runCommand(
        "execute as @a[tag=manifold.pilot,limit=1] at @s run function manifold:gravity/" +
        function);
  }
  private static void set(TestServerContext s, String name, int value) {
    s.runCommand("scoreboard players set #g." + name + " manifold " + value);
  }
  private static void setVector(TestServerContext s, String prefix, int x, int y,
                                int z) {
    set(s, prefix + "x", x);
    set(s, prefix + "y", y);
    set(s, prefix + "z", z);
  }
  private static int score(TestServerContext s, String name) {
    return s.computeOnServer(server -> {
      var board = server.getScoreboard();
      var value = board.getPlayerScoreInfo(ScoreHolder.forNameOnly("#g." + name),
                                           board.getObjective("manifold"));
      if (value == null)
        throw new AssertionError("Missing controller state " + name);
      return value.value();
    });
  }
  private static List<Integer> vector(TestServerContext s, String prefix) {
    return List.of(score(s, prefix + "x"), score(s, prefix + "y"),
                   score(s, prefix + "z"));
  }
  private static double imageDifference(GpuReadback.Image a, GpuReadback.Image b) {
    double sum = 0;
    for (int i = 0; i < a.rgba().length; i++)
      for (int shift : new int[] {8, 16, 24})
        sum += Math.abs(((a.word(i) >> shift) & 255) - ((b.word(i) >> shift) & 255));
    return sum / (a.rgba().length * 3);
  }
  private static void check(boolean ok, String message) {
    if (!ok)
      throw new AssertionError(message);
  }
}
