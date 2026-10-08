package dev.caimeo.backrooms.play;

import com.google.gson.GsonBuilder;
import com.mojang.blaze3d.platform.InputConstants;
import net.fabricmc.api.ClientModInitializer;
import net.fabricmc.fabric.api.client.event.lifecycle.v1.ClientTickEvents;
import net.fabricmc.fabric.api.client.keymapping.v1.KeyMappingHelper;
import net.minecraft.client.KeyMapping;
import net.minecraft.client.Minecraft;
import net.minecraft.network.chat.Component;
import net.minecraft.resources.Identifier;
import net.minecraft.world.level.Level;
import net.minecraft.world.scores.ScoreHolder;
import java.nio.file.*;
import java.util.*;

public final class BackroomsPlayClient implements ClientModInitializer {
  private Object session;
  private int ticks, stage, clock;
  private boolean started, ready, pending;
  private KeyMapping exit, home;
  private final List<String> verified = new ArrayList<>();

  @Override
  public void onInitializeClient() {
    if (!Boolean.getBoolean("backrooms.play"))
      return;
    var category =
        KeyMapping.Category.register(Identifier.parse("backrooms_play:controls"));
    exit = KeyMappingHelper.registerKeyMapping(
        new KeyMapping("key.backrooms_play.exit", InputConstants.KEY_X, category));
    home = KeyMappingHelper.registerKeyMapping(
        new KeyMapping("key.backrooms_play.home", InputConstants.KEY_F7, category));
    ClientTickEvents.END_CLIENT_TICK.register(this::tick);
  }

  private void tick(Minecraft client) {
    if (client.gui.screen() instanceof
        net.minecraft.client.gui.screens.BackupConfirmScreen backup) {
      for (var child : backup.children())
        if (child instanceof net.minecraft.client.gui.components.Button button &&
            button.getMessage().equals(
                net.minecraft.client.gui.screens.BackupConfirmScreen.BACKUP_AND_JOIN)) {
          button.onPress(
              new net.minecraft.client.input.KeyEvent(InputConstants.KEY_RETURN, 0, 0));
          return;
        }
    }
    var server = client.getSingleplayerServer();
    if (server == null || client.player == null) {
      if (ticks++ % 40 == 0)
        status("loading", client.gui.screen() == null
                              ? "no screen"
                              : client.gui.screen().getClass().getName() + " " +
                                    client.gui.screen().getTitle().getString());
      session = null;
      started = false;
      ready = false;
      return;
    }
    if (session != server) {
      session = server;
      started = false;
      ready = false;
      ticks = 0;
      stage = 0;
      clock = 0;
      verified.clear();
    }
    ticks++;
    if (Boolean.getBoolean("backrooms.play.smoke") &&
        client.player.input.getClass() != net.minecraft.client.player.ClientInput.class)
      client.player.input = new net.minecraft.client.player.ClientInput();
    if (!started && ticks >= 30) {
      started = true;
      var id = client.player.getUUID();
      server.execute(() -> {
        server.setWorldAllowCommands(true);
        var player = server.getPlayerList().getPlayer(id);
        if (player != null)
          server.getCommands().performPrefixedCommand(
              player.createCommandSourceStack().withSuppressedOutput(),
              "function backrooms:enter");
      });
      client.options.bobView().set(false);
      client.options.renderDistance().set(5);
      client.options.pauseOnLostFocus = false;
      client.options.inactivityFpsLimit().set(
          net.minecraft.client.InactivityFpsLimit.MINIMIZED);
      client.getWindow().setTitle("Backrooms · Minecraft 26.3");
      status("preparing", "");
    }
    if (!ready && started && !pending && ticks % 5 == 0) {
      pending = true;
      server.execute(() -> {
        var objective = server.getScoreboard().getObjective("backrooms");
        var active = objective == null
                         ? null
                         : server.getScoreboard().getPlayerScoreInfo(
                               ScoreHolder.forNameOnly("#lobby"), objective);
        boolean complete = active != null && active.value() == 1;
        client.execute(() -> {
          pending = false;
          if (complete) {
            ready = true;
            client.player.sendSystemMessage(
                Component.literal("后室 Level 0：WASD 行走 · F7 入口 · X 离开"));
            status("ready", "");
          }
        });
      });
    }
    if (!ready || client.gui.screen() != null)
      return;
    while (exit.consumeClick())
      send(client, "trigger backrooms.action set 2");
    while (home.consumeClick())
      send(client, "trigger backrooms.action set 3");
    if (Boolean.getBoolean("backrooms.play.smoke")) {
      clock++;
      if (stage == 0 && clock > 40 && !pending)
        verify(client, "entry");
      else if (stage == 1) {
        KeyMapping.click(home.getDefaultKey());
        advance();
      } else if (stage == 2 && clock > 20 && !pending)
        verify(client, "home");
      else if (stage == 3) {
        KeyMapping.click(exit.getDefaultKey());
        advance();
      } else if (stage == 4 && clock > 20 && !pending)
        verify(client, "exit");
      else if (stage == 5) {
        status("passed", "");
        client.stop();
      }
    }
  }

  private void verify(Minecraft client, String action) {
    pending = true;
    client.getSingleplayerServer().execute(() -> {
      var server = client.getSingleplayerServer();
      var player = server.getPlayerList().getPlayer(client.player.getUUID());
      var diagnostic = " position=" + player.position() +
                       " velocity=" + player.getDeltaMovement() + " neighbors=" +
                       player.level()
                           .getEntities(player, player.getBoundingBox().inflate(2.0))
                           .stream()
                           .map(e -> e.getType().toString())
                           .toList();
      boolean ok = action.equals("entry")
                       ? player.level().dimension().identifier().toString().equals(
                             "backrooms:interior")
                   : action.equals("home")
                       ? Math.abs(player.getX() - 0.5) < 0.001 &&
                             Math.abs(player.getZ() - 0.5) < 0.001
                       : player.level().dimension().equals(Level.OVERWORLD);
      client.execute(() -> {
        pending = false;
        if (ok) {
          verified.add(action);
          advance();
        } else {
          status("failed",
                 "Control did not reach its expected state: " + action + diagnostic);
          client.stop();
        }
      });
    });
  }
  private void advance() {
    stage++;
    clock = 0;
  }
  private void send(Minecraft client, String command) {
    client.player.connection.sendCommand(command);
  }
  private void status(String state, String failure) {
    try {
      Files.writeString(
          Path.of("backrooms-play-status.json"),
          new GsonBuilder().setPrettyPrinting().create().toJson(
              Map.of("status", state, "controlTransport", "client command packets",
                     "verifiedControls", verified, "failure", failure)));
    } catch (Exception error) {
      throw new RuntimeException(error);
    }
  }
}
