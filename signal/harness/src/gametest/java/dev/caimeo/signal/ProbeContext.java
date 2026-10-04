package dev.caimeo.signal;

import java.util.concurrent.CompletableFuture;
import java.util.concurrent.TimeUnit;
import java.util.function.Function;
import net.minecraft.client.Minecraft;
import net.minecraft.client.Screenshot;
import net.minecraft.server.MinecraftServer;

/** Runs orchestration on a worker, with tasks submitted to native event loops. */
public final class ProbeContext {
  private final Minecraft minecraft;
  public ProbeContext(Minecraft minecraft) {
    this.minecraft = minecraft;
  }

  public <T> T computeOnClient(Function<Minecraft, T> action) {
    var result = new CompletableFuture<T>();
    minecraft.execute(() -> {
      try {
        result.complete(action.apply(minecraft));
      } catch (Throwable error) {
        result.completeExceptionally(error);
      }
    });
    return result.orTimeout(20, TimeUnit.SECONDS).join();
  }

  public void sleep(long milliseconds) {
    try {
      Thread.sleep(milliseconds);
    } catch (InterruptedException e) {
      Thread.currentThread().interrupt();
      throw new RuntimeException(e);
    }
  }

  public void takeScreenshot(String name) {
    var saved = new CompletableFuture<Void>();
    computeOnClient(mc -> {
      Screenshot.grab(mc.gameDirectory, name + ".png",
                      mc.gameRenderer.mainRenderTarget(), 1,
                      message -> saved.complete(null));
      return null;
    });
    saved.orTimeout(20, TimeUnit.SECONDS).join();
  }

  public ServerAccess server() {
    return new ServerAccess(minecraft.getSingleplayerServer());
  }

  public static final class ServerAccess {
    private final MinecraftServer server;
    ServerAccess(MinecraftServer server) {
      this.server = server;
    }

    public <T> T computeOnServer(Function<MinecraftServer, T> action) {
      var result = new CompletableFuture<T>();
      server.execute(() -> {
        try {
          result.complete(action.apply(server));
        } catch (Throwable error) {
          result.completeExceptionally(error);
        }
      });
      return result.orTimeout(20, TimeUnit.SECONDS).join();
    }

    public void runCommand(String command) {
      computeOnServer(s -> {
        s.getCommands().performPrefixedCommand(
            s.createCommandSourceStack().withSuppressedOutput(), command);
        return null;
      });
    }
  }
}
