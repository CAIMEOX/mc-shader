package dev.caimeo.escher.play;

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
import net.minecraft.world.scores.ScoreHolder;
import java.nio.file.*;
import java.util.*;

public final class EscherPlayClient implements ClientModInitializer {
  private Object serverIdentity;
  private int ticks, stage, clock;
  private int initialEnabled, initialTurn, initialQuality;
  private int initialScene, initialFolding, initialAnimate, initialRolling,
      initialOverview;
  private boolean preparing, ready, pending;
  private KeyMapping twist, toggle, rebuild, home;
  private final List<Integer> verified = new ArrayList<>();
  @Override
  public void onInitializeClient() {
    if (!Boolean.getBoolean("escher.play"))
      return;
    var category =
        KeyMapping.Category.register(Identifier.parse("escher_play:controls"));
    twist = KeyMappingHelper.registerKeyMapping(
        new KeyMapping("key.escher_play.twist", InputConstants.KEY_R, category));
    toggle = KeyMappingHelper.registerKeyMapping(
        new KeyMapping("key.escher_play.toggle", InputConstants.KEY_X, category));
    rebuild = KeyMappingHelper.registerKeyMapping(
        new KeyMapping("key.escher_play.rebuild", InputConstants.KEY_F6, category));
    home = KeyMappingHelper.registerKeyMapping(
        new KeyMapping("key.escher_play.home", InputConstants.KEY_F7, category));
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
      stage = 0;
      clock = 0;
      verified.clear();
    }
    ticks++;
    if (!ready && !preparing && ticks >= 25) {
      preparing = true;
      var id = client.player.getUUID();
      server.execute(() -> {
        var player = server.getPlayerList().getPlayer(id);
        if (player == null)
          return;
        server.setWorldAllowCommands(true);
        player.setGameMode(GameType.ADVENTURE);
        var commands = server.getCommands();
        var source = server.createCommandSourceStack().withSuppressedOutput();
        if (Files.exists(Path.of(".setup-stage"))) {
          commands.performPrefixedCommand(source, "function escher:demo");
          try {
            Files.delete(Path.of(".setup-stage"));
          } catch (Exception e) {
            throw new RuntimeException(e);
          }
        } else
          commands.performPrefixedCommand(
              source, "execute positioned 0 70 0 run function escher:start");
        String scene = System.getProperty("escher.play.scene", "");
        if (List.of("gallery", "folding").contains(scene))
          commands.performPrefixedCommand(source, "function escher:scene/" + scene);
        var selection =
            server.getCommandStorage().get(Identifier.parse("escher:control"));
        boolean overview = selection.getIntOr("scene", 0) == 1 &&
                           selection.getIntOr("overview", 0) == 1;
        player.setGameMode(overview ? GameType.SPECTATOR : GameType.ADVENTURE);
        commands.performPrefixedCommand(
            source, "tp " + player.getStringUUID() +
                        (overview ? " 0 65 22 0 10" : " 0 65 2 0 0"));
        commands.performPrefixedCommand(source, "spawnpoint " + player.getStringUUID() +
                                                    " 0 65 2 0");
        client.execute(() -> {
          client.options.bobView().set(false);
          client.options.renderDistance().set(5);
          client.options.pauseOnLostFocus = false;
          client.options.inactivityFpsLimit().set(
              net.minecraft.client.InactivityFpsLimit.MINIMIZED);
          client.getWindow().setTitle("Escher Gallery · Minecraft 26.3");
          client.player.sendSystemMessage(Component.literal(
              "Escher: R 形态变化 · X 碰撞场景 · /function escher:scene/folding 切换场景"));
          status("preparing", "");
        });
      });
    }
    if (preparing && !ready && !pending && ticks % 5 == 0) {
      pending = true;
      server.execute(() -> {
        var objective = server.getScoreboard().getObjective("escher");
        var value = objective == null
                        ? null
                        : server.getScoreboard().getPlayerScoreInfo(
                              ScoreHolder.forNameOnly("#ready"), objective);
        boolean complete = value != null && value.value() == 1;
        var control =
            server.getCommandStorage().get(Identifier.parse("escher:control"));
        int enabled = control.getIntOr("enabled", 1),
            turn = control.getIntOr("turn", 399),
            quality = control.getIntOr("quality", 2),
            scene = control.getIntOr("scene", 0),
            folding = control.getIntOr("folding", 1000),
            animate = control.getIntOr("animate", 1),
            rolling = control.getIntOr("rolling", 1),
            overview = control.getIntOr("overview", 0);
        client.execute(() -> {
          pending = false;
          if (complete) {
            initialEnabled = enabled;
            initialTurn = turn;
            initialQuality = quality;
            initialScene = scene;
            initialFolding = folding;
            initialAnimate = animate;
            initialRolling = rolling;
            initialOverview = overview;
            String requested = System.getProperty("escher.play.scene", "");
            if ((requested.equals("folding") && scene != 1) ||
                (requested.equals("gallery") && scene != 0)) {
              status("failed", "Requested scene was not initialized");
              client.stop();
              return;
            }
            client.getWindow().setTitle("Escher · " +
                                        (scene == 1 ? "Folding" : "Gallery"));
            ready = true;
            preparing = false;
            status("ready", "");
          }
        });
      });
    }
    if (!ready || client.gui.screen() != null)
      return;
    boolean smoke = Boolean.getBoolean("escher.play.smoke");
    while (twist.consumeClick())
      if (!smoke)
        send(client, "trigger escher.action set 1");
    while (toggle.consumeClick())
      if (!smoke)
        send(client, "trigger escher.action set 2");
    while (home.consumeClick())
      if (!smoke)
        send(client, "tp @s 0.0 65.0 2.0 0 0");
    while (rebuild.consumeClick())
      if (!smoke)
        send(client, "function escher:demo");
    if (smoke) {
      clock++;
      if (stage == 0 && clock > 45) {
        send(client, "trigger escher.action set 2");
        advance();
      } else if (stage == 1 && clock > 20 && !pending)
        verify(client, 0);
      else if (stage == 2) {
        send(client, "trigger escher.action set 2");
        advance();
      } else if (stage == 3 && clock > 20 && !pending)
        verify(client, 1);
      else if (stage == 4) {
        send(client, "trigger escher.action set 1");
        advance();
      } else if (stage == 5 && clock > 20 && !pending)
        verify(client, 2);
      else if (stage == 6) {
        send(client, "function escher:quality/low");
        advance();
      } else if (stage == 7 && clock > 20 && !pending)
        verify(client, 3);
      else if (stage == 8) {
        send(client, "function escher:quality/high");
        advance();
      } else if (stage == 9 && clock > 20 && !pending)
        verify(client, 4);
      else if (stage == 10) {
        send(client, "scoreboard players set #enabled escher " + initialEnabled);
        send(client, "scoreboard players set #turn escher " + initialTurn);
        send(client, "scoreboard players set #folding escher " + initialFolding);
        send(client, "scoreboard players set #animate escher " + initialAnimate);
        send(client, "scoreboard players set #rolling escher " + initialRolling);
        send(client, "scoreboard players set #overview escher " + initialOverview);
        send(client,
             "function escher:quality/" +
                 List.of("low", "balanced", "high", "native").get(initialQuality));
        send(client, "function escher:send");
        advance();
      } else if (stage == 11 && clock > 20) {
        status("passed", "");
        client.stop();
      }
    }
  }
  private void advance() {
    stage++;
    clock = 0;
  }
  private void send(Minecraft client, String command) {
    client.player.connection.sendCommand(command);
  }
  private void verify(Minecraft client, int expected) {
    pending = true;
    client.getSingleplayerServer().execute(() -> {
      var control = client.getSingleplayerServer().getCommandStorage().get(
          Identifier.parse("escher:control"));
      int enabled = control.getIntOr("enabled", -1),
          angle = control.getIntOr("turn", -1),
          quality = control.getIntOr("quality", -1),
          folding = control.getIntOr("folding", -1);
      client.execute(() -> {
        pending = false;
        int nextTurn = initialTurn + 200 >= 1200 ? 0 : initialTurn + 200;
        if ((expected == 0 && enabled == 1 - initialEnabled) ||
            (expected == 1 && enabled == initialEnabled) ||
            (expected == 2 &&
             (initialScene == 1 ? folding == (initialFolding > 0 ? 0 : 1000)
                                : angle == nextTurn)) ||
            (expected == 3 && quality == 0) || (expected == 4 && quality == 2)) {
          if (client.player.isSpectator() !=
              (initialScene == 1 && initialOverview == 1)) {
            status("failed", "The selected view needs its matching movement mode");
            stage = 99;
            client.stop();
            return;
          }
          verified.add(expected);
          advance();
        } else {
          status("failed", "Unexpected region parameters: enabled=" + enabled +
                               ", twist=" + angle + ", quality=" + quality);
          stage = 99;
          client.stop();
        }
      });
    });
  }
  private void status(String state, String failure) {
    try {
      Files.writeString(Path.of("escher-play-status.json"),
                        new GsonBuilder().setPrettyPrinting().create().toJson(Map.of(
                            "status", state, "nativeInput",
                            System.getProperty("fabric.client.gametest") == null,
                            "creative", Minecraft.getInstance().player.isCreative(),
                            "scene", initialScene == 1 ? "folding" : "gallery",
                            "verifiedControls", verified, "failure", failure)));
    } catch (Exception e) {
      throw new RuntimeException(e);
    }
  }
}
