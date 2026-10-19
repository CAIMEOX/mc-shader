package dev.caimeo.manifold;

import com.mojang.blaze3d.platform.InputConstants;
import net.fabricmc.fabric.api.client.gametest.v1.context.ClientGameTestContext;
import net.fabricmc.fabric.api.client.gametest.v1.context.TestServerContext;
import java.util.*;

/** Samples real player motion across local windows and periodic boundaries. */
final class ContinuityChecks {
  record Sample(long tick, double y, double z, double velocity, double clientVelocity,
                int mode, int waitTicks, int window, boolean grounded) {}
  record View(double time, double x, double y, double z, double ready, double mode) {}

  static void run(ClientGameTestContext context, TestServerContext server,
                  List<Map<String, Object>> checks) {
    server.runCommand("function manifold:three_rings/start");
    server.runCommand("function manifold:quality/low");
    server.waitFor(s
                   -> TransportChecks.value(s, "h.mode") == 1 &&
                          s.getPlayerList().getPlayers().getFirst().onGround(),
                   400);
    context.waitFor(mc
                    -> mc.player != null && !mc.player.isSpectator() &&
                           mc.player.onGround(),
                    200);
    context.waitTicks(8);
    context.getInput().lookAt(0, 0);
    var samples = new ArrayList<Sample>();
    context.getInput().holdKey(InputConstants.KEY_W);
    try {
      for (int step = 0; step < 90; step++) {
        context.waitTicks(1);
        var sample = sample(context, server);
        samples.add(sample);
        if (sample.z() >= 11)
          break;
      }
    } finally {
      context.getInput().releaseKey(InputConstants.KEY_W);
    }
    for (int step = 0; step < 160; step++) {
      context.waitTicks(1);
      var current = sample(context, server);
      if (samples.isEmpty() || current.tick() != samples.getLast().tick())
        samples.add(current);
    }
    double distance = 0;
    int frozen = 0, longestFrozen = 0, waiting = 0, crossings = 0, velocityResets = 0;
    for (int i = 1; i < samples.size(); i++) {
      var previous = samples.get(i - 1);
      var current = samples.get(i);
      if (current.z() < 10.8 || previous.z() < 10.8 ||
          current.tick() == previous.tick())
        continue;
      double delta = current.y() - previous.y();
      delta -= 64 * Math.rint(delta / 64);
      distance -= delta;
      if (Math.abs(delta) < .001)
        frozen += (int)(current.tick() - previous.tick());
      else
        frozen = 0;
      longestFrozen = Math.max(frozen, longestFrozen);
      if (current.mode() == 3)
        waiting++;
      if (current.window() != previous.window())
        crossings++;
      if (previous.clientVelocity() < -.5 &&
          current.clientVelocity() > previous.clientVelocity() + .03)
        velocityResets++;
    }
    checks.add(Map.of("case", "rings_continuous_fall", "samples", samples, "distance",
                      distance, "longest_frozen_ticks", longestFrozen,
                      "waiting_samples", waiting, "window_crossings", crossings,
                      "velocity_resets", velocityResets));
    if (samples.getLast().z() < 10.8 || distance < 128 || longestFrozen > 1 ||
        waiting != 0 || velocityResets != 0)
      throw new AssertionError(
          "Falling through open space stays continuous: distance=" + distance +
          ", frozen ticks=" + longestFrozen + ", waiting samples=" + waiting +
          ", velocity resets=" + velocityResets);
    var views = new ArrayList<View>();
    for (int i = 0; i < 96; i++) {
      context.waitTicks(1);
      var probe = GpuReadback.read(context, "probe");
      if (probe == null)
        throw new AssertionError("The falling camera has a GPU frame");
      views.add(new View(probe.scalar(17), probe.scalar(0), probe.scalar(1),
                         probe.scalar(2), probe.scalar(12), probe.scalar(48)));
    }
    double maxLateralError = 0, maxSpeed = 0;
    int discontinuities = 0;
    for (int i = 1; i < views.size(); i++) {
      var previous = views.get(i - 1);
      var current = views.get(i);
      double dt = ((current.time() - previous.time() + 1) % 1) * 24000;
      double dy = current.y() - previous.y();
      dy -= 64 * Math.rint(dy / 64);
      double lateral = current.x() - 10;
      lateral -= 64 * Math.rint(lateral / 64);
      maxLateralError = Math.max(maxLateralError, Math.abs(lateral));
      if (dt > .01)
        maxSpeed = Math.max(maxSpeed, Math.abs(dy) / dt);
      if (current.ready() != 1 || current.mode() != 1 || Math.abs(lateral) > .05 ||
          (dt > .01 && (dy > .05 || -dy > 4.2 * dt + .3 || -dy < .5 * dt)))
        discontinuities++;
    }
    checks.add(Map.of("case", "rings_falling_camera", "views", views, "discontinuities",
                      discontinuities, "max_lateral_error", maxLateralError,
                      "max_speed", maxSpeed));
    if (discontinuities != 0)
      throw new AssertionError(
          "The falling camera remains continuous across windows: " + discontinuities +
          ", lateral error=" + maxLateralError + ", speed=" + maxSpeed);
    directions(context, server, checks);
    server.runCommand("function manifold:stop");
    context.waitTicks(10);
  }

