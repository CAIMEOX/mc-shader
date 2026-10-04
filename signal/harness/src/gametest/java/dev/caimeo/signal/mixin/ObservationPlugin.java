package dev.caimeo.signal.mixin;

import java.util.List;
import java.util.Set;
import org.objectweb.asm.tree.ClassNode;
import org.spongepowered.asm.mixin.extensibility.IMixinConfigPlugin;
import org.spongepowered.asm.mixin.extensibility.IMixinInfo;

/** Selects the observers for a run before Minecraft classes are transformed. */
public final class ObservationPlugin implements IMixinConfigPlugin {
  @Override
  public void onLoad(String mixinPackage) {}
  @Override
  public String getRefMapperConfig() {
    return null;
  }
  @Override
  public boolean shouldApplyMixin(String target, String mixin) {
    return !Boolean.getBoolean("signal.stopwatchOnly") ||
        !mixin.endsWith("Observation");
  }
  @Override
  public void acceptTargets(Set<String> mine, Set<String> others) {}
  @Override
  public List<String> getMixins() {
    return null;
  }
  @Override
  public void preApply(String target, ClassNode node, String mixin, IMixinInfo info) {}
  @Override
  public void postApply(String target, ClassNode node, String mixin, IMixinInfo info) {}
}
