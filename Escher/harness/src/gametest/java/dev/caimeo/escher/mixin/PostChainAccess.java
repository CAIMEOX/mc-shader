package dev.caimeo.escher.mixin;

import com.mojang.blaze3d.pipeline.RenderTarget;
import net.minecraft.client.renderer.PostChain;
import net.minecraft.resources.Identifier;
import org.spongepowered.asm.mixin.Mixin;
import org.spongepowered.asm.mixin.gen.Accessor;
import java.util.Map;

@Mixin(PostChain.class)
public interface PostChainAccess {
  @Accessor("persistentTargets")
  Map<Identifier, RenderTarget> escher$persistentTargets();
}
