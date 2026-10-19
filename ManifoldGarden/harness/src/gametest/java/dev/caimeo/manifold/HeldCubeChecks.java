package dev.caimeo.manifold;

import net.fabricmc.fabric.api.client.gametest.v1.context.ClientGameTestContext;
import java.util.*;

/** Observes the carried cube's world orientation through real camera input. */
final class HeldCubeChecks {
  static void run(ClientGameTestContext context, List<Map<String, Object>> checks,
                  int id) {
    var pose = context.computeOnClient(
        mc -> List.of(mc.player.getYRot(), mc.player.getXRot()));
    String cube = List.of("blue", "amber", "green").get(id);
    var samples = new ArrayList<Map<String, Object>>();
    double maximumError = 0;
    boolean visible = true;
    try {
      context.runOnClient(mc -> mc.mouseHandler.grabMouse());
      for (int yaw : new int[] {-135, -45, 0, 45, 90, 180}) {
        for (int pitch : new int[] {-70, 0, 70}) {
          context.getInput().lookAt(yaw, pitch);
          context.waitTicks(3);
          var gpu = GpuReadback.read(context, "probe");
          if (gpu == null)
            throw new AssertionError("The held cube is observable on the GPU");
          var errors = List.of(gpu.scalar(91), gpu.scalar(92), gpu.scalar(93));
          for (double error : errors)
            maximumError = Math.max(maximumError, error);
          visible &= gpu.scalar(12) == 1 && gpu.scalar(72) == 2 &&
                     gpu.scalar(99) == id && gpu.scalar(94) == 1 &&
                     gpu.scalar(95) > .15;
          samples.add(Map.of("yaw", yaw, "pitch", pitch, "world_axis_errors", errors,
                             "visible", gpu.scalar(94), "color_magnitude",
                             gpu.scalar(95)));
          if (yaw == 45 && pitch <= 0)
            context.takeScreenshot("manifold-held-" + cube +
                                   (pitch == 0 ? "-level" : "-up"));
        }
      }
    } finally {
      context.getInput().lookAt(pose.get(0), pose.get(1));
      context.waitTicks(4);
    }
    checks.add(Map.of("case", "held_cube_world_orientation", "cube", cube,
                      "maximum_world_axis_error", maximumError, "visible", visible,
                      "samples", samples));
    if (!(maximumError < .001 && visible))
      throw new AssertionError(
          "The carried " + cube +
          " cube keeps its world axes while the player looks around: error=" +
          maximumError + ", visible=" + visible);
  }
}
