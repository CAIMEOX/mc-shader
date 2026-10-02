package dev.caimeo.qwen.play;
import com.mojang.blaze3d.platform.InputConstants;
import net.fabricmc.api.ClientModInitializer;
import net.fabricmc.fabric.api.client.event.lifecycle.v1.ClientTickEvents;
import net.fabricmc.fabric.api.client.keymapping.v1.KeyMappingHelper;
import net.minecraft.client.KeyMapping;
import net.minecraft.network.chat.Component;
import net.minecraft.resources.Identifier;

public final class QwenPlayClient implements ClientModInitializer {
  private Object identity;
  private int ticks;
  private KeyMapping submit;
  @Override
  public void onInitializeClient() {
    var category = KeyMapping.Category.register(Identifier.parse("qwen_play:controls"));
    submit = KeyMappingHelper.registerKeyMapping(
        new KeyMapping("Qwen: submit NBT prompt", InputConstants.KEY_R, category));
    ClientTickEvents.END_CLIENT_TICK.register(client -> {
      var server = client.getSingleplayerServer();
      if (server == null || client.player == null)
        return;
      if (identity != server) {
        identity = server;
        ticks = 0;
      }
      if (++ticks == 30) {
        server.execute(() -> {
          server.setWorldAllowCommands(true);
          server.getCommands().performPrefixedCommand(
              server.createCommandSourceStack().withSuppressedOutput(),
              "data modify storage qwen:input max_tokens set value 256");
          if (java.nio.file.Files.exists(java.nio.file.Path.of(".setup"))) {
            var commands = server.getCommands();
            var source = server.createCommandSourceStack().withSuppressedOutput();
            commands.performPrefixedCommand(source, "kill @e[tag=qwen.carrier]");
            commands.performPrefixedCommand(
                source, "data modify storage qwen:input prompt set value \"What is 2 "
                            + "+ 2? Answer briefly.\"");
            try {
              java.nio.file.Files.delete(java.nio.file.Path.of(".setup"));
            } catch (Exception e) {
              throw new RuntimeException(e);
            }
          }
        });
        client.options.enableVsync().set(false);
        client.options.pauseOnLostFocus = false;
        client.options.inactivityFpsLimit().set(
            net.minecraft.client.InactivityFpsLimit.MINIMIZED);
        client.getWindow().setTitle("Qwen3 · Shader Playground");
        client.player.sendSystemMessage(
            Component.literal("Qwen: R 提交 qwen:input 的 prompt；/data modify "
                              + "storage qwen:input prompt set value \"你的问题\""));
      }
      if (client.gui.screen() == null)
        while (submit.consumeClick())
          client.player.connection.sendCommand("trigger qwen.action set 1");
    });
  }
}
