package dev.caimeo.signal.play;

import com.google.gson.GsonBuilder;
import com.mojang.blaze3d.platform.InputConstants;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import net.fabricmc.api.ClientModInitializer;
import net.fabricmc.fabric.api.client.event.lifecycle.v1.ClientTickEvents;
import net.fabricmc.fabric.api.client.keymapping.v1.KeyMappingHelper;
import net.minecraft.client.KeyMapping;
import net.minecraft.client.Minecraft;
import net.minecraft.network.chat.Component;
import net.minecraft.resources.Identifier;
import net.minecraft.world.level.GameType;

/** Interactive shortcuts for the ordinary data-pack receiver. */
public final class SignalPlayClient implements ClientModInitializer {
  private Object serverIdentity;
  private int ticks;
  private boolean preparing;
  private boolean ready;
  private KeyMapping receive;
  private KeyMapping cancel;
  private int smokeStage;
  private int smokeClock;
  private boolean smokePending;
  private final List<String> checks = new ArrayList<>();
  private Map<String, Object> snapshot = Map.of();

  @Override
  public void onInitializeClient() {
    if (!Boolean.getBoolean("signal.play"))
      return;
    var category =
        KeyMapping.Category.register(Identifier.parse("signal_play:controls"));
    receive = KeyMappingHelper.registerKeyMapping(
        new KeyMapping("key.signal_play.receive", InputConstants.KEY_R, category));
    cancel = KeyMappingHelper.registerKeyMapping(
        new KeyMapping("key.signal_play.cancel", InputConstants.KEY_X, category));
    ClientTickEvents.END_CLIENT_TICK.register(this::tick);
  }

  private void tick(Minecraft client) {
    var server = client.getSingleplayerServer();
    if (server == null || client.player == null) {
      serverIdentity = null;
      return;
    }
    if (serverIdentity != server) {
      serverIdentity = server;
      ticks = 0;
      preparing = ready = smokePending = false;
      smokeStage = smokeClock = 0;
      checks.clear();
    }
    ticks++;
    if (!ready && !preparing && ticks >= 30 && client.gui.overlay() == null &&
        client.gui.screen() == null) {
      preparing = true;
      prepare(client);
    }
    if (!ready || client.gui.screen() != null)
      return;
    while (receive.consumeClick())
      client.player.connection.sendCommand("trigger signal.ping");
    while (cancel.consumeClick())
      client.player.connection.sendCommand("function signal:ping/cancel");
    if (Boolean.getBoolean("signal.play.smoke"))
      smoke(client);
  }

  private void prepare(Minecraft client) {
    var server = client.getSingleplayerServer();
    var id = client.player.getUUID();
    server.execute(() -> {
      try {
        var player = server.getPlayerList().getPlayer(id);
        if (player == null)
          throw new IllegalStateException("Player has not joined");
        server.setWorldAllowCommands(true);
        server.getPlayerList().op(player.nameAndId());
        server.getPlayerList().sendPlayerPermissionLevel(player);
        server.getCommands().sendCommands(player);
        var commands = server.getCommands();
        var source = server.createCommandSourceStack().withSuppressedOutput();
        commands.performPrefixedCommand(source, "function signal:ping/cancel");
        commands.performPrefixedCommand(
            source, "posteffect remove " + player.getStringUUID() + " signal:ping");
        commands.performPrefixedCommand(source, "kill @e[tag=signal.carrier]");
        commands.performPrefixedCommand(source, "tick rate 200");
        if (Files.exists(Path.of(".setup-signal-play"))) {
          commands.performPrefixedCommand(
              source, "fill -16 63 -16 16 63 16 minecraft:polished_andesite strict");
          commands.performPrefixedCommand(
              source, "fill -16 64 -16 16 67 16 minecraft:air strict");
          commands.performPrefixedCommand(source, "difficulty peaceful");
          commands.performPrefixedCommand(source, "time set noon");
          commands.performPrefixedCommand(source, "weather clear");
          player.setGameMode(GameType.CREATIVE);
          player.getAbilities().flying = false;
          player.onUpdateAbilities();
          commands.performPrefixedCommand(source, "tp " + player.getStringUUID() +
                                                      " 0.5 64 0.5 -90 0");
          Files.delete(Path.of(".setup-signal-play"));
        }
        client.execute(() -> {
          client.options.enableVsync().set(false);
          client.options.bobView().set(false);
          client.options.framerateLimit().set(120);
          client.options.pauseOnLostFocus = false;
          client.options.inactivityFpsLimit().set(
              net.minecraft.client.InactivityFpsLimit.MINIMIZED);
          client.getWindow().setTitle("Signal Playground · Minecraft 26.3");
          client.player.sendSystemMessage(
              Component.translatable("message.signal_play.controls"));
          ready = true;
          status(client, "ready", "");
        });
      } catch (Throwable error) {
        client.execute(() -> fail(client, error.toString()));
      }
    });
  }

