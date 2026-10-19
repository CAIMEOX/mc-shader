package dev.caimeo.manifold;

import com.google.gson.JsonParser;
import com.mojang.blaze3d.platform.InputConstants;
import net.fabricmc.fabric.api.client.gametest.v1.context.ClientGameTestContext;
import net.fabricmc.fabric.api.client.gametest.v1.context.TestServerContext;
import net.minecraft.resources.Identifier;
import java.util.*;

final class MessageChecks {
  static void run(ClientGameTestContext context, TestServerContext server,
                  List<Map<String, Object>> checks) {
    String original =
        context.computeOnClient(mc -> mc.getLanguageManager().getSelected());
    context.runOnClient(mc -> MessageCapture.start());
    try {
      for (String language : List.of("en_us", "zh_cn")) {
        select(context, language);
        var catalog = context.computeOnClient(mc -> {
          try (var reader = mc.getResourceManager()
                                .getResourceOrThrow(Identifier.parse(
                                    "manifold:lang/" + language + ".json"))
                                .openAsReader()) {
            var values = new HashMap<String, String>();
            for (var entry :
                 JsonParser.parseReader(reader).getAsJsonObject().entrySet())
              values.put(entry.getKey(), entry.getValue().getAsString());
            return values;
          } catch (Exception error) {
            throw new RuntimeException(error);
          }
        });
        take(context);
        server.runCommand("function manifold:three_rings/start");
        server.runCommand("function manifold:quality/low");
        nativeReady(context, server);
        var entry = take(context);
        require(entry.size() == 1 &&
                    entry.getFirst().key().equals("manifold.rings.name"),
                "Entry presents the chapter name: " + entry);
        localized(entry, catalog);
        invoke(server, "manifold:three_rings/activate");
        context.getInput().lookAt(90, -90);
        context.waitTicks(3);
        context.getInput().holdKey(InputConstants.KEY_LCONTROL);
        context.waitTicks(4);
        context.getInput().releaseKey(InputConstants.KEY_LCONTROL);
        server.waitFor(s
                       -> TransportChecks.value(s, "h.mode") == 1 &&
                              TransportChecks.value(s, "g.dy") == 1,
                       400);
        nativeReady(context, server);
        require(take(context).isEmpty(),
                "Landing and activation keep the play view clear");
        checks.add(Map.of("case", "ui_play", "language", language, "chapter", entry));

        server.runCommand("function manifold:help");
        context.waitTicks(4);
        var help = take(context);
        require(help.size() == 4 &&
                    help.stream().allMatch(m -> m.channel().equals("chat")),
                "Help is presented on request");
        require(help.getFirst().bindings().equals(List.of("key.use", "key.sprint")),
                "Help resolves the configured interaction and gravity keys");
        localized(help, catalog);
        invoke(server, "manifold:three_rings/holding");
        context.waitTicks(3);
        var feedback = take(context);
        require(feedback.size() == 1 &&
                    feedback.getFirst().channel().equals("actionbar"),
                "A blocked action gives one short response");
        localized(feedback, catalog);
        checks.add(Map.of("case", "ui_help", "language", language, "messages", help,
                          "action_feedback", feedback));

        server.runOnServer(s -> {
          int[][] cells = {{38, 63, 12}, {38, 3, 9}, {38, 3, 28}};
          for (int id = 0; id < cells.length; id++) {
            for (int a = 0; a < 3; a++)
              s.getCommands().performPrefixedCommand(
                  s.createCommandSourceStack(),
                  "data modify storage manifold:runtime cubes[" + id + "]."
                      + "xyz".charAt(a) + " set value " + cells[id][a]);
            s.getCommands().performPrefixedCommand(
                s.createCommandSourceStack(),
                "data modify storage manifold:runtime cubes[" + id +
                    "].phase set value 0");
          }
        });
        invoke(server, "manifold:three_rings/goal");
        context.waitTicks(3);
        invoke(server, "manifold:three_rings/goal");
        invoke(server, "manifold:three_rings/activate");
        context.waitTicks(3);
        var victory = take(context);
        victory(context, victory, "rings", catalog);
        require(server.computeOnServer(s -> TransportChecks.value(s, "r.complete")) ==
                    1,
                "The circuit goal retains its completed state");
        context.takeScreenshot("manifold-victory-" + language);
        checks.add(Map.of("case", "ui_victory", "level", "rings", "language", language,
                          "messages", victory));

        server.runCommand("function manifold:joinery/start");
        server.runCommand("function manifold:quality/low");
        nativeReady(context, server);
        localized(take(context), catalog);
        server.runCommand("function manifold:help");
        context.waitTicks(3);
        var joineryHelp = take(context);
        localized(joineryHelp, catalog);
        require(joineryHelp.size() == 3,
                "Joinery controls and recovery are available on request");
        server.runOnServer(s -> {
          for (int id = 0; id < 6; id++)
            for (char axis : "xyz".toCharArray())
              s.getCommands().performPrefixedCommand(s.createCommandSourceStack(),
                                                     "scoreboard players set #j.p" +
                                                         id + axis + " manifold 0");
        });
        invoke(server, "manifold:joinery/encode");
        invoke(server, "manifold:joinery/goal");
        context.waitTicks(3);
        var joineryVictory = take(context);
        victory(context, joineryVictory, "joinery", catalog);
        checks.add(Map.of("case", "ui_joinery", "language", language, "help",
                          joineryHelp, "victory", joineryVictory));
        server.runCommand("function manifold:start");
        server.runCommand("function manifold:quality/low");
        nativeReady(context, server);
        require(take(context).isEmpty(), "Lattice exploration begins with the scene");
        server.runCommand("function manifold:help");
        context.waitTicks(3);
        var exploration = take(context);
        require(exploration.size() == 3, "Lattice controls are available on request");
        localized(exploration, catalog);
        server.runCommand("function manifold:flight");
        server.runCommand("function manifold:quality/low");
        context.waitTicks(8);
        require(take(context).isEmpty(), "Flight starts with the scene");
        server.runCommand("function manifold:help");
        context.waitTicks(3);
        var flight = take(context);
        require(flight.size() == 2, "Flight controls are available on request");
        localized(flight, catalog);
        checks.add(Map.of("case", "ui_exploration", "language", language,
                          "lattice_help", exploration, "flight_help", flight));
        server.runCommand("function manifold:stop");
        context.waitTicks(12);
      }
    } finally {
      context.getInput().releaseKey(InputConstants.KEY_LCONTROL);
      context.runOnClient(mc -> MessageCapture.stop());
      server.runCommand("function manifold:stop");
      select(context, original);
    }
  }

