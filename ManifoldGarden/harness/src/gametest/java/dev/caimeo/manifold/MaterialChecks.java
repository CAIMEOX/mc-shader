package dev.caimeo.manifold;

import net.fabricmc.fabric.api.client.gametest.v1.context.ClientGameTestContext;
import net.fabricmc.fabric.api.client.gametest.v1.context.TestServerContext;
import net.minecraft.commands.arguments.EntityAnchorArgument;
import net.minecraft.world.phys.Vec3;
import java.util.*;

/** Observes cube symbols and surface finish in the three-ring gallery. */
final class MaterialChecks {
  static void initialCubes(ClientGameTestContext context, TestServerContext server,
                           List<Map<String, Object>> checks) {
    var gpu = GpuReadback.read(context, "probe");
    if (gpu == null)
      throw new AssertionError("Material observations are available on the GPU");
    var observation = Map.<String, Object>of(
        "case", "material_cube_symbols", "dormant_arrow_contrast", gpu.scalar(80),
        "energized_arrow_contrast", gpu.scalar(81));
    checks.add(observation);
    if (!(gpu.scalar(80) > .25 && gpu.scalar(81) > .25))
      throw new AssertionError(
          "The orange direction arrow remains legible in both activation states: " +
          observation);
    checks.add(Map.of("case", "material_periodic_finish", "periodic_error",
                      gpu.scalar(85), "distant_subpixel_change", gpu.scalar(86)));
    if (!(gpu.scalar(85) < .0005 && gpu.scalar(86) < .01))
      throw new AssertionError(
          "Architectural texture stays continuous through wrapping and distant subpixel motion");
    var endcaps = Map.<String, Object>of(
        "case", "material_direction_endcaps", "inward_cross_contrast", gpu.scalar(87),
        "outward_dot_contrast", gpu.scalar(88), "endcap_ring_contrast", gpu.scalar(89),
        "outward_diagonal_contrast", gpu.scalar(90));
    checks.add(endcaps);
    if (!(gpu.scalar(87) > .25 && gpu.scalar(88) > .25 && gpu.scalar(89) > .25 &&
          gpu.scalar(90) < .01))
      throw new AssertionError(
          "Cube axes distinguish inward cross and outward dot endcaps: " + endcaps);
    cubeFaces(context, server, checks);
  }

  private static void cubeFaces(ClientGameTestContext context, TestServerContext server,
                                List<Map<String, Object>> checks) {
    var original = server.computeOnServer(
        s -> s.getPlayerList().getPlayers().getFirst().position());
    var pose = context.computeOnClient(
        mc -> List.of(mc.player.getYRot(), mc.player.getXRot()));
    boolean hidden = context.computeOnClient(mc -> mc.gui.hud.isHidden());
    var contrasts = new ArrayList<Double>();
    var glyphs = new ArrayList<String>();
    server.runOnServer(s -> {
      var source = s.createCommandSourceStack();
      s.getCommands().performPrefixedCommand(source, "tag @a remove manifold.pilot");
      s.getCommands().performPrefixedCommand(source, "gamemode spectator @a");
    });
    try {
      Vec3 centre = new Vec3(27.5, 203.5, 4.5);
      // The source's -X face touches its support. Observe all exposed faces.
      for (var normal :
           List.of(new Vec3(1, 0, 0), new Vec3(0, 1, 0), new Vec3(0, -1, 0),
                   new Vec3(0, 0, 1), new Vec3(0, 0, -1))) {
        boolean axial = Math.abs(normal.x) > .8;
        Vec3 up = axial ? new Vec3(0, 1, 0) : new Vec3(1, 0, 0);
        Vec3 right = up.cross(normal);
        Vec3 eye = centre.add(normal.scale(2));
        server.runCommand("execute in manifold:stage run tp @a " + eye.x + " " +
                          (eye.y - 1.62) + " " + eye.z);
        context.waitTicks(5);
        Vec3 surface = centre.add(normal.scale(.5));
        Vec3 glyph = axial ? surface.add(right.scale(.08)).add(up.scale(.08))
                           : surface.add(right.scale(.16)).add(up.scale(-.076));
        Vec3 field = axial ? surface.add(right.scale(.10))
                           : surface.add(right.scale(.16)).add(up.scale(.05));
        double[] mark = pixelAt(context, glyph), background = pixelAt(context, field);
        double contrast = 0;
        for (int c = 0; c < 3; c++)
          contrast += Math.pow(mark[c] - background[c], 2);
        contrasts.add(Math.sqrt(contrast));
        glyphs.add(axial ? "inward" : "arrow");
      }
      checks.add(Map.of("case", "material_visible_cube_faces", "glyphs", glyphs,
                        "glyph_contrasts", contrasts));
      if (!contrasts.stream().allMatch(value -> value > .15))
        throw new AssertionError(
            "The initial orange cube shows its direction glyph on every exposed face: " +
            contrasts);
      server.runCommand("execute in manifold:stage run tp @a 17.0 192.38 18.0");
      context.waitTicks(6);
      context.runOnClient(mc -> {
        if (!mc.gui.hud.isHidden())
          mc.gui.hud.toggle();
        mc.player.lookAt(EntityAnchorArgument.Anchor.EYES, new Vec3(17.0, 199.0, 4.5));
      });
      context.waitTicks(4);
      context.takeScreenshot("manifold-material-gallery");
    } finally {
      server.runOnServer(s -> {
        var source = s.createCommandSourceStack();
        s.getCommands().performPrefixedCommand(
            source, "execute in manifold:stage run tp @a " + original.x + " " +
                        original.y + " " + original.z + " " + pose.get(0) + " " +
                        pose.get(1));
        s.getCommands().performPrefixedCommand(source, "gamemode adventure @a");
        s.getCommands().performPrefixedCommand(source, "tag @a add manifold.pilot");
      });
      context.runOnClient(mc -> {
        if (mc.gui.hud.isHidden() != hidden)
          mc.gui.hud.toggle();
      });
      context.waitTicks(8);
    }
  }

  private static double[] pixelAt(ClientGameTestContext context, Vec3 point) {
    context.runOnClient(
        mc -> mc.player.lookAt(EntityAnchorArgument.Anchor.EYES, point));
    context.waitTicks(3);
    var image = GpuReadback.read(context, "swap");
    int rgba = image.rgba()[(image.height() / 2) * image.width() + image.width() / 2];
    return new double[] {(rgba >>> 24) / 255.0, ((rgba >>> 16) & 255) / 255.0,
                         ((rgba >>> 8) & 255) / 255.0};
  }
}
