package dev.caimeo.signal.mixin;

import dev.caimeo.signal.Observation;
import net.minecraft.client.Minecraft;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

@Mixin(Minecraft.class)
public abstract class ClientObservation {
  @Inject(method = "runTick", at = @At("HEAD"))
  private void signal$frame(boolean render, CallbackInfo ci) {
    if (render)
      Observation.record(Observation.Stream.FRAME);
  }
}
