package dev.caimeo.manifold.mixin;

import dev.caimeo.manifold.MessageCapture;
import net.minecraft.client.multiplayer.ClientPacketListener;
import net.minecraft.network.protocol.game.*;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

@Mixin(ClientPacketListener.class)
public class ClientMessages {
  @Inject(method = "setTitleText", at = @At("TAIL"))
  private void manifold$title(ClientboundSetTitleTextPacket packet, CallbackInfo ci) {
    MessageCapture.record("title", packet.text());
  }
  @Inject(method = "setSubtitleText", at = @At("TAIL"))
  private void manifold$subtitle(ClientboundSetSubtitleTextPacket packet,
                                 CallbackInfo ci) {
    MessageCapture.record("subtitle", packet.text());
  }
  @Inject(method = "setActionBarText", at = @At("TAIL"))
  private void manifold$actionbar(ClientboundSetActionBarTextPacket packet,
                                  CallbackInfo ci) {
    MessageCapture.record("actionbar", packet.text());
  }
  @Inject(method = "handleSystemChat", at = @At("TAIL"))
  private void manifold$chat(ClientboundSystemChatPacket packet, CallbackInfo ci) {
    MessageCapture.record(packet.overlay() ? "actionbar" : "chat", packet.content());
  }
}
