package dev.caimeo.manifold;

import com.mojang.blaze3d.platform.InputConstants;
import net.fabricmc.fabric.api.client.gametest.v1.context.ClientGameTestContext;
import net.fabricmc.fabric.api.client.gametest.v1.context.TestServerContext;
import net.minecraft.world.scores.ScoreHolder;
import java.util.*;

/** Observes rendered continuity while the native carrier leaves the draw list. */
final class ShaderChecks {
  static void run(ClientGameTestContext context, TestServerContext server,
                  List<Map<String, Object>> checks) {
    context.runOnClient(mc -> {
      mc.options.cloudStatus().set(net.minecraft.client.CloudStatus.FANCY);
      mc.options.chunkSectionFadeInTime().set(.75);
    });
    server.runCommand("function manifold:start");
    server.runCommand("function manifold:quality/low");
    server.waitFor(s -> {
      var score = s.getScoreboard().getPlayerScoreInfo(
          ScoreHolder.forNameOnly("#h.mode"),
          s.getScoreboard().getObjective("manifold"));
      return score != null && score.value() == 1;
    }, 400);
    context.waitTicks(15);
    var initial = probe(context);
    check(initial.scalar(12) == 1 && initial.scalar(48) == 1,
          "The native room begins with an active shader frame");
    cameraSweep(context, checks, false);
    cameraGap(context, server, checks);
    nativeSurface(context, checks);
    turn(context, checks);
    roomTracking(context, server, checks);
    cameraSweep(context, checks, true);
    var samples = new ArrayList<Double>();
    try {
      carrierRange(server, 0);
      context.waitTicks(3);
      for (int i = 0; i < 3; i++) {
        samples.add(probe(context).scalar(12));
        context.waitTicks(1);
      }
      checks.add(Map.of("case", "shader_carrier_gap", "frame_ready", samples));
      check(samples.stream().allMatch(value -> value == 1),
            "Short carrier visibility gaps keep the scene rendered: " + samples);
      check(probe(context).scalar(70) > .05,
            "The visibility gap exercises a retained camera packet");
      context.waitTicks(24);
      check(probe(context).scalar(12) == 0,
            "An expired carrier frame returns control to native rendering");
      checks.add(Map.of("case", "shader_carrier_expiry", "frame_ready", 0));
    } finally {
      carrierRange(server, 4);
    }
    context.waitTicks(5);
    check(probe(context).scalar(12) == 1,
          "A visible carrier restores scene rendering after expiry");
    checks.add(Map.of("case", "shader_carrier_recovery", "frame_ready", 1));
    server.runCommand("function manifold:stop");
    context.waitTicks(24);
    check(probe(context).scalar(12) == 0,
          "Stopping the session releases the rendered scene within the cache lifetime");
    checks.add(Map.of("case", "shader_session_stop", "frame_ready", 0));
  }

  private static void roomTracking(ClientGameTestContext context,
                                   TestServerContext server,
                                   List<Map<String, Object>> checks) {
    server.runCommand(
        "execute in manifold:stage run tp @a[tag=manifold.pilot] 80.0 202.0 24.5 0 0");
    var samples = new ArrayList<Map<String, Object>>();
    double minimumReady = 1;
    for (int tick = 0; tick < 50; tick++) {
      context.waitTicks(1);
      var frame = probe(context);
      minimumReady = Math.min(minimumReady, frame.scalar(12));
      if (tick % 5 == 0)
        samples.add(Map.of("tick", tick, "frame_ready", frame.scalar(12), "packet_age",
                           frame.scalar(70), "position", server.computeOnServer(s -> {
                             var p = s.getPlayerList().getPlayers().getFirst();
                             return List.of(p.getX(), p.getY(), p.getZ());
                           })));
    }
    checks.add(Map.of("case", "shader_room_tracking", "samples", samples,
                      "minimum_frame_ready", minimumReady));
    context.takeScreenshot("manifold-room-tracking");
    check(minimumReady == 1,
          "The controller remains rendered throughout the physical room: " + samples);
  }

