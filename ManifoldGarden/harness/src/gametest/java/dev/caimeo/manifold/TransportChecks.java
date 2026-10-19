package dev.caimeo.manifold;

import com.google.gson.JsonParser;
import net.fabricmc.fabric.api.client.gametest.v1.context.TestServerContext;
import net.minecraft.core.component.DataComponents;
import net.minecraft.resources.Identifier;
import net.minecraft.server.MinecraftServer;
import net.minecraft.world.entity.Display;
import net.minecraft.world.scores.ScoreHolder;
import java.io.InputStreamReader;
import java.math.BigInteger;
import java.nio.charset.StandardCharsets;
import java.util.*;

/** Exercises the native command encoder against the declared wire format. */
final class TransportChecks {
  record Field(String name, int offset, int width, int bias) {
    int limit() {
      return 1 << width;
    }
  }

  static void run(TestServerContext server, List<Map<String, Object>> checks) {
    List<Field> fields;
    try (var stream =
             TransportChecks.class.getResourceAsStream("/manifold-build.json")) {
      var metadata = JsonParser
                         .parseReader(new InputStreamReader(
                             Objects.requireNonNull(stream), StandardCharsets.UTF_8))
                         .getAsJsonObject();
      fields = new ArrayList<>();
      for (var entry : metadata.getAsJsonArray("protocol_fields")) {
        var field = entry.getAsJsonObject();
        fields.add(
            new Field(field.get("name").getAsString(), field.get("offset").getAsInt(),
                      field.get("width").getAsInt(), field.get("bias").getAsInt()));
      }
    } catch (Exception error) {
      throw new RuntimeException(error);
    }
    int vectors = server.computeOnServer(s -> {
      var saved = fields.stream().mapToInt(f -> value(s, f.name())).toArray();
      var payload = new int[fields.size()];
      var random = new Random(0x4d414e);
      int count = 0;
      try {
        for (int iteration = 0; iteration < 40; iteration++) {
          for (int i = 0; i < fields.size(); i++) {
            var field = fields.get(i);
            payload[i] = (iteration == 0   ? 0
                          : iteration == 1 ? field.limit() - 1
                                           : random.nextInt(field.limit())) -
                         field.bias();
          }
          verify(s, fields, payload);
          count++;
        }
        for (int i = 0; i < fields.size(); i++) {
          var field = fields.get(i);
          for (int boundary : new int[] {0, 1, 31, 32, 255, 256, 65535, 65536}) {
            payload[i] = (boundary % field.limit()) - field.bias();
            verify(s, fields, payload);
            count++;
          }
        }
        verify(s, fields, payload);
        set(s, "tx.ready", 0);
        verify(s, fields, payload);
        return count + 2;
      } finally {
        for (int i = 0; i < fields.size(); i++)
          set(s, fields.get(i).name(), saved[i]);
        send(s);
      }
    });
    checks.add(Map.of("case", "incremental_transport", "payload_vectors", vectors,
                      "storage_and_carrier_match", true, "cache_reinitializes", true));

    int sequenceDelta = server.computeOnServer(s -> {
      var player = s.getPlayerList().getPlayers().getFirst();
      player.setXRot(-90);
      player.setYRot(90);
      s.getScoreboard()
          .getOrCreatePlayerScore(player,
                                  s.getScoreboard().getObjective("manifold.action"))
          .set(1);
      int before = value(s, "g.seq");
      s.getCommands().performPrefixedCommand(s.createCommandSourceStack(),
                                             "function manifold:tick");
      int delta = (value(s, "g.seq") - before + 65536) % 65536;
      if (value(s, "h.mode") != 2 || delta != 1 || value(s, "tx.pending") != 0 ||
          value(s, "tx.defer") != 0)
        throw new AssertionError("A gravity turn publishes one completed tick: delta=" +
                                 delta + ", mode=" + value(s, "h.mode"));
      return delta;
    });
    checks.add(
        Map.of("case", "tick_publication", "sequence_delta", sequenceDelta, "mode", 2));
  }

  private static void verify(MinecraftServer server, List<Field> fields, int[] values) {
    BigInteger packed = BigInteger.ZERO;
    int bits = 0;
    for (int i = 0; i < fields.size(); i++) {
      var field = fields.get(i);
      set(server, field.name(), values[i]);
      packed = packed.or(
          BigInteger.valueOf(values[i] + field.bias()).shiftLeft(field.offset()));
      bits = Math.max(bits, field.offset() + field.width());
    }
    send(server);
    var expected = new ArrayList<Integer>();
    for (int offset = 0; offset < bits; offset += 24)
      expected.add(packed.shiftRight(offset).intValue() & 0xffffff);
    var storage = server.getCommandStorage()
                      .get(Identifier.parse("manifold:tx"))
                      .getList("colors")
                      .orElseThrow();
    var actual = new ArrayList<Integer>();
    for (int i = 0; i < storage.size(); i++)
      actual.add(storage.getInt(i).orElseThrow());
    if (!actual.subList(0, expected.size()).equals(expected))
      throw new AssertionError("Native payload packing: " + actual + " expected " +
                               expected);
    boolean found = false;
    for (var entity :
         server.getPlayerList().getPlayers().getFirst().level().getAllEntities()) {
      if (!(entity instanceof Display.ItemDisplay display) ||
          !entity.entityTags().contains("manifold.carrier"))
        continue;
      var data = display.getSlot(0).get().get(DataComponents.CUSTOM_MODEL_DATA);
      if (data == null || !data.colors().equals(actual))
        throw new AssertionError("The carrier contains the encoded payload");
      found = true;
    }
    if (!found)
      throw new AssertionError("An active carrier receives the payload");
  }

  private static void send(MinecraftServer server) {
    server.getCommands().performPrefixedCommand(
        server.createCommandSourceStack(),
        "execute as @a[tag=manifold.pilot,limit=1] at @s run function manifold:send");
  }
  static int value(MinecraftServer server, String name) {
    var score = server.getScoreboard().getPlayerScoreInfo(
        ScoreHolder.forNameOnly("#" + name),
        server.getScoreboard().getObjective("manifold"));
    return score == null ? 0 : score.value();
  }
  private static void set(MinecraftServer server, String name, int value) {
    server.getScoreboard()
        .getOrCreatePlayerScore(ScoreHolder.forNameOnly("#" + name),
                                server.getScoreboard().getObjective("manifold"))
        .set(value);
  }
}
