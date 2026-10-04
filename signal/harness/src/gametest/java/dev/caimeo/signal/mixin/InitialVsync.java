package dev.caimeo.signal.mixin;
import org.lwjgl.sdl.SDLVideo;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.Unique;
import org.spongepowered.asm.mixin.injection.At;
import org.spongepowered.asm.mixin.injection.Inject;
import org.spongepowered.asm.mixin.injection.callback.CallbackInfo;

@Mixin(targets = "com.mojang.renderpearl.backend.opengl.GlSurface", remap = false)
public abstract class InitialVsync {
  @Unique private boolean signal$intervalSet;
  @Inject(method = "present", at = @At("HEAD"), remap = false)
  private void signal$initialSwapInterval(CallbackInfo ci) {
    if (!signal$intervalSet) {
      SDLVideo.SDL_GL_SetSwapInterval(0);
      signal$intervalSet = true;
    }
  }
}
