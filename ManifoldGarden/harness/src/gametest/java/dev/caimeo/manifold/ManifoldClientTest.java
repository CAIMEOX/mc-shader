package dev.caimeo.manifold;

import com.google.gson.GsonBuilder;
import net.fabricmc.fabric.api.client.gametest.v1.FabricClientGameTest;
import net.fabricmc.fabric.api.client.gametest.v1.context.ClientGameTestContext;
import net.fabricmc.fabric.api.client.gametest.v1.world.TestWorldSave;
import net.minecraft.world.level.storage.LevelResource;
import java.nio.file.*;
import java.util.*;

public final class ManifoldClientTest implements FabricClientGameTest {
  private final Map<String, Object> report = new LinkedHashMap<>();
  private final List<Map<String, Object>> checks = new ArrayList<>();
  @Override
  public void runTest(ClientGameTestContext context) {
    String suite = System.getenv().getOrDefault("MANIFOLD_TEST_SUITE", "all");
    report.put("result", "running");
    report.put("suite", suite);
    report.put("minecraft", "26.3");
    report.put("renderer", "physical rooms and periodic architecture");
    report.put("checks", checks);
    try {
      if (!Set.of("all", "hybrid", "flight", "entry", "shader", "rings", "joinery",
                  "joinery-render", "continuity", "rendering", "ui")
               .contains(suite))
        throw new IllegalArgumentException("Unknown Manifold test suite: " + suite);
      var reload = context.computeOnClient(mc -> {
        var packs = mc.getResourcePackRepository();
        packs.reload();
        var ids = new ArrayList<>(packs.getSelectedIds());
        ids.add("file/manifold.zip");
        packs.setSelected(ids);
        mc.options.renderDistance().set(5);
        mc.options.bobView().set(false);
        mc.options.enableVsync().set(false);
        mc.options.framerateLimit().set(60);
        mc.options.inactivityFpsLimit().set(
            net.minecraft.client.InactivityFpsLimit.MINIMIZED);
        mc.options.pauseOnLostFocus = false;
        mc.options.chatOpacity().set(0.0);
        mc.options.textBackgroundOpacity().set(0.0);
        mc.getWindow().setTitle("Manifold · hybrid gravity tests");
        return mc.reloadResourcePacks();
      });
      context.waitFor(mc -> reload.isDone(), 1200);
      reload.join();
      context.waitFor(mc -> mc.gui.overlay() == null, 400);
      TestWorldSave save;
      try (var bootstrap = context.worldBuilder().create()) {
        save = bootstrap.getWorldSave();
        var server = bootstrap.getServer();
        var loading = server.computeOnServer(s -> {
          var dir = s.getWorldPath(LevelResource.DATAPACK_DIR);
          Files.createDirectories(dir);
          Files.copy(Path.of("manifold-datapack.zip"), dir.resolve("manifold.zip"),
                     StandardCopyOption.REPLACE_EXISTING);
          var packs = s.getPackRepository();
          packs.reload();
          var ids = new ArrayList<>(packs.getSelectedIds());
          ids.add("file/manifold.zip");
          if (Set.of("entry", "all", "rings", "joinery", "joinery-render")
                  .contains(suite)) {
            try (var archive = FileSystems.newFileSystem(
                     Path.of("manifold-launch-datapack.zip"))) {
              var root = archive.getPath("/");
              try (var paths = Files.walk(root)) {
                for (var path : paths.toList()) {
                  var destination = dir.resolve("manifold_launch")
                                        .resolve(root.relativize(path).toString());
                  if (Files.isDirectory(path))
                    Files.createDirectories(destination);
                  else
                    Files.copy(path, destination, StandardCopyOption.REPLACE_EXISTING);
                }
              }
            }
            packs.reload();
            ids.add("file/manifold_launch");
          }
          packs.setSelected(ids);
          return s.reloadResources(ids);
        });
        context.waitFor(mc -> loading.isDone(), 600);
        loading.join();
      }
      // Dimension registries are built while opening the saved world.
      try (var world = save.open()) {
        try {
          var server = world.getServer();
          report.put("world", save.getSaveDirectory().toString());
          context.getInput().resizeWindow(1280, 900);
          server.runOnServer(s
                             -> ((net.minecraft.client.server.IntegratedServer)s)
                                    .setWorldAllowCommands(true));
          server.runOnServer(s -> {
            var source = s.createCommandSourceStack();
            if (Set.of("entry", "all", "rings", "joinery", "joinery-render")
                    .contains(suite))
              s.getCommands().performPrefixedCommand(
                  source,
                  "scoreboard players operation @a manifold.launch_seen = #generation manifold.launch");
            s.getCommands().performPrefixedCommand(source, "function manifold:stop");
          });
          server.runCommand("gamemode spectator @a");
          server.runCommand("tp @a 0.0 67.0 4.0 0 5");
          context.waitTicks(40);
          world.getConnection().waitForChunksRender(false, 400);
          if (suite.equals("all") || suite.equals("flight"))
            GravityChecks.run(context, server, checks);
          if (suite.equals("all") || suite.equals("hybrid"))
            HybridChecks.run(context, server, checks);
          if (suite.equals("all") || suite.equals("shader"))
            ShaderChecks.run(context, server, checks);
          if (suite.equals("all") || suite.equals("shader"))
            ProductionChecks.run(
                context, server, checks,
                () -> world.getConnection().waitForChunksRender(false, 400));
          if (suite.equals("rings") || suite.equals("all"))
            ThreeRingsChecks.run(context, server, checks);
          if (suite.equals("joinery") || suite.equals("all"))
            JoineryChecks.run(context, server, checks);
          if (suite.equals("joinery-render"))
            JoineryChecks.presentation(context, server, checks);
          if (suite.equals("continuity") || suite.equals("all"))
            ContinuityChecks.run(context, server, checks);
          if (suite.equals("rendering") || suite.equals("all"))
            VisibilityChecks.run(context, server, checks);
          if (suite.equals("entry") || suite.equals("all"))
            EntryChecks.run(context, server, checks);
          if (suite.equals("ui") || suite.equals("all"))
            MessageChecks.run(context, server, checks);
          report.put("result", "passed");
          persist();
        } catch (Throwable error) {
          try {
            context.takeScreenshot("manifold-world-failure");
          } catch (Throwable screenshotError) {
            error.addSuppressed(screenshotError);
          }
          throw error;
        }
      }
    } catch (Throwable error) {
      report.put("result", "failed");
      report.put("failure", error.toString());
      persist();
      try {
        context.takeScreenshot("manifold-failure");
      } catch (Throwable ignored) {
      }
      throw new RuntimeException(error);
    }
  }
  private void persist() {
    try {
      Files.writeString(Path.of("manifold-report.json"),
                        new GsonBuilder().setPrettyPrinting().create().toJson(report));
    } catch (Exception error) {
      throw new RuntimeException(error);
    }
  }
}
