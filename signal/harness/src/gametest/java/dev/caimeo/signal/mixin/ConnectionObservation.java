package dev.caimeo.signal.mixin;

import dev.caimeo.signal.Observation;
import io.netty.channel.ChannelHandlerContext;
import net.minecraft.network.Connection;
import net.minecraft.network.protocol.Packet;
import net.minecraft.network.protocol.game.ServerboundClientTickEndPacket;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

@Mixin(Connection.class)
public abstract class ConnectionObservation {
  @Inject(
      method =
          "channelRead0(Lio/netty/channel/ChannelHandlerContext;Lnet/minecraft/network/protocol/Packet;)V",
      at = @At("HEAD"))
  private void
  signal$arrived(ChannelHandlerContext ctx, Packet<?> packet, CallbackInfo ci) {
    if (packet instanceof ServerboundClientTickEndPacket)
      Observation.record(Observation.Stream.ARRIVED);
  }
}
