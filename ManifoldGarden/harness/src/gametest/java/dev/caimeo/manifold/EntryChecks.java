package dev.caimeo.manifold;

import net.fabricmc.fabric.api.client.gametest.v1.context.ClientGameTestContext;
import net.fabricmc.fabric.api.client.gametest.v1.context.TestServerContext;
import net.minecraft.core.registries.Registries;
import net.minecraft.resources.Identifier;
import net.minecraft.resources.ResourceKey;
import net.minecraft.world.entity.ai.attributes.Attributes;
import net.minecraft.world.level.GameType;
import net.minecraft.world.level.Level;
import net.minecraft.world.level.gamerules.GameRules;
import net.minecraft.world.phys.Vec3;
import net.minecraft.world.scores.ScoreHolder;
import java.util.*;

/** Exercises the launcher's packaged entry flow with an ordinary survival player. */
final class EntryChecks {
  private static final ResourceKey<Level> STAGE =
      ResourceKey.create(Registries.DIMENSION, Identifier.parse("manifold:stage"));
  private static final Identifier PROTECTION =
      Identifier.parse("manifold:session_fall_protection");

  static void run(ClientGameTestContext context, TestServerContext server,
                  List<Map<String, Object>> checks) {
    runLaunch(context, server, checks);
    runSafety(context, server, checks);
    explicitExitAndReopen(context, server, checks);
  }

  static void runLaunch(ClientGameTestContext context, TestServerContext server,
                        List<Map<String, Object>> checks) {
    var observation = new LinkedHashMap<String, Object>();
    var samples = new ArrayList<Map<String, Object>>();
    observation.put("case", "launcher_survival_entry");
    observation.put("samples", samples);
    checks.add(observation);

    // A persisted visit is independent of whether this player owns a live session.
    // Configure the fixture atomically, before the next vanilla server tick.
    server.runOnServer(s -> {
      var commands = s.getCommands();
      var source = s.createCommandSourceStack();
      for (String command :
           List.of("execute as @a[tag=manifold.pilot] at @s run function manifold:stop",
                   "scoreboard players reset @a manifold.launch_seen",
                   "tag @a add manifold.hybrid_visited", "tag @a remove manifold.pilot",
                   "effect clear @a", "gamemode survival @a",
                   "execute in minecraft:overworld run tp @a 1 67 15 0 0"))
        commands.performPrefixedCommand(source, command);
      var player = s.getPlayerList().getPlayers().getFirst();
      player.setHealth(player.getMaxHealth());
    });

    boolean aliveThroughout = true;
    for (int tick = 0; tick <= 80; tick++) {
      var sample = state(server);
      aliveThroughout &= (Boolean)sample.get("alive");
      if (tick % 10 == 0 || !(Boolean)sample.get("alive"))
        samples.add(Map.of("tick", tick, "player", sample));
      if (tick < 80)
        context.waitTicks(1);
    }
    var settled = state(server);
    observation.put("alive_throughout", aliveThroughout);
    observation.put("settled", settled);
    check(aliveThroughout && (Boolean)settled.get("alive"),
          "The survival player remains alive throughout launcher entry: " + settled);
    check((Boolean)settled.get("stage") && (Boolean)settled.get("adventure") &&
              (Boolean)settled.get("pilot"),
          "The launcher enters its adventure stage for a returning player: " + settled);
    check((Boolean)settled.get("grounded"),
          "The launcher settles the player on the physical entrance platform: " +
              settled);
    check(!(Boolean)settled.get("fall_damage_rule"),
          "The demo world starts with fall damage disabled");
    context.takeScreenshot("manifold-launcher-entrance");
  }

  static void runSafety(ClientGameTestContext context, TestServerContext server,
                        List<Map<String, Object>> checks) {
    server.runOnServer(s -> {
      var commands = s.getCommands();
      var source = s.createCommandSourceStack();
      commands.performPrefixedCommand(
          source, "execute as @a[tag=manifold.pilot] at @s run function manifold:stop");
      commands.performPrefixedCommand(
          source, "execute as @a at @s run function manifold:start");
    });
    server.waitFor(s -> {
      var player = s.getPlayerList().getPlayers().getFirst();
      return player.level().dimension().equals(STAGE) && player.onGround() &&
          value(s, "h.mode") == 1;
    }, 160);
    context.waitFor(mc
                    -> mc.player != null && mc.player.onGround() &&
                           !mc.player.getAbilities().flying,
                    100);
    nativeLanding(context, server, checks, "stage_survival_landing");
    respawn(context, server, checks);
    nativeLanding(context, server, checks, "stage_respawn_landing");
  }

