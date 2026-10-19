package dev.caimeo.manifold;

import net.fabricmc.fabric.api.client.gametest.v1.context.ClientGameTestContext;
import net.fabricmc.fabric.api.client.gametest.v1.context.TestServerContext;
import java.util.*;

/**
 * Verifies the playable renderer in the same physical scene as the diagnostic build.
 */
final class ProductionChecks {
  static void run(ClientGameTestContext context, TestServerContext server,
                  List<Map<String, Object>> checks, Runnable awaitChunks) {
    server.runCommand("function manifold:start");
    server.runCommand("function manifold:quality/low");
    waitNative(context, server);
    TransportChecks.run(server, checks);
    server.runCommand("function manifold:reset");
    waitNative(context, server);
    context.getInput().lookAt(0, 12);
    awaitChunks.run();
    context.waitTicks(20);
    var reference = GpuReadback.read(context, "swap");
    if (reference == null || GpuReadback.read(context, "probe").scalar(12) != 1)
      throw new AssertionError("The diagnostic renderer has a complete scene");
    try {
      select(context, "file/manifold-play.zip");
      awaitChunks.run();
      context.waitTicks(30);
      var actual = GpuReadback.read(context, "swap");
      if (actual == null || actual.width() != reference.width() ||
          actual.height() != reference.height())
        throw new AssertionError("Both profiles render the same viewport");
      long difference = 0, samples = 0;
      for (int y = actual.height() / 8; y < actual.height() * 7 / 8; y += 4)
        for (int x = actual.width() / 8; x < actual.width() * 7 / 8; x += 4) {
          int index = y * actual.width() + x;
          for (int shift : new int[] {8, 16, 24}) {
            difference += Math.abs(((actual.rgba()[index] >>> shift) & 255) -
                                   ((reference.rgba()[index] >>> shift) & 255));
            samples++;
          }
        }
      double meanError = difference / (double)samples;
      if (meanError > 2.0)
        throw new AssertionError(
            "Render profiles preserve the final scene: RGB error=" + meanError);
      checks.add(Map.of("case", "production_render_profile", "mean_rgb_error",
                        meanError, "samples", samples));
      context.takeScreenshot("manifold-production");
    } finally {
      select(context, "file/manifold.zip");
      server.runCommand("function manifold:stop");
      context.waitTicks(20);
    }
  }

  private static void select(ClientGameTestContext context, String pack) {
    var reload = context.computeOnClient(mc -> {
      var packs = mc.getResourcePackRepository();
      packs.reload();
      var ids = new ArrayList<>(packs.getSelectedIds());
      ids.remove("file/manifold.zip");
      ids.remove("file/manifold-play.zip");
      ids.add(pack);
      packs.setSelected(ids);
      return mc.reloadResourcePacks();
    });
    context.waitFor(mc -> reload.isDone(), 1200);
    reload.join();
    context.waitFor(mc -> mc.gui.overlay() == null, 400);
  }

  private static void waitNative(ClientGameTestContext context,
                                 TestServerContext server) {
    server.waitFor(s
                   -> TransportChecks.value(s, "h.mode") == 1 &&
                          s.getPlayerList().getPlayers().getFirst().onGround(),
                   400);
    context.waitFor(mc
                    -> mc.player != null && !mc.player.isSpectator() &&
                           mc.player.onGround() && mc.gui.screen() == null,
                    200);
    context.waitTicks(8);
  }
}
