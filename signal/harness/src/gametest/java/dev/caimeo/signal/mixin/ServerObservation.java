package dev.caimeo.signal.mixin;

import dev.caimeo.signal.Observation;
import net.minecraft.server.network.ServerGamePacketListenerImpl;
import net.minecraft.network.protocol.game.ServerboundClientTickEndPacket;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

@Mixin(ServerGamePacketListenerImpl.class)
public abstract class ServerObservation {
  @Inject(method = "handleClientTickEnd", at = @At("TAIL"))
  private void signal$handled(ServerboundClientTickEndPacket packet, CallbackInfo ci) {
    Observation.record(Observation.Stream.HANDLED);
  }
}