  private void smoke(Minecraft client) {
    if (++smokeClock > 900) {
      fail(client, "Interactive check timed out at stage " + smokeStage);
      return;
    }
    if (smokeStage == 0 && smokeClock >= 20) {
      client.player.connection.sendCommand("tick rate 199");
      nextSmoke();
    } else if (smokeStage >= 1 && smokeStage <= 4 && smokeClock >= 5 && !smokePending) {
      smokePending = true;
      int expectedStage = smokeStage;
      var server = client.getSingleplayerServer();
      var id = client.player.getUUID();
      server.execute(() -> {
        var player = server.getPlayerList().getPlayer(id);
        var data = server.getCommandStorage().get(Identifier.parse("signal:ping"));
        var values = new LinkedHashMap<String, Object>();
        values.put("tick_rate", server.tickRateManager().tickrate());
        values.put("status", data.getStringOr("status", ""));
        values.put("bits", data.getListOrEmpty("bits").size());
        values.put("posteffect",
                   player != null && player.getPostEffects().contains(
                                         Identifier.parse("signal:ping")));
        values.put("operator",
                   player != null && server.getPlayerList().isOp(player.nameAndId()));
        client.execute(() -> {
          smokePending = false;
          snapshot = values;
          if (smokeStage != expectedStage)
            return;
          float rate = ((Number)values.get("tick_rate")).floatValue();
          if (smokeStage == 1 && rate == 199 &&
              Boolean.TRUE.equals(values.get("operator"))) {
            checks.add("operator_tick_command");
            client.player.connection.sendCommand("tick rate 200");
            nextSmoke();
          } else if (smokeStage == 2 && rate == 200) {
            checks.add("tick_rate_200");
            KeyMapping.click(receive.getDefaultKey());
            nextSmoke();
          } else if (smokeStage == 3 && values.get("status").equals("receiving") &&
                     ((Number)values.get("bits")).intValue() > 0 &&
                     Boolean.TRUE.equals(values.get("posteffect"))) {
            checks.add("receive_key_and_data_pack_bit");
            KeyMapping.click(cancel.getDefaultKey());
            nextSmoke();
          } else if (smokeStage == 4 && values.get("status").equals("cancelled") &&
                     Boolean.FALSE.equals(values.get("posteffect"))) {
            checks.add("cancel_key_and_effect_cleanup");
            status(client, "passed", "");
            client.stop();
          } else if (values.get("status").equals("error")) {
            fail(client, "Data-pack receiver reported an error");
          }
        });
      });
    }
  }

  private void nextSmoke() {
    smokeStage++;
    smokeClock = 0;
  }

  private void fail(Minecraft client, String message) {
    ready = false;
    status(client, "failed", message);
    if (client.player != null)
      client.player.sendSystemMessage(Component.literal("Signal: " + message));
    if (Boolean.getBoolean("signal.play.smoke"))
      client.stop();
  }

  private void status(Minecraft client, String state, String failure) {
    try {
      Files.writeString(Path.of("signal-play-status.json"),
                        new GsonBuilder().setPrettyPrinting().create().toJson(
                            Map.of("status", state, "failure", failure, "native_input",
                                   System.getProperty("fabric.client.gametest") == null,
                                   "resource_packs",
                                   client.getResourcePackRepository().getSelectedIds(),
                                   "checks", List.copyOf(checks), "snapshot", snapshot,
                                   "world", "Signal Playground")));
    } catch (Exception error) {
      throw new RuntimeException(error);
    }
  }
}