  static void joinery(ClientGameTestContext context, TestServerContext server,
                      List<Map<String, Object>> checks) {
    String original =
        context.computeOnClient(mc -> mc.getLanguageManager().getSelected());
    context.runOnClient(mc -> MessageCapture.start());
    try {
      for (String language : List.of("en_us", "zh_cn")) {
        select(context, language);
        var catalog = context.computeOnClient(mc -> {
          try (var reader = mc.getResourceManager()
                                .getResourceOrThrow(Identifier.parse(
                                    "manifold:lang/" + language + ".json"))
                                .openAsReader()) {
            var values = new HashMap<String, String>();
            for (var e : JsonParser.parseReader(reader).getAsJsonObject().entrySet())
              values.put(e.getKey(), e.getValue().getAsString());
            return values;
          } catch (Exception e) {
            throw new RuntimeException(e);
          }
        });
        take(context);
        server.runCommand("function manifold:help");
        context.waitTicks(3);
        var help = take(context);
        require(help.size() == 3, "Joinery presents controls and recovery on request");
        localized(help, catalog);
        require(context
                    .computeOnClient(
                        mc -> mc.player.getMainHandItem().getHoverName().getString())
                    .equals(catalog.get("manifold.joinery.tool")),
                "The held tool uses the selected client language");
        invoke(server, "manifold:joinery/complete");
        context.waitTicks(3);
        var ending = take(context);
        victory(context, ending, "joinery", catalog);
        context.takeScreenshot("manifold-joinery-victory-" + language);
        checks.add(Map.of("case", "ui_joinery", "language", language, "help", help,
                          "victory", ending));
      }
    } finally {
      context.runOnClient(mc -> MessageCapture.stop());
      select(context, original);
    }
  }

  private static void localized(List<MessageCapture.Message> messages,
                                Map<String, String> catalog) {
    for (var message : messages) {
      String expected = String.format(Locale.ROOT, catalog.get(message.key()),
                                      message.arguments().toArray());
      require(expected.equals(message.text()),
              "The client resolves the selected language and arguments");
    }
  }
  private static void victory(ClientGameTestContext context,
                              List<MessageCapture.Message> messages, String level,
                              Map<String, String> catalog) {
    require(messages.size() == 2 &&
                messages.stream()
                        .filter(m
                                -> m.channel().equals("title") &&
                                       m.key().equals("manifold." + level + ".victory"))
                        .count() == 1 &&
                messages.stream()
                        .filter(m
                                -> m.channel().equals("subtitle") &&
                                       m.key().equals("manifold." + level + ".ending"))
                        .count() == 1,
            "Victory presents one localized title and subtitle: " + messages);
    localized(messages, catalog);
    require(context.computeOnClient(
                mc
                -> messages.stream().allMatch(
                    message
                    -> mc.font.width(message.text()) *
                               (message.channel().equals("title") ? 4 : 2) <=
                           mc.getWindow().getGuiScaledWidth() - 16)),
            "Victory text fits the client's scaled viewport");
  }
  private static void invoke(TestServerContext server, String name) {
    server.runCommand("execute as @a[tag=manifold.pilot,limit=1] at @s run function " +
                      name);
  }
  private static List<MessageCapture.Message> take(ClientGameTestContext context) {
    return context.computeOnClient(mc -> MessageCapture.take());
  }
  private static void nativeReady(ClientGameTestContext context,
                                  TestServerContext server) {
    server.waitFor(s
                   -> TransportChecks.value(s, "h.mode") == 1 &&
                          s.getPlayerList().getPlayers().getFirst().onGround(),
                   400);
    context.waitFor(mc -> !mc.player.isSpectator(), 200);
    context.waitTicks(5);
  }
  private static void select(ClientGameTestContext context, String language) {
    var reload = context.computeOnClient(mc -> {
      mc.getLanguageManager().setSelected(language);
      mc.options.languageCode = language;
      return mc.reloadResourcePacks();
    });
    context.waitFor(mc -> reload.isDone(), 1200);
    reload.join();
    context.waitFor(mc -> mc.gui.overlay() == null, 400);
  }
  private static void require(boolean condition, String message) {
    if (!condition)
      throw new AssertionError(message);
  }
}