  private static void cameraSweep(ClientGameTestContext context,
                                  List<Map<String, Object>> checks, boolean moving) {
    context.runOnClient(mc -> mc.mouseHandler.grabMouse());
    context.getInput().lookAt(0, 0);
    context.waitTicks(3);
    var reference = probe(context);
    var basis =
        new org.joml.Matrix3f((float)reference.scalar(3), (float)reference.scalar(4),
                              (float)reference.scalar(5), (float)reference.scalar(6),
                              (float)reference.scalar(7), (float)reference.scalar(8),
                              (float)reference.scalar(9), (float)reference.scalar(10),
                              (float)reference.scalar(11));
    basis.mul(context.computeOnClient(
        mc
        -> new org.joml.Matrix3f()
               .rotation(mc.gameRenderer.mainCamera().rotation())
               .transpose()));
    var samples = new ArrayList<Map<String, Object>>();
    var observation = new LinkedHashMap<String, Object>();
    observation.put("case",
                    moving ? "shader_room_camera_motion" : "shader_camera_sweep");
    observation.put("samples", samples);
    checks.add(observation);
    double maximumError = 0;
    double minimumReady = 1;
    if (moving)
      context.getInput().holdKey(InputConstants.KEY_W);
    try {
      for (int yaw = 0; yaw < 360; yaw += 30) {
        for (int pitch : new int[] {0, -70, 70}) {
          context.getInput().lookAt(yaw, pitch);
          context.waitTicks(2);
          var frame = probe(context);
          var forward = context.computeOnClient(mc -> {
            var f = mc.gameRenderer.mainCamera().forwardVector();
            var logical = basis.transform(new org.joml.Vector3f(f));
            return List.of((double)logical.x(), (double)logical.y(),
                           (double)logical.z());
          });
          double error = Math.sqrt(Math.pow(frame.scalar(9) + forward.get(0), 2) +
                                   Math.pow(frame.scalar(10) + forward.get(1), 2) +
                                   Math.pow(frame.scalar(11) + forward.get(2), 2));
          maximumError = Math.max(maximumError, error);
          minimumReady = Math.min(minimumReady, frame.scalar(12));
          samples.add(Map.of("yaw", yaw, "pitch", pitch, "frame_ready",
                             frame.scalar(12), "packet_age", frame.scalar(70),
                             "forward_error", error));
          if (error > .01 || frame.scalar(12) < .5) {
            context.takeScreenshot("manifold-camera-alignment");
            context.waitTicks(24);
            observation.put("held_frame_ready", probe(context).scalar(12));
            observation.put("maximum_forward_error", maximumError);
            observation.put("minimum_frame_ready", minimumReady);
            check(false,
                  "Turning keeps native depth and architecture on the same camera: " +
                      samples.getLast());
          }
        }
      }
    } finally {
      context.getInput().releaseKey(InputConstants.KEY_W);
    }
    observation.put("maximum_forward_error", maximumError);
    observation.put("minimum_frame_ready", minimumReady);
  }

  private static void cameraGap(ClientGameTestContext context, TestServerContext server,
                                List<Map<String, Object>> checks) {
    context.getInput().lookAt(0, 0);
    context.waitTicks(3);
    carrierRange(server, 0);
    try {
      context.waitTicks(3);
      var previous = GpuReadback.read(context, "swap");
      context.getInput().lookAt(45, 0);
      context.waitTicks(2);
      var images = GpuReadback.readBatch(context, "minecraft:end_of_frame",
                                         List.of("probe", "swap"));
      var frame = images.get("probe");
      var displayed = images.get("swap");
      double error = 0;
      int samples = 0;
      for (int y = 8; y < displayed.height(); y += 16)
        for (int x = 8; x < displayed.width(); x += 16) {
          int offset = y * displayed.width() + x;
          for (int shift : new int[] {8, 16, 24}) {
            error += Math.abs(((previous.rgba()[offset] >>> shift) & 255) -
                              ((displayed.rgba()[offset] >>> shift) & 255)) /
                     255.0;
            samples++;
          }
        }
      error /= samples;
      checks.add(Map.of("case", "shader_coherent_frame_gap", "mean_channel_change",
                        error, "frame_ready", frame.scalar(12), "packet_age",
                        frame.scalar(70)));
      context.takeScreenshot("manifold-camera-gap");
      check(frame.scalar(12) == 1 && error < 1.0 / 255,
            "A controller gap retains a complete frame across mouse movement: " +
                error);
    } finally {
      carrierRange(server, 4);
    }
    context.waitTicks(4);
  }

