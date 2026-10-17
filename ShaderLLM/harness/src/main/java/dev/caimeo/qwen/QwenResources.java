package dev.caimeo.qwen;

import java.util.List;
import net.minecraft.client.Minecraft;
import net.minecraft.resources.Identifier;

public final class QwenResources {
  public static void requireLoaded(Minecraft client, boolean probes) {
    requireSelected(client, probes);
    for (String name : List.of(
             "qwen:font/wire.json", "minecraft:post_effect/end_of_frame.json",
             "minecraft:shaders/core/text.vsh", "minecraft:shaders/core/text.fsh")) {
      var resource = client.getResourceManager().getResource(Identifier.parse(name));
      if (resource.isEmpty() || !resource.get().sourcePackId().equals("file/qwen.zip"))
        throw new IllegalStateException(
            "Required Qwen resource is missing or overridden: " + name);
    }
  }

  public static void requireSelected(Minecraft client, boolean probes) {
    var selected = client.getResourcePackRepository().getSelectedIds();
    if (!selected.contains("file/qwen.zip") ||
        (probes && !selected.contains("file/qwen-probes.zip")))
      throw new IllegalStateException(
          "Required Qwen resource packs were disabled during reload: " + selected);
  }
}
