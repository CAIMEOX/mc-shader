package dev.caimeo.manifold.mixin;

import dev.caimeo.manifold.RuntimeMetrics;
import net.minecraft.client.Minecraft;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.Unique;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

@Mixin(Minecraft.class)
public class MinecraftFrames {
  @Unique private long manifold$frameStart;

  @Inject(method = "renderFrame", at = @At("HEAD"))
  private void manifold$beginFrame(boolean tick, CallbackInfo ci) {
    manifold$frameStart = System.nanoTime();
  }

  @Inject(method = "renderFrame", at = @At("RETURN"))
  private void manifold$endFrame(boolean tick, CallbackInfo ci) {
    RuntimeMetrics.recordFrame(System.nanoTime() - manifold$frameStart);
  }
}
