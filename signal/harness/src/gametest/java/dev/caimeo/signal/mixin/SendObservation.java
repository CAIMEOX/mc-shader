package dev.caimeo.signal.mixin;

import dev.caimeo.signal.Observation;
import net.minecraft.client.multiplayer.ClientCommonPacketListenerImpl;
import net.minecraft.network.protocol.Packet;
import net.minecraft.network.protocol.game.ServerboundClientTickEndPacket;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

@Mixin(ClientCommonPacketListenerImpl.class)
public abstract class SendObservation {
  @Inject(method = "send", at = @At("HEAD"))
  private void signal$sent(Packet<?> packet, CallbackInfo ci) {
    if (packet instanceof ServerboundClientTickEndPacket)
      Observation.record(Observation.Stream.SENT);
  }
}
