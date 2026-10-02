package dev.caimeo.qwen.mixin;
import org.lwjgl.sdl.SDLVideo;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.Unique;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

@Mixin(targets = "com.mojang.renderpearl.backend.opengl.GlSurface", remap = false)
public abstract class InitialVsync {
  @Unique private boolean qwen$intervalSet;
  @Inject(method = "present", at = @At("HEAD"), remap = false)
  private void qwen$initialSwapInterval(CallbackInfo ci) {
    if (!qwen$intervalSet) {
      SDLVideo.SDL_GL_SetSwapInterval(0);
      qwen$intervalSet = true;
    }
  }
}
