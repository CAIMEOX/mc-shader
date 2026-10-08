package dev.caimeo.backrooms;

import com.mojang.blaze3d.systems.RenderSystem;
import dev.caimeo.backrooms.mixin.PostChainAccess;
import net.fabricmc.fabric.api.client.gametest.v1.context.ClientGameTestContext;
import net.minecraft.client.renderer.PostChain;
import net.minecraft.resources.Identifier;
import java.util.Set;
import java.util.List;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.concurrent.CompletableFuture;

final class GpuReadback {
  record Image(int width, int height, int[] rgba) {
    long word(int index) {
      return Integer.toUnsignedLong(rgba[index]);
    }
    double scalar(int index) {
      return Float.intBitsToFloat(rgba[index]);
    }
    int red(int index) {
      return rgba[index] >>> 24;
    }
  }
  static Image read(ClientGameTestContext context, String target) {
    var images = readBatch(context, "minecraft:end_of_frame", List.of(target));
    return images == null ? null : images.get(target);
  }
  static Map<String, Image> readBatch(ClientGameTestContext context, String effect,
                                      List<String> names) {
    var future = context.computeOnClient(mc -> {
      var result = new CompletableFuture<Map<String, Image>>();
      try {
        var chain = mc.getShaderManager().getPostChain(
            Identifier.parse(effect), Set.of(PostChain.MAIN_TARGET_ID));
        record Copy(String name, com.mojang.blaze3d.pipeline.RenderTarget target,
                    int offset) {}
        var copies = new ArrayList<Copy>();
        int length = 0;
        for (String name : names) {
          var target = ((PostChainAccess)chain)
                           .backrooms$persistentTargets()
                           .get(Identifier.withDefaultNamespace(name));
          if (target == null) {
            result.complete(null);
            return result;
          }
          copies.add(new Copy(name, target, length));
          length += target.width * target.height * 4;
        }
        var device = RenderSystem.getDevice();
        var buffer =
            device.createBuffer(() -> "Backrooms state observation", 9, length);
        Runnable complete = () -> {
          try (var mapped = buffer.map(true, false)) {
            var bytes = mapped.data();
            var images = new LinkedHashMap<String, Image>();
            for (var copy : copies) {
              int w = copy.target.width, h = copy.target.height;
              int[] values = new int[w * h];
              for (int i = 0; i < values.length; i++)
                for (int j = 0; j < 4; j++)
                  values[i] =
                      (values[i] << 8) | (bytes.get(copy.offset + i * 4 + j) & 255);
              images.put(copy.name, new Image(w, h, values));
            }
            result.complete(images);
          } catch (Throwable error) {
            result.completeExceptionally(error);
          } finally {
            buffer.close();
          }
        };
        for (int i = 0; i < copies.size(); i++) {
          var copy = copies.get(i);
          device.createCommandEncoder().copyTextureToBuffer(
              copy.target.getColorTexture(), buffer, copy.offset,
              i == copies.size() - 1 ? complete : () -> {}, 0);
        }
      } catch (Throwable error) {
        result.completeExceptionally(error);
      }
      return result;
    });
    context.waitFor(mc -> future.isDone(), 300);
    return future.join();
  }
}
