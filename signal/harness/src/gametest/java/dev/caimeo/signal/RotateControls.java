package dev.caimeo.signal;

import java.util.LinkedHashMap;
import java.util.Map;
import net.minecraft.client.Minecraft;
import net.minecraft.util.Mth;

/** Ordinary input stimuli and client pose checks, independent of the receiver. */
public final class RotateControls {
  private static String activity = "idle";
  private static boolean active;
  private static double expectedYaw;
  private static double maximumAngleError;
  private static double maximumRawYaw;
  private static double minimumY;
  private static double maximumY;
  private static int ticks;
  private static int focusedTicks, grabbedTicks, attackTicks, destroyingTicks;

  public static void start(Minecraft mc, String kind) {
    activity = kind;
    expectedYaw = mc.player.getYRot();
    maximumAngleError = 0;
    maximumRawYaw = Math.abs(mc.player.getYRot());
    minimumY = maximumY = mc.player.getY();
    ticks = 0;
    focusedTicks = grabbedTicks = attackTicks = destroyingTicks = 0;
    active = true;
    mc.options.keyUp.setDown(kind.equals("walk"));
    mc.options.keyJump.setDown(kind.equals("jump"));
    mc.options.keyAttack.setDown(kind.equals("mine"));
  }

  public static void startTick(Minecraft mc) {
    if (active && mc.player != null && activity.equals("turn")) {
      mc.player.turn(0.37 / 0.15, 0);
      expectedYaw += 0.37;
    }
  }

  public static void endTick(Minecraft mc) {
    if (!active || mc.player == null)
      return;
    ticks++;
    if (mc.isWindowActive())
      focusedTicks++;
    if (mc.mouseHandler.isMouseGrabbed())
      grabbedTicks++;
    if (mc.options.keyAttack.isDown())
      attackTicks++;
    if (mc.gameMode != null && mc.gameMode.isDestroying())
      destroyingTicks++;
    maximumAngleError =
        Math.max(maximumAngleError,
                 Math.abs(Mth.wrapDegrees(mc.player.getYRot() - expectedYaw)));
    maximumRawYaw = Math.max(maximumRawYaw, Math.abs(mc.player.getYRot()));
    minimumY = Math.min(minimumY, mc.player.getY());
    maximumY = Math.max(maximumY, mc.player.getY());
  }

  public static Map<String, Object> stop(Minecraft mc) {
    active = false;
    mc.options.keyUp.setDown(false);
    mc.options.keyJump.setDown(false);
    mc.options.keyAttack.setDown(false);
    if (mc.gameMode != null)
      mc.gameMode.stopDestroyBlock();
    var result = new LinkedHashMap<String, Object>();
    result.put("activity", activity);
    result.put("client_ticks", ticks);
    result.put("focused_ticks", focusedTicks);
    result.put("mouse_grabbed_ticks", grabbedTicks);
    result.put("attack_down_ticks", attackTicks);
    result.put("destroying_ticks", destroyingTicks);
    result.put("max_angle_error_degrees", maximumAngleError);
    result.put("max_raw_yaw_degrees", maximumRawYaw);
    result.put("vertical_range_blocks", maximumY - minimumY);
    return result;
  }
}
