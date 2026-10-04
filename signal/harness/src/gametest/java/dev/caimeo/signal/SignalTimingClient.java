package dev.caimeo.signal;

import java.util.concurrent.CompletableFuture;
import net.fabricmc.api.ClientModInitializer;
import net.fabricmc.fabric.api.client.event.lifecycle.v1.ClientTickEvents;

public final class SignalTimingClient implements ClientModInitializer {
  private boolean started;
  private int readyTicks;
  @Override
  public void onInitializeClient() {
    if (!Boolean.getBoolean("signal.probe"))
      return;
    if (Boolean.getBoolean("signal.rotate") ||
        Boolean.getBoolean("signal.rotateStream")) {
      ClientTickEvents.START_CLIENT_TICK.register(RotateControls::startTick);
      ClientTickEvents.END_CLIENT_TICK.register(RotateControls::endTick);
    }
    ClientTickEvents.END_CLIENT_TICK.register(mc -> {
      if (!started && mc.player != null && mc.getSingleplayerServer() != null &&
          mc.gui.overlay() == null && mc.gui.screen() == null && ++readyTicks > 40) {
        started = true;
        CompletableFuture.runAsync(() -> {
          if (Boolean.getBoolean("signal.fall"))
            new FrameStreamExperiment(FrameStreamExperiment.Channel.FALL).run(mc);
          else if (Boolean.getBoolean("signal.rotateStream"))
            new FrameStreamExperiment(FrameStreamExperiment.Channel.ROTATION).run(mc);
          else if (Boolean.getBoolean("signal.pingpong"))
            new PingPongExperiment().run(mc);
          else if (Boolean.getBoolean("signal.rotate"))
            new RotateExperiment().run(mc);
          else if (Boolean.getBoolean("signal.water"))
            new WaterExperiment().run(mc);
          else
            new TimingExperiment().run(mc);
        });
      }
    });
  }
}