  private static void directions(ClientGameTestContext context,
                                 TestServerContext server,
                                 List<Map<String, Object>> checks) {
    String[] names = {"floor", "ceiling", "west", "east", "north", "south"};
    String[] axes = {"x", "y", "z"};
    int[] activeAxes = {1, 1, 0, 0, 2, 2};
    int[] signs = {-1, 1, -1, 1, -1, 1};
    for (int direction = 0; direction < names.length; direction++) {
      int axis = activeAxes[direction], sign = signs[direction];
      int[] initial = axis == 0   ? new int[] {40, 50, 50}
                      : axis == 1 ? new int[] {10, 40, 11}
                                  : new int[] {10, 10, 40};
      var commands = new ArrayList<String>();
      commands.add("gamemode spectator @s");
      commands.add("scoreboard players set #g.frame manifold 0");
      commands.add("scoreboard players set #g.cooldown manifold 0");
      for (int slot = 0; slot < 2; slot++)
        commands.add("scoreboard players set #h.cache" + slot + " manifold -1");
      for (int a = 0; a < 3; a++)
        commands.add("scoreboard players set #g." + axes[a] + " manifold " +
                     initial[a] * 4096);
      commands.add("function manifold:gravity/bounds");
      commands.add("function manifold:gravity/down/" + names[direction]);
      commands.add("function manifold:hybrid/land");
      commands.add("function manifold:gravity/publish");
      server.runOnServer(s -> {
        for (String command : commands)
          s.getCommands().performPrefixedCommand(
              s.createCommandSourceStack(),
              "execute as @a[tag=manifold.pilot,limit=1] at @s run " + command);
      });
      server.waitFor(s -> TransportChecks.value(s, "h.mode") == 1, 160);
      context.waitFor(mc -> !mc.player.isSpectator(), 120);
      context.waitTicks(8);
      int resets = 0, pauses = 0, visualErrors = 0, crossings = 0;
      double distance = 0, previousPosition = Double.NaN, previousVelocity = 0;
      int previousSlot = -1;
      var trajectory = new ArrayList<Map<String, Object>>();
      for (int step = 0; step < 90; step++) {
        context.waitTicks(1);
        double velocity = context.computeOnClient(mc -> mc.player.getDeltaMovement().y);
        var state = server.computeOnServer(
            s
            -> List.of(TransportChecks.value(s, "g." + axes[axis]) / 4096.0,
                       (double)TransportChecks.value(s, "h.mode"),
                       (double)TransportChecks.value(s, "h.slot")));
        double position = state.get(0);
        if (!Double.isNaN(previousPosition)) {
          double delta = position - previousPosition;
          delta -= 64 * Math.rint(delta / 64);
          distance += sign * delta;
        }
        if (previousVelocity < -.5 && velocity > previousVelocity + .03)
          resets++;
        if (state.get(1) != 1)
          pauses++;
        if (previousSlot >= 0 && state.get(2).intValue() != previousSlot)
          crossings++;
        previousPosition = position;
        previousVelocity = velocity;
        previousSlot = state.get(2).intValue();
        trajectory.add(Map.of("position", position, "velocity", velocity, "mode",
                              state.get(1), "slot", state.get(2)));
        if (step % 4 == 0) {
          var probe = GpuReadback.read(context, "probe");
          if (probe == null || probe.scalar(12) != 1 || probe.scalar(48) != 1) {
            visualErrors++;
          } else {
            for (int a = 0; a < 3; a++) {
              if (a == axis)
                continue;
              double error = probe.scalar(a) - initial[a];
              error -= 64 * Math.rint(error / 64);
              if (Math.abs(error) > .05)
                visualErrors++;
            }
          }
        }
      }
      checks.add(Map.of("case", "rings_axis_fall", "direction", names[direction],
                        "distance", distance, "velocity_resets", resets,
                        "waiting_samples", pauses, "visual_errors", visualErrors,
                        "window_crossings", crossings, "trajectory", trajectory));
      if (distance < 128 || crossings < 4 || resets != 0 || pauses != 0 ||
          visualErrors != 0)
        throw new AssertionError("Continuous native fall in " + names[direction] +
                                 ": distance=" + distance + ", resets=" + resets +
                                 ", pauses=" + pauses +
                                 ", visual errors=" + visualErrors);
    }
  }

  private static Sample sample(ClientGameTestContext context,
                               TestServerContext server) {
    double clientVelocity =
        context.computeOnClient(mc -> mc.player.getDeltaMovement().y);
    return server.computeOnServer(s -> {
      var player = s.getPlayerList().getPlayers().getFirst();
      return new Sample(
          s.overworld().getGameTime(), TransportChecks.value(s, "g.y") / 4096.0,
          TransportChecks.value(s, "g.z") / 4096.0, player.getDeltaMovement().y,
          clientVelocity, TransportChecks.value(s, "h.mode"),
          TransportChecks.value(s, "h.wait"), TransportChecks.value(s, "r.wy"),
          player.onGround());
    });
  }
}
