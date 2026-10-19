package dev.caimeo.manifold;

import com.google.gson.JsonParser;
import com.mojang.blaze3d.platform.InputConstants;
import net.fabricmc.fabric.api.client.gametest.v1.context.ClientGameTestContext;
import net.fabricmc.fabric.api.client.gametest.v1.context.TestServerContext;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.*;

/** Compares rendered ray hits with the authored periodic solid geometry. */
final class VisibilityChecks {
  record Box(double[] lo, double[] hi, int channel) {}

  static void run(ClientGameTestContext context, TestServerContext server,
                  List<Map<String, Object>> checks) {
    var boxes = solids();
    server.runCommand("function manifold:three_rings/start");
    server.runCommand("function manifold:quality/low");
    server.waitFor(s
                   -> TransportChecks.value(s, "h.mode") == 1 &&
                          s.getPlayerList().getPlayers().getFirst().onGround(),
                   400);
    context.waitFor(mc -> !mc.player.isSpectator() && mc.player.onGround(), 200);
    context.waitTicks(20);
    RuntimeMetrics.observe(context, server, checks, "entry");
    RuntimeMetrics.balanced(context, server, checks, "entry_balanced");
    RuntimeMetrics.rooms(context, server, checks);
    RuntimeMetrics.observe(context, server, checks, "after_room_rotations");
    context.getInput().lookAt(0, 0);
    context.getInput().holdKey(InputConstants.KEY_W);
    try {
      server.waitFor(s -> TransportChecks.value(s, "g.z") >= 11 * 4096, 100);
    } finally {
      context.getInput().releaseKey(InputConstants.KEY_W);
    }
    var samples = new ArrayList<Map<String, Object>>();
    var errors = new ArrayList<Map<String, Object>>();
    int compared = 0, missing = 0, unexpected = 0;
    for (int frame = 0; frame < 72; frame++) {
      if (frame % 12 == 0)
        context.getInput().lookAt(new int[] {180, 90, 0, 270, 180, 90}[frame / 12],
                                  -20);
      context.waitTicks(1);
      var gpu = GpuReadback.read(context, "probe");
      if (gpu == null || gpu.scalar(12) != 1)
        throw new AssertionError("The visibility sample has an active frame");
      double[] origin = {gpu.scalar(0), gpu.scalar(1), gpu.scalar(2)};
      var currentBoxes = new ArrayList<>(boxes);
      for (int id = 0; id < 3; id++) {
        if (gpu.scalar(112 + id) == 1)
          continue;
        double[] lo = new double[3], hi = new double[3];
        for (int a = 0; a < 3; a++) {
          lo[a] = gpu.scalar(103 + id * 3 + a) - .5;
          hi[a] = lo[a] + 1;
        }
        currentBoxes.add(new Box(lo, hi, -1));
      }
      int frameMissing = 0, frameUnexpected = 0;
      for (int y = 0; y < 18; y++)
        for (int x = 0; x < 32; x++) {
          int index = (y + 1) * gpu.width() + x * 8;
          double[] direction = {gpu.scalar(index + 3), gpu.scalar(index + 4),
                                gpu.scalar(index + 5)};
          double expected = intersect(origin, direction, currentBoxes, gpu);
          double actual = gpu.scalar(index);
          if (expected > 120 && actual > 120)
            continue;
          compared++;
          double tolerance = .15 + Math.min(expected, actual) * .005;
          boolean miss = expected < 120 && actual > expected + tolerance;
          boolean extra = actual < 120 && actual < expected - tolerance;
          if (miss)
            frameMissing++;
          if (extra)
            frameUnexpected++;
          if ((miss && frameMissing <= 2 || extra && frameUnexpected <= 2) &&
              errors.size() < 150)
            errors.add(Map.of(
                "frame", frame, "pixel", List.of(x, y), "expected", expected, "actual",
                actual, "native", gpu.scalar(index + 1), "native_sdf",
                gpu.scalar(index + 6), "origin", origin, "direction", direction));
        }
      missing += frameMissing;
      unexpected += frameUnexpected;
      var sample = new LinkedHashMap<>(RuntimeMetrics.sample(context, server));
      sample.put("missing", frameMissing);
      sample.put("unexpected", frameUnexpected);
      sample.put("slot", gpu.scalar(51));
      samples.add(sample);
      if ((frameMissing + frameUnexpected > 10) && frame % 12 == 0)
        context.takeScreenshot("manifold-visibility-" + frame);
    }
    RuntimeMetrics.observe(context, server, checks, "sustained_fall");
    RuntimeMetrics.balanced(context, server, checks, "sustained_fall_balanced");
    checks.add(Map.of("case", "rings_surface_visibility", "compared_rays", compared,
                      "missing_hits", missing, "unexpected_hits", unexpected, "samples",
                      samples, "errors", errors));
    if (missing + unexpected != 0)
      throw new AssertionError(
          "Visible surfaces match the periodic level: missing=" + missing +
          ", unexpected=" + unexpected + ", compared=" + compared);
    diagonal(context, server, checks);
    server.runCommand("function manifold:stop");
    context.waitTicks(10);
  }