  private static void nativeLanding(ClientGameTestContext context,
                                    TestServerContext server,
                                    List<Map<String, Object>> checks, String caseName) {
    var observation = new LinkedHashMap<String, Object>();
    var samples = new ArrayList<Map<String, Object>>();
    observation.put("case", caseName);
    observation.put("samples", samples);
    checks.add(observation);
    server.runOnServer(s -> {
      var commands = s.getCommands();
      var source = s.createCommandSourceStack();
      for (
          String command : List.of(
              "gamerule minecraft:fall_damage true",
              "effect clear @a minecraft:resistance", "gamemode survival @a",
              "execute as @a run attribute @s minecraft:fall_damage_multiplier base set 0.6",
              "execute in manifold:stage run tp @a 8.5 228 0.5 0 0"))
        commands.performPrefixedCommand(source, command);
      var player = s.getPlayerList().getPlayers().getFirst();
      player.setHealth(player.getMaxHealth());
      player.resetFallDistance();
      player.setDeltaMovement(Vec3.ZERO);
    });
    var initial = state(server);
    check(
        (Boolean)initial.get("fall_damage_rule"),
        "Native landing exercises player protection while the fall damage rule is enabled");
    float startingHealth = ((Number)initial.get("health")).floatValue();
    boolean aliveThroughout = true;
    boolean healthPreserved = true;
    boolean airborne = false;
    boolean landed = false;
    double largestFallDistance = 0;
    for (int tick = 0; tick < 160; tick++) {
      context.waitTicks(1);
      var sample = state(server);
      double y = ((Number)((List<?>)sample.get("position")).get(1)).doubleValue();
      aliveThroughout &= (Boolean)sample.get("alive");
      healthPreserved &= ((Number)sample.get("health")).floatValue() == startingHealth;
      airborne |= !(Boolean)sample.get("grounded") && y > 205;
      largestFallDistance = Math.max(
          largestFallDistance, ((Number)sample.get("fall_distance")).doubleValue());
      landed = airborne && (Boolean)sample.get("grounded") && Math.abs(y - 202) < .05;
      if (tick % 5 == 0 || landed || !(Boolean)sample.get("alive"))
        samples.add(Map.of("tick", tick, "player", sample));
      if (landed || !(Boolean)sample.get("alive"))
        break;
    }
    var settled = state(server);
    observation.put("initial", initial);
    observation.put("settled", settled);
    observation.put("max_server_fall_distance", largestFallDistance);
    observation.put("airborne", airborne);
    observation.put("landed", landed);
    check(
        airborne && landed,
        "Vanilla movement carries the survival player from height onto the stage floor: " +
            observation);
    check(largestFallDistance > 3,
          "The vanilla server accumulated a damaging fall before contact: " +
              observation);
    check(aliveThroughout && healthPreserved && (Boolean)settled.get("alive"),
          "The stage protects the survival player's health during a native landing: " +
              observation);
    check((Boolean)settled.get("stage") && (Boolean)settled.get("pilot") &&
              ((Number)settled.get("hybrid_mode")).intValue() == 1,
          "The native survival landing preserves the stage session: " + settled);
    check(
        (Boolean)settled.get("fall_protection") &&
            ((Number)settled.get("fall_multiplier")).doubleValue() == 0 &&
            ((Number)settled.get("fall_base")).doubleValue() == .6,
        "Session protection suppresses damage while preserving the player's base attribute: " +
            settled);
    context.takeScreenshot("manifold-" + caseName.replace('_', '-'));
  }

