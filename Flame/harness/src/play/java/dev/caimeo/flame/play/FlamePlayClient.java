package dev.caimeo.flame.play;

import com.google.gson.GsonBuilder;
import com.mojang.blaze3d.platform.InputConstants;
import net.fabricmc.api.ClientModInitializer;
import net.fabricmc.fabric.api.client.event.lifecycle.v1.ClientTickEvents;
import net.fabricmc.fabric.api.client.keymapping.v1.KeyMappingHelper;
import net.minecraft.client.KeyMapping;
import net.minecraft.client.Minecraft;
import net.minecraft.network.chat.Component;
import net.minecraft.resources.Identifier;
import net.minecraft.world.level.GameType;
import java.nio.file.*;
import java.util.Map;
import java.util.ArrayList;
import java.util.List;
import net.minecraft.world.scores.ScoreHolder;

public final class FlamePlayClient implements ClientModInitializer {
  private Object serverIdentity;
  private int ticks;
  private boolean preparing, ready;
  private int smokeStage, smokeClock, smokeAttempts, lastEpoch;
  private boolean smokePending;
  private String failure = "";
  private final List<Integer> verifiedModes = new ArrayList<>();
  private KeyMapping ignite, quench, stage, rescan;
  @Override
  public void onInitializeClient() {
    if (!Boolean.getBoolean("flame.play"))
      return;
    var category =
        KeyMapping.Category.register(Identifier.parse("flame_play:controls"));
    ignite = KeyMappingHelper.registerKeyMapping(
        new KeyMapping("key.flame_play.ignite", InputConstants.KEY_R, category));
    quench = KeyMappingHelper.registerKeyMapping(
        new KeyMapping("key.flame_play.quench", InputConstants.KEY_X, category));
    stage = KeyMappingHelper.registerKeyMapping(
        new KeyMapping("key.flame_play.stage", InputConstants.KEY_F6, category));
    rescan = KeyMappingHelper.registerKeyMapping(
        new KeyMapping("key.flame_play.rescan", InputConstants.KEY_F7, category));
    ClientTickEvents.END_CLIENT_TICK.register(this::tick);
  }
  private void tick(Minecraft client) {
    var server = client.getSingleplayerServer();
    if (server == null || client.player == null) {
      serverIdentity = null;
      ready = false;
      preparing = false;
      ticks = 0;
      return;
    }
    if (serverIdentity != server) {
      serverIdentity = server;
      ready = false;
      preparing = false;
      ticks = 0;
      smokeStage = 0;
      smokeClock = 0;
      smokeAttempts = 0;
      smokePending = false;
      failure = "";
      verifiedModes.clear();
    }
    ticks++;
    if (!ready && !preparing && ticks >= 25) {
      preparing = true;
      var playerId = client.player.getUUID();
      server.execute(() -> {
        var player = server.getPlayerList().getPlayer(playerId);
        if (player == null)
          return;
        server.setWorldAllowCommands(true);
        player.setGameMode(GameType.SPECTATOR);
        var commands = server.getCommands();
        var source = server.createCommandSourceStack().withSuppressedOutput();
        if (Files.exists(Path.of(".setup-stage"))) {
          commands.performPrefixedCommand(source, "function flame:demo");
          try {
            Files.delete(Path.of(".setup-stage"));
          } catch (Exception e) {
            throw new RuntimeException(e);
          }
        } else {
          commands.performPrefixedCommand(source,
                                          "scoreboard players set #mode flame 1");
          commands.performPrefixedCommand(source, "function flame:rescan");
        }
        commands.performPrefixedCommand(source, "tp " + player.getStringUUID() +
                                                    " 8 70 22 180 25");
        client.execute(() -> {
          client.options.bobView().set(false);
          client.options.pauseOnLostFocus = false;
          client.options.inactivityFpsLimit().set(
              net.minecraft.client.InactivityFpsLimit.MINIMIZED);
          client.getWindow().setTitle("Flame Playground · Minecraft 26.3");
          client.player.sendSystemMessage(
              Component.translatable("message.flame_play.controls"));
          ready = true;
          status(client, "ready");
        });
      });
    }
    if (!ready || client.gui.screen() != null)
      return;
    while (ignite.consumeClick()) {
      send(client, "trigger flame.action set 1");
    }
    while (quench.consumeClick()) {
      send(client, "trigger flame.action set 2");
    }
    while (rescan.consumeClick())
      send(client, "trigger flame.action set 3");
    while (stage.consumeClick())
      rebuild(client);
    if (Boolean.getBoolean("flame.play.smoke")) {
      smokeClock++;
      if (smokeStage == 0 && smokeClock >= 45) {
        send(client, "trigger flame.action set 2");
        nextSmoke();
      } else if (smokeStage == 1 && smokeClock >= 15 && !smokePending)
        verifyMode(client, 2, false);
      else if (smokeStage == 2) {
        send(client, "tp @s 3.5 68 8.5 0 90");
        nextSmoke();
      } else if (smokeStage == 3 && smokeClock >= 20) {
        send(client, "trigger flame.action set 1");
        nextSmoke();
      } else if (smokeStage == 4 && smokeClock >= 20 && !smokePending)
        verifyMode(client, 1, false);
      else if (smokeStage == 5) {
        send(client, "trigger flame.action set 3");
        nextSmoke();
      } else if (smokeStage == 6 && smokeClock >= 25 && !smokePending)
        verifyMode(client, 1, true);
      else if (smokeStage == 7) {
        status(client, "passed");
        client.stop();
      }
    }
  }
  private void send(Minecraft client, String command) {
    client.player.connection.sendCommand(command);
    status(client, "ready");
  }
  private void rebuild(Minecraft client) {
    var server = client.getSingleplayerServer();
    server.execute(()
                       -> server.getCommands().performPrefixedCommand(
                           server.createCommandSourceStack().withSuppressedOutput(),
                           "function flame:demo"));
    status(client, "ready");
  }
  private void nextSmoke() {
    smokeStage++;
    smokeClock = 0;
    smokeAttempts = 0;
  }
  private void verifyMode(Minecraft client, int mode, boolean freshEpoch) {
    smokePending = true;
    client.getSingleplayerServer().execute(() -> {
      var server = client.getSingleplayerServer();
      var colors = server.getCommandStorage()
                       .get(Identifier.parse("flame:tx"))
                       .getListOrEmpty("colors");
      int actual =
          colors.size() > 4 ? (colors.get(4).asInt().orElseThrow() >> 15) & 3 : -1;
      int epoch = colors.isEmpty() ? 0 : colors.get(0).asInt().orElseThrow();
      var objective = server.getScoreboard().getObjective("flame");
      var readyScore = objective == null
                           ? null
                           : server.getScoreboard().getPlayerScoreInfo(
                                 ScoreHolder.forNameOnly("#ready"), objective);
      boolean complete = readyScore != null && readyScore.value() == 1;
      client.execute(() -> {
        smokePending = false;
        if (actual == mode && complete && (!freshEpoch || epoch != lastEpoch)) {
          verifiedModes.add(actual);
          lastEpoch = epoch;
          nextSmoke();
        } else if (++smokeAttempts >= 12) {
          failure = "Expected mode " + mode + ", payload mode " + actual + ", ready " +
                    complete + ", epoch " + epoch + ", previous epoch " + lastEpoch;
          smokeStage = 99;
          status(client, "failed");
          client.stop();
        } else
          smokeClock = 0;
      });
    });
  }
  private void status(Minecraft client, String state) {
    try {
      Files.writeString(
          Path.of("flame-play-status.json"),
          new GsonBuilder().setPrettyPrinting().create().toJson(Map.of(
              "status", state, "nativeInput",
              System.getProperty("fabric.client.gametest") == null, "resourcePacks",
              client.getResourcePackRepository().getSelectedIds(), "smokeStage",
              smokeStage, "verifiedModes", verifiedModes, "epoch", lastEpoch, "failure",
              failure)));
    } catch (Exception e) {
      throw new RuntimeException(e);
    }
  }
}