  private static void nativeSurface(ClientGameTestContext context,
                                    List<Map<String, Object>> checks) {
    context.runOnClient(mc -> mc.mouseHandler.grabMouse());
    context.getInput().lookAt(90, 60);
    context.waitTicks(4);
    var images = GpuReadback.readBatch(context, "minecraft:end_of_frame",
                                       List.of("probe", "swap"));
    check(images != null, "The rendered surface and camera are observable together");
    var probe = images.get("probe");
    var scene = images.get("swap");
    check(probe.scalar(55) == 1 && Math.abs(probe.scalar(57) - 1.5) < .03,
          "The material sample belongs to the real collision floor");
    check(probe.scalar(68) > .999, "Native depth reconstructs the upward floor normal");
    int pixel = scene.rgba()[(scene.height() / 2) * scene.width() + scene.width() / 2];
    var actual = new ArrayList<Double>();
    var expected = new ArrayList<Double>();
    double maximumError = 0;
    for (int channel = 0; channel < 3; channel++) {
      double displayed = ((pixel >>> (24 - channel * 8)) & 255) / 255.0;
      double material = probe.scalar(64 + channel);
      actual.add(displayed);
      expected.add(material);
      maximumError = Math.max(maximumError, Math.abs(displayed - material));
    }
    checks.add(Map.of("case", "shader_native_material", "displayed", actual,
                      "architecture_material", expected, "maximum_channel_error",
                      maximumError, "logical_floor_y", probe.scalar(57)));
    check(maximumError <= 2.0 / 255,
          "The native floor uses the architecture material in the final frame: " +
              maximumError);
    context.takeScreenshot("manifold-shader-native-material");
  }

  private static void turn(ClientGameTestContext context,
                           List<Map<String, Object>> checks) {
    context.getInput().lookAt(90, 0);
    context.waitTicks(4);
    var modes = new ArrayList<Integer>();
    double minimumReady = 1;
    boolean landed = false;
    context.getInput().holdKey(InputConstants.KEY_LCONTROL);
    try {
      for (int tick = 0; tick < 120; tick++) {
        context.waitTicks(1);
        var frame = probe(context);
        int mode = (int)frame.scalar(48);
        if (modes.isEmpty() || modes.getLast() != mode)
          modes.add(mode);
        minimumReady = Math.min(minimumReady, frame.scalar(12));
        if (tick == 3)
          context.getInput().releaseKey(InputConstants.KEY_LCONTROL);
        if (mode == 1 && frame.scalar(51) == 1) {
          landed = true;
          break;
        }
      }
    } finally {
      context.getInput().releaseKey(InputConstants.KEY_LCONTROL);
    }
    checks.add(Map.of("case", "shader_gravity_transition", "modes", modes,
                      "minimum_frame_ready", minimumReady, "landed", landed));
    check(landed && modes.contains(2) && modes.contains(3),
          "The rendered camera follows turn, fall and native room handoff: " + modes);
    check(minimumReady == 1,
          "The shader remains active throughout gravity and room transitions");
    context.takeScreenshot("manifold-shader-wall-material");
  }

  private static void carrierRange(TestServerContext server, int range) {
    server.runCommand("execute in manifold:stage run data merge entity "
                      + "@e[type=minecraft:item_display,tag=manifold.carrier,limit=1] "
                      + "{view_range:" + range + "f}");
  }

  private static GpuReadback.Image probe(ClientGameTestContext context) {
    var value = GpuReadback.read(context, "probe");
    check(value != null && value.width() >= 64,
          "The rendered scene exposes its camera and controller observations");
    return value;
  }

  private static void check(boolean condition, String message) {
    if (!condition)
      throw new AssertionError(message);
  }
}