  private static void respawn(ClientGameTestContext context, TestServerContext server,
                              List<Map<String, Object>> checks) {
    var observation = new LinkedHashMap<String, Object>();
    observation.put("case", "stage_respawn");
    checks.add(observation);
    server.runCommand("kill @a");
    context.waitFor(mc -> mc.player != null && !mc.player.isAlive(), 80);
    context.waitTicks(25);
    var dead = state(server);
    observation.put("death", dead);
    check(!(Boolean)dead.get("alive"), "The server observes the player's death");
    // This is the same client API used by the vanilla death screen's Respawn button.
    context.runOnClient(mc -> mc.player.respawn());
    for (int tick = 0; tick < 160; tick++) {
      context.waitTicks(1);
      var sample = state(server);
      if ((Boolean)sample.get("alive") && (Boolean)sample.get("stage") &&
          (Boolean)sample.get("grounded") && (Boolean)sample.get("adventure") &&
          ((Number)sample.get("hybrid_mode")).intValue() == 1)
        break;
    }
    var settled = state(server);
    observation.put("settled", settled);
    check(
        (Boolean)settled.get("alive") && (Boolean)settled.get("stage") &&
            (Boolean)settled.get("grounded") && (Boolean)settled.get("adventure") &&
            (Boolean)settled.get("pilot") &&
            ((Number)settled.get("hybrid_mode")).intValue() == 1,
        "Vanilla respawn restores an active adventure session on the stage platform: " +
            settled);
    context.waitFor(mc
                    -> mc.player != null && mc.player.isAlive() &&
                           mc.player.onGround() && mc.gui.screen() == null,
                    100);
  }

  private static void explicitExitAndReopen(ClientGameTestContext context,
                                            TestServerContext server,
                                            List<Map<String, Object>> checks) {
    server.runCommand("function manifold:stop");
    boolean aliveThroughout = true;
    for (int tick = 0; tick < 80; tick++) {
      context.waitTicks(1);
      aliveThroughout &= (Boolean)state(server).get("alive");
    }
    var exited = state(server);
    checks.add(Map.of("case", "launcher_explicit_exit", "settled", exited,
                      "alive_throughout", aliveThroughout));
    check(
        aliveThroughout && (Boolean)exited.get("alive") &&
            (Boolean)exited.get("grounded") && (Boolean)exited.get("adventure") &&
            !(Boolean)exited.get("pilot") &&
            ((Number)exited.get("hybrid_mode")).intValue() == 0 &&
            exited.get("dimension").equals("minecraft:overworld"),
        "Explicit exit keeps the player safely in the lobby through subsequent launcher ticks: " +
            exited);
    var lobby = (List<?>)exited.get("position");
    check(new Vec3(((Number)lobby.get(0)).doubleValue(),
                   ((Number)lobby.get(1)).doubleValue(),
                   ((Number)lobby.get(2)).doubleValue())
                  .distanceTo(new Vec3(4.5, 65, 4.5)) < .05,
          "Explicit exit returns to the launcher lobby platform: " + exited);
    check(
        !(Boolean)exited.get("fall_protection") &&
            ((Number)exited.get("fall_multiplier")).doubleValue() == .6 &&
            ((Number)exited.get("fall_base")).doubleValue() == .6,
        "Session exit removes its modifier and preserves the existing base attribute: " +
            exited);

    int before =
        server.computeOnServer(s -> score(s, "manifold.launch", "#generation"));
    server.runCommand("function manifold_launch:load");
    context.waitTicks(80);
    var reopened = state(server);
    int after = server.computeOnServer(s -> score(s, "manifold.launch", "#generation"));
    int seen = server.computeOnServer(s -> {
      var player = s.getPlayerList().getPlayers().getFirst();
      var entry = s.getScoreboard().getPlayerScoreInfo(
          player, s.getScoreboard().getObjective("manifold.launch_seen"));
      return entry == null ? 0 : entry.value();
    });
    checks.add(Map.of("case", "launcher_world_load", "before_generation", before,
                      "after_generation", after, "player_generation", seen, "settled",
                      reopened));
    check(
        after == before + 1 && seen == after,
        "World load advances the entry generation and records the player's admission");
    check((Boolean)reopened.get("alive") && (Boolean)reopened.get("grounded") &&
              (Boolean)reopened.get("adventure") && (Boolean)reopened.get("stage") &&
              (Boolean)reopened.get("pilot") &&
              ((Number)reopened.get("hybrid_mode")).intValue() == 1 &&
              !(Boolean)reopened.get("fall_damage_rule"),
          "The next world load starts a protected stage session from the lobby: " +
              reopened);
    activeSessionLoad(context, server, checks);
  }