  private static void diagonal(ClientGameTestContext context, TestServerContext server,
                               List<Map<String, Object>> checks) {
    server.runOnServer(s -> {
      for (String command : List.of(
               "gamemode spectator @s", "scoreboard players set #g.x manifold 118784",
               "scoreboard players set #g.y manifold 163840",
               "scoreboard players set #g.z manifold 204800",
               "scoreboard players set #g.frame manifold 0",
               "function manifold:gravity/bounds", "function manifold:hybrid/land",
               "function manifold:gravity/publish"))
        s.getCommands().performPrefixedCommand(
            s.createCommandSourceStack(),
            "execute as @a[tag=manifold.pilot,limit=1] at @s run " + command);
    });
    server.waitFor(s -> TransportChecks.value(s, "h.mode") == 1, 160);
    context.waitFor(mc -> !mc.player.isSpectator(), 120);
    context.waitTicks(8);
    context.getInput().lookAt(-90, 0);
    var samples = new ArrayList<Map<String, Object>>();
    double maxHorizontal = 0, maxVertical = 0;
    context.getInput().holdKey(InputConstants.KEY_W);
    try {
      for (int i = 0; i < 72; i++) {
        context.waitTicks(1);
        var gpu = GpuReadback.read(context, "probe");
        var position = server.computeOnServer(
            s
            -> List.of(TransportChecks.value(s, "g.x") / 4096.0,
                       TransportChecks.value(s, "g.y") / 4096.0));
        double dx = gpu.scalar(0) - position.get(0);
        double dy = gpu.scalar(1) - position.get(1) - .72;
        dx -= 64 * Math.rint(dx / 64);
        dy -= 64 * Math.rint(dy / 64);
        maxHorizontal = Math.max(maxHorizontal, Math.abs(dx));
        maxVertical = Math.max(maxVertical, Math.abs(dy));
        samples.add(Map.of("horizontal_error", dx, "vertical_error", dy,
                           "render_origin", List.of(gpu.scalar(0), gpu.scalar(1)),
                           "server_position", position));
      }
    } finally {
      context.getInput().releaseKey(InputConstants.KEY_W);
    }
    checks.add(Map.of("case", "rings_diagonal_camera", "samples", samples,
                      "max_horizontal_error", maxHorizontal, "max_vertical_error",
                      maxVertical));
    if (maxHorizontal > 1 || maxVertical > 12)
      throw new AssertionError("Diagonal falling keeps window origins aligned: " +
                               maxHorizontal + ", " + maxVertical);
  }

  private static List<Box> solids() {
    try (var input =
             VisibilityChecks.class.getResourceAsStream("/manifold-build.json")) {
      var array = JsonParser
                      .parseReader(new InputStreamReader(Objects.requireNonNull(input),
                                                         StandardCharsets.UTF_8))
                      .getAsJsonObject()
                      .getAsJsonArray("rings_solids");
      var result = new ArrayList<Box>();
      for (var element : array) {
        var b = element.getAsJsonObject();
        double[] lo = new double[3], hi = new double[3];
        for (int a = 0; a < 3; a++) {
          lo[a] = b.getAsJsonArray("lo").get(a).getAsDouble();
          hi[a] = b.getAsJsonArray("hi").get(a).getAsDouble();
        }
        result.add(new Box(lo, hi, b.get("channel").getAsInt()));
      }
      return result;
    } catch (Exception error) {
      throw new RuntimeException(error);
    }
  }

  private static double intersect(double[] origin, double[] direction, List<Box> boxes,
                                  GpuReadback.Image gpu) {
    double best = 1e7;
    // Every image intersecting this short ray lies in the surrounding five cells.
    for (int ox = -2; ox <= 2; ox++)
      for (int oy = -2; oy <= 2; oy++)
        for (int oz = -2; oz <= 2; oz++) {
          double[] local = {origin[0] - 64 * (Math.floor(origin[0] / 64) + ox),
                            origin[1] - 64 * (Math.floor(origin[1] / 64) + oy),
                            origin[2] - 64 * (Math.floor(origin[2] / 64) + oz)};
          for (var box : boxes) {
            if (box.channel() >= 0 && gpu.scalar(100 + box.channel()) == 1)
              continue;
            double near = 0, far = 120;
            for (int a = 0; a < 3 && near <= far; a++) {
              if (Math.abs(direction[a]) < 1e-9) {
                if (local[a] < box.lo()[a] || local[a] > box.hi()[a])
                  far = -1;
              } else {
                double t0 = (box.lo()[a] - local[a]) / direction[a];
                double t1 = (box.hi()[a] - local[a]) / direction[a];
                near = Math.max(near, Math.min(t0, t1));
                far = Math.min(far, Math.max(t0, t1));
              }
            }
            if (near <= far && far > .01)
              best = Math.min(best, near);
          }
        }
    return best;
  }
}
