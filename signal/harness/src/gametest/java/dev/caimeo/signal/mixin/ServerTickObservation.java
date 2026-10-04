package dev.caimeo.signal.mixin;

import dev.caimeo.signal.Observation;
import net.minecraft.server.MinecraftServer;
import java.util.function.BooleanSupplier;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

@Mixin(MinecraftServer.class)
public abstract class ServerTickObservation {
  @Inject(method = "tickServer", at = @At("HEAD"))
  private void signal$tick(BooleanSupplier budget, CallbackInfo ci) {
    Observation.record(Observation.Stream.SERVER_TICK);
  }
}
