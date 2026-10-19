package dev.caimeo.manifold;

import net.fabricmc.fabric.api.client.gametest.v1.context.ClientGameTestContext;
import net.fabricmc.fabric.api.client.gametest.v1.context.TestServerContext;
import java.util.*;

public final class RuntimeMetrics {
  private static long frameNanos;
  public static void recordFrame(long duration) {
    frameNanos = duration;
  }
  static Map<String, Object> sample(ClientGameTestContext context,
                                    TestServerContext server) {
    var result = new LinkedHashMap<String, Object>();
    result.putAll(server.computeOnServer(s -> {
      var times = s.getTickTimesNanos();
      int entities = 0, proxies = 0, active = 0;
      var level = s.getPlayerList().getPlayers().getFirst().level();
      for (var entity : level.getAllEntities()) {
        entities++;
        if (entity.entityTags().contains("manifold.object.proxy"))
          proxies++;
        if (entity.entityTags().contains("manifold.object.active"))
          active++;
      }
      return Map.<String, Object>of(
          "tick", s.getTickCount(), "tick_ms",
          times[Math.floorMod(s.getTickCount() - 1, times.length)] / 1e6, "entities",
          entities, "proxies", proxies, "active_objects", active);
    }));
    result.putAll(context.computeOnClient(mc -> {
      var values = new LinkedHashMap<String, Object>();
      values.put("frame_ms", mc.getFrameTimeNs() / 1e6);
      values.put("frame_interval_ms", frameNanos / 1e6);
      values.put("width", mc.gameRenderer.mainRenderTarget().width);
      values.put("height", mc.gameRenderer.mainRenderTarget().height);
      double gpu = mc.getGpuUtilization();
      values.put("gpu_utilization", Double.isFinite(gpu) ? gpu : null);
      return values;
    }));
    return result;
  }

  static void observe(ClientGameTestContext context, TestServerContext server,
                      List<Map<String, Object>> checks, String phase) {
    var samples = new ArrayList<Map<String, Object>>();
    for (int i = 0; i < 40; i++) {
      context.waitTicks(1);
      samples.add(sample(context, server));
    }
    checks.add(Map.of("case", "runtime_timing", "phase", phase, "samples", samples));
  }

  static void rooms(ClientGameTestContext context, TestServerContext server,
                    List<Map<String, Object>> checks) {
    int slot = server.computeOnServer(s -> 1 - TransportChecks.value(s, "h.slot"));
    var samples = new ArrayList<Map<String, Object>>();
    for (int frame = 0; frame < 24; frame++) {
      int orientation = (frame + 1) % 24;
      double elapsed = server.computeOnServer(s -> {
        var source = s.createCommandSourceStack();
        long start = System.nanoTime();
        s.getCommands().performPrefixedCommand(
            source,
            "execute as @a[tag=manifold.pilot,limit=1] at @s run function manifold:rooms/build/" +
                slot + "/" + orientation);
        double ms = (System.nanoTime() - start) / 1e6;
        s.getCommands().performPrefixedCommand(
            source, "function manifold:rooms/select/" + (1 - slot));
        return ms;
      });
      context.waitTicks(2);
      var sample = new LinkedHashMap<>(sample(context, server));
      sample.put("build_ms", elapsed);
      sample.put("frame", orientation);
      samples.add(sample);
    }
    checks.add(Map.of("case", "room_build_timing", "samples", samples));
  }

  static void balanced(ClientGameTestContext context, TestServerContext server,
                       List<Map<String, Object>> checks, String phase) {
    server.runCommand("function manifold:quality/balanced");
    context.waitTicks(12);
    observe(context, server, checks, phase);
    server.runCommand("function manifold:quality/low");
    context.waitTicks(12);
  }
}
