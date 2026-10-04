package dev.caimeo.signal.mixin;

import dev.caimeo.signal.PingPongExperiment;
import net.minecraft.client.multiplayer.ClientPacketListener;
import net.minecraft.network.protocol.game.ClientboundSystemChatPacket;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

@Mixin(ClientPacketListener.class)
public abstract class PingChatCapture {
  @Inject(method = "handleSystemChat", at = @At("TAIL"))
  private void signal$chat(ClientboundSystemChatPacket packet, CallbackInfo callback) {
    PingPongExperiment.capture(packet.content());
  }
}