  private static void activeSessionLoad(ClientGameTestContext context,
                                        TestServerContext server,
                                        List<Map<String, Object>> checks) {
    var observation = new LinkedHashMap<String, Object>();
    observation.put("case", "launcher_active_session_load");
    checks.add(observation);
    server.runCommand(
        "execute as @a[tag=manifold.pilot] at @s run function manifold:hybrid/turn/west");
    server.waitFor(s -> {
      var player = s.getPlayerList().getPlayers().getFirst();
      return player.level().dimension().equals(STAGE) && player.onGround() &&
          value(s, "h.mode") == 1 && value(s, "g.frame") != 0;
    }, 200);
    context.waitTicks(8);
    var active = state(server);
    observation.put("before_load", active);
    check(((Number)active.get("frame")).intValue() != 0,
          "The active session has a turned gravity frame");
    server.runCommand("function manifold_launch:load");
    context.waitTicks(80);
    var restored = state(server);
    double positionError = position(restored).distanceTo(position(active));
    observation.put("after_load", restored);
    observation.put("position_error", positionError);
    check((Boolean)restored.get("alive") && (Boolean)restored.get("grounded") &&
              (Boolean)restored.get("stage") && (Boolean)restored.get("pilot") &&
              ((Number)restored.get("hybrid_mode")).intValue() == 1 &&
              restored.get("frame").equals(active.get("frame")) &&
              restored.get("slot").equals(active.get("slot")) && positionError < .05,
          "Loading the launcher preserves the active room and gravity: " + observation);
    server.runCommand("function manifold:stop");
    context.waitTicks(10);
    var exited = state(server);
    observation.put("exited", exited);
    check((Boolean)exited.get("alive") && (Boolean)exited.get("grounded") &&
              !(Boolean)exited.get("pilot") &&
              exited.get("dimension").equals("minecraft:overworld") &&
              position(exited).distanceTo(new Vec3(4.5, 65, 4.5)) < .05,
          "The resumed session retains its safe lobby return point: " + exited);
  }

  private static Vec3 position(Map<String, Object> state) {
    var coordinates = (List<?>)state.get("position");
    return new Vec3(((Number)coordinates.get(0)).doubleValue(),
                    ((Number)coordinates.get(1)).doubleValue(),
                    ((Number)coordinates.get(2)).doubleValue());
  }

  private static Map<String, Object> state(TestServerContext server) {
    return server.computeOnServer(s -> {
      var player = s.getPlayerList().getPlayers().getFirst();
      var result = new LinkedHashMap<String, Object>();
      result.put("alive", player.isAlive());
      result.put("health", player.getHealth());
      result.put("dimension", player.level().dimension().identifier().toString());
      result.put("stage", player.level().dimension().equals(STAGE));
      result.put("adventure",
                 player.gameMode.getGameModeForPlayer() == GameType.ADVENTURE);
      result.put("game_mode", player.gameMode.getGameModeForPlayer().getName());
      result.put("grounded", player.onGround());
      result.put("pilot", player.entityTags().contains("manifold.pilot"));
      result.put("position", List.of(player.getX(), player.getY(), player.getZ()));
      result.put("fall_distance", player.fallDistance);
      result.put("hybrid_mode", value(s, "h.mode"));
      result.put("frame", value(s, "g.frame"));
      result.put("slot", value(s, "h.slot"));
      var fall = player.getAttribute(Attributes.FALL_DAMAGE_MULTIPLIER);
      result.put("fall_base", fall.getBaseValue());
      result.put("fall_multiplier", fall.getValue());
      result.put("fall_protection", fall.hasModifier(PROTECTION));
      result.put("fall_damage_rule",
                 player.level().getGameRules().get(GameRules.FALL_DAMAGE));
      return result;
    });
  }

  private static int value(net.minecraft.server.MinecraftServer server, String name) {
    return score(server, "manifold", "#" + name);
  }

  private static int score(net.minecraft.server.MinecraftServer server,
                           String objectiveName, String holder) {
    var board = server.getScoreboard();
    var objective = board.getObjective(objectiveName);
    if (objective == null)
      return 0;
    var entry = board.getPlayerScoreInfo(ScoreHolder.forNameOnly(holder), objective);
    return entry == null ? 0 : entry.value();
  }

  private static void check(boolean condition, String message) {
    if (!condition)
      throw new AssertionError(message);
  }
}
