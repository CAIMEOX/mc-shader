package dev.caimeo.manifold;

import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import com.mojang.blaze3d.platform.InputConstants;
import net.fabricmc.fabric.api.client.gametest.v1.context.ClientGameTestContext;
import net.fabricmc.fabric.api.client.gametest.v1.context.TestServerContext;

import net.minecraft.world.phys.Vec3;
import net.minecraft.core.BlockPos;
import net.minecraft.core.component.DataComponents;
import net.minecraft.resources.Identifier;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.*;

/** Exercises tool targeting, six-axis timber translation, presentation and recovery. */
final class JoineryChecks {
  private static final JsonObject MODEL = model();
  private static final double[][][] FRAMES = frames();

  static void run(ClientGameTestContext context, TestServerContext server,
                  List<Map<String, Object>> checks) {
    server.runCommand("function manifold:joinery/start");
    server.runCommand("function manifold:quality/low");
    ready(context, server);
    check(value(server, "h.level") == 1 && value(server, "period") == 64,
          "Joinery starts in its periodic scene");
    savedTool(context, server, checks);
    context.runOnClient(mc -> mc.mouseHandler.grabMouse());
    context.getInput().lookAt(100, 15);
    context.waitTicks(45);
    var gpu = Objects.requireNonNull(GpuReadback.read(context, "probe"));
    check(gpu.scalar(12) == 1 && gpu.scalar(72) == 1,
          "The joinery camera reaches the renderer");
    context.takeScreenshot("manifold-joinery-entrance");
    RuntimeMetrics.observe(context, server, checks, "joinery_idle");
    server.runCommand("function manifold:quality/balanced");
    context.waitTicks(12);
    context.takeScreenshot("manifold-joinery-architecture");
    RuntimeMetrics.observe(context, server, checks, "joinery_balanced");
    server.runCommand("function manifold:quality/low");
    context.waitTicks(12);
    int sequence = value(server, "g.seq");
    int publications = value(server, "r.bank_publications");
    context.waitTicks(15);
    check(value(server, "g.seq") != sequence &&
              value(server, "r.bank_publications") == publications,
          "Idle timbers retain their object snapshot while the camera advances");
    checks.add(
        Map.of("case", "joinery_entry", "period", 64, "idle_bank_publications", 0));

    periodicApproach(context, server, checks);
    server.runCommand("function manifold:reset");
    ready(context, server);
    var route = MODEL.getAsJsonArray("joinery_route");
    var observed = new ArrayList<Map<String, Object>>();
    for (int step = 0; step < route.size(); step++) {
      JsonObject planned = route.get(step).getAsJsonObject();
      int rod = planned.get("rod").getAsInt();
      Vec3 down = vector(planned, "down");
      if (step == 0) {
        server.runCommand("function manifold:quality/balanced");
        context.waitTicks(5);
      }
      var before = configuration(server);
      var action = scenario(before, down, true, rod);
      fixture(context, server, action.json());
      Vec3 aim = action.aim, standing = position(server);
      click(context, server, rod, aim);
      finishMove(context, server, rod, down, before);
      check(wrapped(position(server).subtract(standing)).length() < .05,
            "A timber operation preserves the safe standing position");
      observed.add(Map.of("rod", rod, "down", down.toString(), "target",
                          configuration(server)[rod].toString()));
      if (step == 0) {
        server.runCommand("function manifold:joinery/undo");
        ready(context, server);
        check(Arrays.equals(configuration(server), before) &&
                  value(server, "j.steps") == 0,
              "Undo restores the full three-dimensional assembly");
        click(context, server, rod, aim);
        finishMove(context, server, rod, down, before);
        server.runCommand("function manifold:quality/low");
        context.waitTicks(5);
      }
      if (step == 7)
        context.takeScreenshot("manifold-joinery-key-return");
    }
    check(value(server, "j.configuration") == 0 && value(server, "r.complete") == 1 &&
              value(server, "j.steps") == route.size(),
          "The authored tool sequence closes all six member envelopes");
    checks.add(Map.of("case", "joinery_assembly", "moves", observed, "steps",
                      route.size(), "complete", 1));
    closure(context, server, checks);
    context.takeScreenshot("manifold-joinery-complete");
    server.runCommand("reload");
    context.waitTicks(20);
    check(value(server, "j.configuration") == 0 && value(server, "r.complete") == 1,
          "Reload preserves three-dimensional member positions");
    server.runCommand("function manifold:joinery/checkpoint/restore");
    ready(context, server);
    check(value(server, "j.configuration") == 0 && value(server, "r.complete") == 1,
          "Checkpoint restore reconstructs the assembled collision scene");
    checks.add(Map.of("case", "joinery_checkpoint", "configuration", 0, "complete", 1));
    RuntimeMetrics.observe(context, server, checks, "joinery_complete");
    directionChecks(context, server, checks);
    reachAndSupport(context, server, checks);
    layoutRecovery(context, server, checks);
    MessageChecks.joinery(context, server, checks);
    server.runCommand("function manifold:stop");
    context.waitTicks(10);
  }

  static void presentation(ClientGameTestContext context, TestServerContext server,
                           List<Map<String, Object>> checks) {
    server.runCommand("function manifold:joinery/start");
    server.runCommand("function manifold:quality/balanced");
    ready(context, server);
    context.runOnClient(mc -> mc.mouseHandler.grabMouse());
    context.getInput().lookAt(100, 15);
    context.waitTicks(45);
    var gpu = Objects.requireNonNull(GpuReadback.read(context, "probe"));
    check(gpu.scalar(12) == 1 && gpu.scalar(162) > .2 && gpu.scalar(162) < .85 &&
              gpu.scalar(157) > .07,
          "Wood tones retain distinguishable identities and distant contrast");
    check(gpu.scalar(160) < .04,
          "Broad timber surfaces retain a continuous wood finish");
    check(gpu.scalar(161) < .01 && gpu.scalar(163) < .002 && gpu.scalar(164) < .0001,
          "Lighting repeats with the joint and depth contrast changes continuously");
    lightField(context, checks);
    context.takeScreenshot("manifold-joinery-material");
    checks.add(Map.of(
        "case", "joinery_status_view", "values",
        context.computeOnClient(mc
                                -> Map.of("health", mc.player.getHealth(), "food",
                                          mc.player.getFoodData().getFoodLevel()))));
    checks.add(Map.of("case", "joinery_material", "haze_256", gpu.scalar(156),
                      "palette_separation", gpu.scalar(157), "surface_variation",
                      gpu.scalar(160)));
    RuntimeMetrics.observe(context, server, checks, "joinery_balanced");
    for (Vec3 down : DIRECTIONS) {
      var action = scenario(configuration(server), down, false);
      fixture(context, server, action.json());
      gpu = Objects.requireNonNull(GpuReadback.read(context, "probe"));
      Vec3 eye = new Vec3(gpu.scalar(0), gpu.scalar(1), gpu.scalar(2));
      look(context, server, wrapped(action.aim.subtract(eye)).normalize());
      context.waitTicks(5);
      gpu = Objects.requireNonNull(GpuReadback.read(context, "probe"));
      check(new Vec3(gpu.scalar(153), gpu.scalar(154), gpu.scalar(155))
                    .subtract(down)
                    .lengthSqr() < 1e-8,
            "The compact HUD follows the active world gravity direction");
      context.takeScreenshot("manifold-joinery-view-" +
                             Arrays.asList(DIRECTIONS).indexOf(down));
      checks.add(Map.of("case", "joinery_gravity_view", "down", down.toString()));
    }
    Vec3[] goal = new Vec3[6];
    Arrays.fill(goal, Vec3.ZERO);
    setConfiguration(server, goal);
    var overlook = new Scenario(0, new Vec3(0, -1, 0), new Vec3(48, 40.4, 35),
                                new Vec3(31.5, 31.5, 95.5));
    fixture(context, server, overlook.json());
    gpu = Objects.requireNonNull(GpuReadback.read(context, "probe"));
    Vec3 eye = new Vec3(gpu.scalar(0), gpu.scalar(1), gpu.scalar(2));
    look(context, server, overlook.aim.subtract(eye).normalize());
    context.waitTicks(6);
    closure(context, server, checks);
    context.takeScreenshot("manifold-joinery-fitted-joint");
    retainedPresentation(context, server, checks);
    server.runCommand("function manifold:stop");
    context.waitTicks(5);
  }

  private static void savedTool(ClientGameTestContext context, TestServerContext server,
                                List<Map<String, Object>> checks) {
    server.runCommand(
        "item replace entity @a[tag=manifold.pilot,limit=1] weapon.mainhand with minecraft:carrot_on_a_stick[minecraft:custom_data={manifold_joinery_tool:1b},minecraft:item_name={translate:\"manifold.joinery.tool\"},minecraft:unbreakable={},minecraft:damage=7]");
    context.waitTicks(3);
    var before = context.computeOnClient(
        mc -> mc.player.getMainHandItem().get(DataComponents.ITEM_MODEL));
    check(!Identifier.parse("manifold:joinery_tool").equals(before),
          "The saved-tool fixture starts with its prior presentation");
    server.runCommand(
        "execute as @a[tag=manifold.pilot,limit=1] at @s run function manifold:joinery/activate");
    context.waitTicks(4);
    check(context.computeOnClient(mc -> {
      var item = mc.player.getMainHandItem();
      return Identifier.parse("manifold:joinery_tool")
                 .equals(item.get(DataComponents.ITEM_MODEL)) &&
          item.getDamageValue() == 7 && item.getCount() == 1;
    }),
          "Equipping a saved tool updates its appearance and preserves item state");
    checks.add(Map.of("case", "joinery_saved_tool", "damage", 7, "count", 1));
  }

  private static void lightField(ClientGameTestContext context,
                                 List<Map<String, Object>> checks) {
    var image = Objects.requireNonNull(GpuReadback.read(context, "joinery_light"));
    double shadowMin = 1, shadowMax = 0, aoMin = 1;
    int samples = 0;
    for (int pixel : image.rgba()) {
      int depth = ((pixel >>> 8) & 255) * 256 + (pixel & 255);
      if (depth == 65535)
        continue;
      double shadow = (pixel >>> 24) / 255.0, ao = ((pixel >>> 16) & 255) / 255.0;
      shadowMin = Math.min(shadowMin, shadow);
      shadowMax = Math.max(shadowMax, shadow);
      aoMin = Math.min(aoMin, ao);
      samples++;
    }
    check(samples > 0 && shadowMax - shadowMin > .4 && aoMin < .85,
          "The light field separates lit surfaces, cast shadows and contacts: " +
              shadowMin + " / " + shadowMax + " / " + aoMin);
    checks.add(Map.of("case", "joinery_illumination", "shadow_min", shadowMin,
                      "shadow_max", shadowMax, "contact_min", aoMin, "samples",
                      samples));
  }
  private static void retainedPresentation(ClientGameTestContext context,
                                           TestServerContext server,
                                           List<Map<String, Object>> checks) {
    server.runCommand(
        "execute in manifold:stage run data modify storage manifold:verification carrier_range set from entity @e[tag=manifold.carrier,limit=1] view_range");
    server.runCommand(
        "execute in manifold:stage run data merge entity @e[tag=manifold.carrier,limit=1] {view_range:0.0f}");
    try {
      context.waitTicks(4);
      var packet = Objects.requireNonNull(GpuReadback.read(context, "packet"));
      check((packet.rgba()[0] & 255) < 230,
            "The presentation check uses a retained camera packet");
      var before = Objects.requireNonNull(GpuReadback.read(context, "presentation"));
      context.waitTicks(3);
      var after = Objects.requireNonNull(GpuReadback.read(context, "presentation"));
      check(Arrays.equals(before.rgba(), after.rgba()),
            "A retained frame keeps its exact antialiasing and HUD appearance");
      checks.add(Map.of("case", "joinery_retained_presentation", "frames_equal", true));
    } finally {
      server.runCommand(
          "execute in manifold:stage run data modify entity @e[tag=manifold.carrier,limit=1] view_range set from storage manifold:verification carrier_range");
      server.runCommand("data remove storage manifold:verification carrier_range");
      context.waitTicks(5);
    }
  }

  private static void periodicApproach(ClientGameTestContext context,
                                       TestServerContext server,
                                       List<Map<String, Object>> checks) {
    look(context, server, new Vec3(0, 0, 1));
    context.getInput().holdKey(InputConstants.KEY_W);
    server.waitFor(s -> TransportChecks.value(s, "g.z") > 36.2 * 4096, 80);
    context.getInput().releaseKey(InputConstants.KEY_W);
    boolean crossed = false, landed = false;
    int previous = value(server, "g.y");
    double minimumReady = 1;
    try {
      for (int tick = 0; tick < 240; tick++) {
        context.waitTicks(1);
        int y = value(server, "g.y");
        if (y - previous > 32 * 4096)
          crossed = true;
        previous = y;
        if (crossed && value(server, "g.grounded") == 0) {
          double delta = 35 - value(server, "g.z") / 4096.0,
                 velocity = value(server, "g.vz") / 4096.0;
          double control = delta * .18 - velocity * 1.8;
          if (Math.abs(delta) > .12 || Math.abs(velocity) > .025) {
            look(context, server, new Vec3(0, 0, Math.signum(control)));
            context.getInput().holdKey(InputConstants.KEY_W);
          } else
            context.getInput().releaseKey(InputConstants.KEY_W);
        }
        if (tick % 4 == 0)
          minimumReady = Math.min(
              minimumReady,
              Objects.requireNonNull(GpuReadback.read(context, "probe")).scalar(12));
        if (crossed && value(server, "g.grounded") == 1) {
          landed = true;
          break;
        }
      }
    } finally {
      context.getInput().releaseKey(InputConstants.KEY_W);
    }
    ready(context, server);
    check(
        crossed && landed && minimumReady == 1,
        "Walking off a timber crosses the periodic boundary and returns to solid ground continuously");
    look(context, server, new Vec3(-1, 0, 0));
    context.getInput().holdKey(InputConstants.KEY_LCONTROL);
    context.waitTicks(3);
    context.getInput().releaseKey(InputConstants.KEY_LCONTROL);
    server.waitFor(s -> TransportChecks.value(s, "g.dx") == -1, 80);
    ready(context, server);
    checks.add(Map.of("case", "joinery_periodic_approach", "crossed", crossed, "landed",
                      landed, "minimum_frame_ready", minimumReady, "turned_gravity",
                      true));
    context.takeScreenshot("manifold-joinery-periodic-approach");
  }
  private static void look(ClientGameTestContext context, TestServerContext server,
                           Vec3 direction) {
    var frame = FRAMES[value(server, "g.frame")];
    double x = dot(direction, frame[0]), y = dot(direction, frame[1]),
           z = dot(direction, frame[2]);
    context.getInput().lookAt((float)Math.toDegrees(Math.atan2(-x, z)),
                              (float)Math.toDegrees(Math.asin(-y)));
  }
  private static double dot(Vec3 p, double[] v) {
    return p.x * v[0] + p.y * v[1] + p.z * v[2];
  }

  private static void fixture(ClientGameTestContext context, TestServerContext server,
                              JsonObject action) {
    var p = action.getAsJsonArray("stand");
    var d = action.getAsJsonArray("down");
    int frame = -1;
    for (int i = 0; i < FRAMES.length; i++) {
      boolean match = true;
      for (int a = 0; a < 3; a++)
        match &= -FRAMES[i][1][a] == d.get(a).getAsInt();
      if (match) {
        frame = i;
        break;
      }
    }
    if (frame < 0)
      throw new AssertionError("Axial operating direction");
    int selected = frame;
    server.runOnServer(s -> {
      var source = s.createCommandSourceStack();
      for (int a = 0; a < 3; a++)
        s.getCommands().performPrefixedCommand(
            source, "scoreboard players set #g."
                        + "xyz".charAt(a) + " manifold " +
                        Math.round(p.get(a).getAsDouble() * 4096));
      s.getCommands().performPrefixedCommand(
          source, "scoreboard players set #g.frame manifold " + selected);
      s.getCommands().performPrefixedCommand(
          source, "scoreboard players set #h.busy manifold 0");
      s.getCommands().performPrefixedCommand(source,
                                             "function manifold:gravity/bounds");
      s.getCommands().performPrefixedCommand(source, "gamemode spectator @a");
      s.getCommands().performPrefixedCommand(
          source,
          "execute as @a[tag=manifold.pilot] at @s run function manifold:hybrid/land");
      s.getCommands().performPrefixedCommand(
          source,
          "execute as @a[tag=manifold.pilot] at @s run function manifold:gravity/publish");
    });
    ready(context, server);
  }

  private static void click(ClientGameTestContext context, TestServerContext server,
                            int rod, Vec3 target) {
    var gpu = Objects.requireNonNull(GpuReadback.read(context, "probe"));
    Vec3 eye = new Vec3(gpu.scalar(0), gpu.scalar(1), gpu.scalar(2));
    var cells = occupancy(configuration(server));
    Vec3 direction = wrapped(target.subtract(eye));
    if (firstHit(cells, eye, direction.normalize()) != rod) {
      var candidates = cells.entrySet()
                           .stream()
                           .filter(e -> e.getValue() == rod)
                           .map(e -> wrapped(e.getKey().centre().subtract(eye)))
                           .filter(v -> v.length() > .2 && v.length() < 96)
                           .sorted(Comparator.comparingDouble(Vec3::lengthSqr))
                           .toList();
      direction = candidates.stream()
                      .filter(v -> firstHit(cells, eye, v.normalize()) == rod)
                      .findFirst()
                      .orElseThrow(
                          ()
                              -> new AssertionError("An exposed face of member " + rod +
                                                    " is reachable from " + eye));
    }
    look(context, server, direction.normalize());
    context.waitTicks(4);
    gpu = Objects.requireNonNull(GpuReadback.read(context, "probe"));
    check(gpu.scalar(158) == 1, "The selected inventory item is the Joinery Tool");
    check(gpu.scalar(131) == rod,
          "The visible timber surface selects member " + rod + ": " + gpu.scalar(131));
    context.getInput().pressMouse(InputConstants.MOUSE_BUTTON_RIGHT);
    context.waitTicks(1);
    check(value(server, "j.hit") == rod,
          "Server and shader select the same first timber: " + rod + " / " +
              value(server, "j.hit"));
  }
  private static void finishMove(ClientGameTestContext context,
                                 TestServerContext server, int rod, Vec3 down,
                                 Vec3[] before) {
    boolean moving = false;
    double previous = 0;
    for (int tick = 0; tick < 50; tick++) {
      context.waitTicks(1);
      var gpu = Objects.requireNonNull(GpuReadback.read(context, "probe"));
      check(
          gpu.scalar(12) == 1 && gpu.scalar(164) < .0001,
          "Camera, geometry and the light-field distance queries remain coherent while translating");
      Vec3 p = new Vec3(gpu.scalar(135 + 3 * rod), gpu.scalar(136 + 3 * rod),
                        gpu.scalar(137 + 3 * rod));
      double distance = wrapped(p.subtract(before[rod].scale(4))).dot(down);
      check(distance >= previous - .12 && distance <= 4.05,
            "The timber follows its signed continuous trajectory: " + distance +
                " after " + previous);
      previous = distance;
      moving |= value(server, "j.moving") >= 0;
      if (value(server, "j.moving") == -1 &&
          !configuration(server)[rod].equals(before[rod]))
        break;
    }
    ready(context, server);
    Vec3 expected = canonical(before[rod].add(down), 16);
    check(moving && configuration(server)[rod].equals(expected),
          "The tool translates the selected timber one module: " + rod + " expected " +
              expected + " actual " + configuration(server)[rod]);
  }
  private static Vec3 vector(JsonObject json, String key) {
    var a = json.getAsJsonArray(key);
    return new Vec3(a.get(0).getAsDouble(), a.get(1).getAsDouble(),
                    a.get(2).getAsDouble());
  }
  private static Vec3[] configuration(TestServerContext server) {
    return server.computeOnServer(s -> {
      Vec3[] result = new Vec3[6];
      for (int i = 0; i < 6; i++)
        result[i] = new Vec3(TransportChecks.value(s, "j.p" + i + "x"),
                             TransportChecks.value(s, "j.p" + i + "y"),
                             TransportChecks.value(s, "j.p" + i + "z"));
      return result;
    });
  }
  private static Vec3 canonical(Vec3 p, int period) {
    return new Vec3(p.x - period * Math.floor(p.x / period),
                    p.y - period * Math.floor(p.y / period),
                    p.z - period * Math.floor(p.z / period));
  }
  private static final Vec3[] DIRECTIONS = {new Vec3(0, -1, 0), new Vec3(0, 1, 0),
                                            new Vec3(-1, 0, 0), new Vec3(1, 0, 0),
                                            new Vec3(0, 0, -1), new Vec3(0, 0, 1)};
  private record Cell(int x, int y, int z) {
    Vec3 centre() {
      return new Vec3(x * 4 + 1.5, y * 4 + 1.5, z * 4 + 1.5);
    }
    Cell moved(Vec3 d) {
      return new Cell(Math.floorMod(x + (int)d.x, 16), Math.floorMod(y + (int)d.y, 16),
                      Math.floorMod(z + (int)d.z, 16));
    }
  }
  private static Map<Cell, Integer> occupancy(Vec3[] offsets) {
    var result = new HashMap<Cell, Integer>();
    for (var element : MODEL.getAsJsonArray("joinery_solids")) {
      var box = element.getAsJsonObject();
      int id = box.get("rod").getAsInt();
      Vec3 lo = vector(box, "lo"), hi = vector(box, "hi");
      for (int x = (int)lo.x / 4; x <= (int)hi.x / 4; x++)
        for (int y = (int)lo.y / 4; y <= (int)hi.y / 4; y++)
          for (int z = (int)lo.z / 4; z <= (int)hi.z / 4; z++)
            result.put(new Cell(x, y, z).moved(offsets[id]), id);
    }
    return result;
  }
  private static int firstHit(Map<Cell, Integer> cells, Vec3 eye, Vec3 direction) {
    Vec3 p = eye.add(.5, .5, .5);
    int[] cell = {(int)Math.floor(p.x / 4), (int)Math.floor(p.y / 4),
                  (int)Math.floor(p.z / 4)};
    double[] origin = {p.x, p.y, p.z}, ray = {direction.x, direction.y, direction.z},
             next = new double[3], delta = new double[3];
    for (int a = 0; a < 3; a++) {
      next[a] = Math.abs(ray[a]) < 1e-10
                    ? 1e9
                    : ((cell[a] + (ray[a] > 0 ? 1 : 0)) * 4 - origin[a]) / ray[a];
      delta[a] = Math.abs(ray[a]) < 1e-10 ? 1e9 : 4 / Math.abs(ray[a]);
    }
    for (int count = 0; count < 96; count++) {
      var hit =
          cells.get(new Cell(Math.floorMod(cell[0], 16), Math.floorMod(cell[1], 16),
                             Math.floorMod(cell[2], 16)));
      if (hit != null)
        return hit;
      double t = Math.min(next[0], Math.min(next[1], next[2]));
      if (t > 96)
        break;
      for (int a = 0; a < 3; a++)
        if (next[a] <= t + 1e-8) {
          cell[a] += ray[a] > 0 ? 1 : -1;
          next[a] += delta[a];
        }
    }
    return -1;
  }
  private record Scenario(int rod, Vec3 down, Vec3 stand, Vec3 aim) {
    JsonObject json() {
      var result = new JsonObject();
      result.addProperty("rod", rod);
      for (var pair : List.of(Map.entry("down", down), Map.entry("stand", stand),
                              Map.entry("aim", aim))) {
        var a = new com.google.gson.JsonArray();
        a.add(pair.getValue().x);
        a.add(pair.getValue().y);
        a.add(pair.getValue().z);
        result.add(pair.getKey(), a);
      }
      return result;
    }
  }
  private static Scenario scenario(Vec3[] offsets, Vec3 down, boolean legal) {
    return scenario(offsets, down, legal, -1);
  }
  private static Scenario scenario(Vec3[] offsets, Vec3 down, boolean legal,
                                   int requested) {
    var cells = occupancy(offsets);
    var exterior = exterior(cells);
    for (int id = 0; id < 6; id++) {
      if (requested >= 0 && requested != id)
        continue;
      if (legal && requested < 0 &&
          (id / 2 == 0   ? down.x
           : id / 2 == 1 ? down.y
                         : down.z) != 0)
        continue;
      int rod = id;
      var owned = cells.entrySet()
                      .stream()
                      .filter(e -> e.getValue() == rod)
                      .map(Map.Entry::getKey)
                      .sorted(Comparator.comparingInt(Cell::x)
                                  .thenComparingInt(Cell::y)
                                  .thenComparingInt(Cell::z))
                      .toList();
      boolean clear = owned.stream().allMatch(c -> {
        Integer other = cells.get(c.moved(down));
        return other == null || other == rod;
      });
      if (clear != legal)
        continue;
      for (var support :
           cells.entrySet()
               .stream()
               .sorted(Comparator.comparingInt(
                   e -> e.getKey().x * 256 + e.getKey().y * 16 + e.getKey().z))
               .toList()) {
        if (support.getValue() == rod ||
            cells.containsKey(support.getKey().moved(down.scale(-1))))
          continue;
        Vec3 stand = canonical(support.getKey().centre().subtract(down.scale(2.9)), 64);
        Cell standingCell = new Cell((int)Math.floor((stand.x + .5) / 4),
                                     (int)Math.floor((stand.y + .5) / 4),
                                     (int)Math.floor((stand.z + .5) / 4));
        if (!exterior.contains(standingCell))
          continue;
        Vec3 eye = stand.subtract(down.scale(.72));
        boolean swept = owned.stream().anyMatch(c -> {
          Vec3 delta = wrapped(c.centre().subtract(stand)).add(down.scale(2));
          return Math.abs(delta.x) < 2 + .3 + Math.abs(down.x) * 2.6 &&
              Math.abs(delta.y) < 2 + .3 + Math.abs(down.y) * 2.6 &&
              Math.abs(delta.z) < 2 + .3 + Math.abs(down.z) * 2.6;
        });
        if (legal && swept)
          continue;
        for (var target : owned.stream()
                              .sorted(Comparator.comparingDouble(
                                  c -> wrapped(c.centre().subtract(eye)).lengthSqr()))
                              .toList()) {
          Vec3 ray = wrapped(target.centre().subtract(eye));
          if (ray.length() < 6 || ray.length() > 60)
            continue;
          if (firstHit(cells, eye, ray.normalize()) == rod)
            return new Scenario(rod, down, stand, target.centre());
        }
      }
    }
    throw new AssertionError("A visible grounded scenario exists for " + down +
                             " legal=" + legal + " member=" + requested);
  }
  private static void directionChecks(ClientGameTestContext context,
                                      TestServerContext server,
                                      List<Map<String, Object>> checks) {
    server.runCommand("function manifold:reset");
    ready(context, server);
    // A valid displaced assembly exposes transverse travel in all six directions.
    Vec3[] displaced = {new Vec3(0, 12, 11), new Vec3(0, 2, 3),  new Vec3(11, 0, 0),
                        new Vec3(3, 0, 6),   new Vec3(0, 15, 0), new Vec3(6, 7, 0)};
    check(occupancy(displaced).size() == occupancy(configuration(server)).size(),
          "The transverse fixture keeps every member volume disjoint");
    setConfiguration(server, displaced);
    for (Vec3 down : DIRECTIONS) {
      var before = configuration(server);
      var action = scenario(before, down, true);
      fixture(context, server, action.json());
      click(context, server, action.rod, action.aim);
      finishMove(context, server, action.rod, down, before);
      var gpu = Objects.requireNonNull(GpuReadback.read(context, "probe"));
      check(new Vec3(gpu.scalar(153), gpu.scalar(154), gpu.scalar(155))
                    .subtract(down)
                    .lengthSqr() < 1e-8,
            "The HUD uses the active signed world gravity axis");
      check(
          gpu.scalar(162) > .2 && gpu.scalar(162) < .85 && gpu.scalar(157) > .07,
          "Distant timber retains contrast and all six identities have distinct colors");
      context.takeScreenshot("manifold-joinery-gravity-" +
                             Arrays.asList(DIRECTIONS).indexOf(down));
      checks.add(Map.of("case", "joinery_transverse_tool", "rod", action.rod, "down",
                        down.toString(), "stand", action.stand.toString()));
      server.runCommand("function manifold:joinery/undo");
      ready(context, server);
      check(Arrays.equals(configuration(server), before),
            "Undo restores every transverse component");
    }
    server.runCommand("function manifold:reset");
    ready(context, server);
    var blocked = scenario(configuration(server), new Vec3(0, -1, 0), false);
    fixture(context, server, blocked.json());
    var before = configuration(server);
    click(context, server, blocked.rod, blocked.aim);
    context.waitTicks(5);
    check(Arrays.equals(configuration(server), before) &&
              value(server, "j.blocker") >= 0,
          "An occupied swept volume rejects the tool event");
    var gpu = Objects.requireNonNull(GpuReadback.read(context, "probe"));
    check(gpu.scalar(134) == value(server, "j.blocker"),
          "Shader feedback and native collision identify the same blocking member");
    checks.add(Map.of("case", "joinery_tool_obstruction", "rod", blocked.rod, "blocker",
                      value(server, "j.blocker")));
  }
  private static void reachAndSupport(ClientGameTestContext context,
                                      TestServerContext server,
                                      List<Map<String, Object>> checks) {
    server.runCommand("function manifold:reset");
    ready(context, server);
    var before = configuration(server);
    context.getInput().holdKey(InputConstants.KEY_LSHIFT);
    context.getInput().lookAt(0, -40);
    context.waitTicks(6);
    var gpu = Objects.requireNonNull(GpuReadback.read(context, "probe"));
    check(gpu.scalar(131) == 0 && gpu.scalar(159) > 70 && gpu.scalar(159) < 80,
          "The tool focuses a repeated timber beyond the native collision window");
    double reach = gpu.scalar(159);
    context.getInput().pressMouse(InputConstants.MOUSE_BUTTON_RIGHT);
    context.waitTicks(1);
    check(value(server, "j.hit") == 0,
          "The logical ray selects the distant visible copy");
    finishMove(context, server, 0, new Vec3(0, -1, 0), before);
    check(value(server, "j.p0y") == 15,
          "Transverse movement wraps through the periodic boundary");
    context.getInput().releaseKey(InputConstants.KEY_LSHIFT);
    context.waitTicks(3);
    checks.add(Map.of("case", "joinery_periodic_tool", "reach", reach, "offset_y", 15,
                      "crouched", true));
    server.runCommand("function manifold:joinery/undo");
    ready(context, server);
    Vec3[] goal = new Vec3[6];
    Arrays.fill(goal, Vec3.ZERO);
    setConfiguration(server, goal);
    var action = new Scenario(0, new Vec3(-1, 0, 0), new Vec3(56.4, 27.5, 31.5),
                              new Vec3(53.5, 27.5, 31.5));
    fixture(context, server, action.json());
    before = configuration(server);
    Vec3 standing = position(server);
    click(context, server, 0, action.aim);
    finishMove(context, server, 0, action.down, before);
    check(Math.abs(wrapped(position(server).subtract(standing)).x + 4) < .05,
          "Moving the support lets the player land on its new surface");
    checks.add(Map.of("case", "joinery_support_descent", "distance", 4));
    server.runCommand("function manifold:joinery/undo");
    ready(context, server);
  }
  private static void layoutRecovery(ClientGameTestContext context,
                                     TestServerContext server,
                                     List<Map<String, Object>> checks) {
    server.runCommand("scoreboard players set #j.layout manifold 0");
    context.waitTicks(2);
    ready(context, server);
    var expected = MODEL.getAsJsonArray("joinery_initial");
    var current = configuration(server);
    for (int i = 0; i < 6; i++) {
      var v = expected.get(i).getAsJsonArray();
      check(current[i].equals(new Vec3(v.get(0).getAsInt(), v.get(1).getAsInt(),
                                       v.get(2).getAsInt())),
            "An unsupported layout initializes the current starting joint");
    }
    check(value(server, "j.layout") == 3 && value(server, "j.steps") == 0 &&
              value(server, "r.complete") == 0 && value(server, "g.blocked") == 0,
          "Layout initialization starts a clear, unsolved assembly session");
    checks.add(Map.of("case", "joinery_layout_initialization", "layout", 3));
  }
  private static void setConfiguration(TestServerContext server, Vec3[] offsets) {
    server.runOnServer(s -> {
      var source = s.createCommandSourceStack();
      s.getCommands().performPrefixedCommand(
          source, "scoreboard players set #h.busy manifold 1");
      s.getCommands().performPrefixedCommand(
          source, "scoreboard players set #h.mode manifold 3");
      s.getCommands().performPrefixedCommand(source, "gamemode spectator @a");
      for (int i = 0; i < 6; i++) {
        double[] xyz = {offsets[i].x, offsets[i].y, offsets[i].z};
        for (int a = 0; a < 3; a++)
          s.getCommands().performPrefixedCommand(
              source, "scoreboard players set #j.p" + i + "xyz".charAt(a) +
                          " manifold " + (int)xyz[a]);
      }
      s.getCommands().performPrefixedCommand(source,
                                             "function manifold:joinery/encode");
      for (int slot = 0; slot < 2; slot++)
        s.getCommands().performPrefixedCommand(
            source, "scoreboard players set #r.region" + slot + " manifold -1");
    });
  }
  private static Set<Cell> exterior(Map<Cell, Integer> cells) {
    var seen = new HashSet<Cell>();
    var queue = new ArrayDeque<Cell>();
    var root = new Cell(0, 0, 0);
    check(!cells.containsKey(root), "The fixture has an exterior air seed");
    seen.add(root);
    queue.add(root);
    while (!queue.isEmpty()) {
      Cell p = queue.removeFirst();
      for (Vec3 d : DIRECTIONS) {
        Cell n = p.moved(d);
        if (!cells.containsKey(n) && seen.add(n))
          queue.addLast(n);
      }
    }
    return seen;
  }
  private static Set<Cell> envelopeCells() {
    var result = new HashSet<Cell>();
    for (var element : MODEL.getAsJsonArray("joinery_envelopes")) {
      var box = element.getAsJsonObject();
      Vec3 lo = vector(box, "lo"), hi = vector(box, "hi");
      for (int x = (int)lo.x / 4; x <= (int)hi.x / 4; x++)
        for (int y = (int)lo.y / 4; y <= (int)hi.y / 4; y++)
          for (int z = (int)lo.z / 4; z <= (int)hi.z / 4; z++)
            result.add(new Cell(x, y, z));
    }
    return result;
  }
  private static void closure(ClientGameTestContext context, TestServerContext server,
                              List<Map<String, Object>> checks) {
    var expected = envelopeCells();
    var counts = server.computeOnServer(s -> {
      int slot = TransportChecks.value(s, "h.slot"),
          frame = TransportChecks.value(s, "g.frame");
      int ox = TransportChecks.value(s, "r.ox" + slot),
          oy = TransportChecks.value(s, "r.oy" + slot),
          oz = TransportChecks.value(s, "r.oz" + slot);
      var basis = FRAMES[frame];
      var world = s.getPlayerList().getPlayers().getFirst().level();
      int missing = 0, extra = 0;
      for (int x = -6; x <= 37; x++)
        for (int y = -6; y <= 37; y++)
          for (int z = -6; z <= 37; z++) {
            boolean filled = expected.contains(new Cell(Math.floorMod(ox + x, 64) / 4,
                                                        Math.floorMod(oy + y, 64) / 4,
                                                        Math.floorMod(oz + z, 64) / 4));
            var p = new BlockPos(
                slot * 80 + (int)(x * basis[0][0] + y * basis[0][1] + z * basis[0][2]),
                200 + (int)(x * basis[1][0] + y * basis[1][1] + z * basis[1][2]),
                (int)(x * basis[2][0] + y * basis[2][1] + z * basis[2][2]));
            boolean solid = !world.getBlockState(p).isAir();
            if (filled && !solid)
              missing++;
            if (!filled && solid)
              extra++;
          }
      return Map.of("missing", missing, "extra", extra, "checked", 44 * 44 * 44);
    });
    check(counts.get("missing") == 0 && counts.get("extra") == 0,
          "Native completed geometry equals its closed timber envelope: " + counts);
    var gpu = Objects.requireNonNull(GpuReadback.read(context, "probe"));
    Vec3 origin = new Vec3(gpu.scalar(0), gpu.scalar(1), gpu.scalar(2));
    double maxError = 0;
    int hits = 0;
    for (int y = 0; y < 18; y++)
      for (int x = 0; x < 32; x++) {
        int pixel = (y + 1) * 256 + x * 8;
        Vec3 ray = new Vec3(gpu.scalar(pixel + 3), gpu.scalar(pixel + 4),
                            gpu.scalar(pixel + 5));
        double predicted = traceEnvelope(origin, ray), actual = gpu.scalar(pixel + 2);
        check((predicted >= 1e6) == (actual >= 1e6),
              "GPU completion rays have the closed silhouette");
        if (predicted < 1e6) {
          maxError = Math.max(maxError, Math.abs(predicted - actual));
          hits++;
        }
      }
    check(hits > 0 && maxError < .08,
          "GPU timber surfaces meet the expected envelope: " + maxError);
    checks.add(Map.of("case", "joinery_closed_joint", "native", counts, "gpu_hits",
                      hits, "maximum_ray_error", maxError, "envelope_modules",
                      expected.size()));
  }
  private static double traceEnvelope(Vec3 origin, Vec3 ray) {
    double[] o = {origin.x, origin.y, origin.z}, d = {ray.x, ray.y, ray.z},
             next = new double[3], delta = new double[3];
    int[] cell = new int[3];
    for (int a = 0; a < 3; a++) {
      cell[a] = (int)Math.floor((o[a] + .5) / 64);
      next[a] = Math.abs(d[a]) < 1e-10
                    ? 1e12
                    : ((cell[a] * 64 + (d[a] > 0 ? 63.5 : -.5)) - o[a]) / d[a];
      delta[a] = Math.abs(d[a]) < 1e-10 ? 1e12 : 64 / Math.abs(d[a]);
    }
    double start = .01;
    for (int step = 0; step < 36 && start <= 650; step++) {
      double end = Math.min(650, Math.min(next[0], Math.min(next[1], next[2]))),
             best = 1e7;
      for (var element : MODEL.getAsJsonArray("joinery_envelopes")) {
        var b = element.getAsJsonObject();
        Vec3 lo = vector(b, "lo"), hi = vector(b, "hi");
        double[] l = {lo.x - .5, lo.y - .5, lo.z - .5},
                 h = {hi.x + .5, hi.y + .5, hi.z + .5};
        double near = start, far = end;
        for (int a = 0; a < 3; a++) {
          double local = o[a] - cell[a] * 64;
          if (Math.abs(d[a]) < 1e-10) {
            if (local < l[a] || local > h[a]) {
              near = 1e7;
              break;
            }
          } else {
            double t0 = (l[a] - local) / d[a], t1 = (h[a] - local) / d[a];
            near = Math.max(near, Math.min(t0, t1));
            far = Math.min(far, Math.max(t0, t1));
          }
        }
        if (near <= far)
          best = Math.min(best, near);
      }
      if (best <= end)
        return best;
      if (end >= 650)
        break;
      for (int a = 0; a < 3; a++)
        if (next[a] <= end + 1e-5) {
          cell[a] += d[a] > 0 ? 1 : -1;
          next[a] += delta[a];
        }
      start = end;
    }
    return 1e7;
  }
  private static void ready(ClientGameTestContext context, TestServerContext server) {
    server.waitFor(s
                   -> TransportChecks.value(s, "h.mode") == 1 &&
                          TransportChecks.value(s, "j.moving") == -1 &&
                          s.getPlayerList().getPlayers().getFirst().onGround(),
                   400);
    context.waitFor(mc
                    -> mc.player != null && !mc.player.isSpectator() &&
                           mc.player.onGround(),
                    200);
    context.waitTicks(5);
  }
  private static Vec3 position(TestServerContext server) {
    return server.computeOnServer(
        s
        -> new Vec3(TransportChecks.value(s, "g.x") / 4096.0,
                    TransportChecks.value(s, "g.y") / 4096.0,
                    TransportChecks.value(s, "g.z") / 4096.0));
  }
  private static Vec3 wrapped(Vec3 p) {
    return new Vec3(p.x - 64 * Math.rint(p.x / 64), p.y - 64 * Math.rint(p.y / 64),
                    p.z - 64 * Math.rint(p.z / 64));
  }
  private static int value(TestServerContext server, String name) {
    return server.computeOnServer(s -> TransportChecks.value(s, name));
  }
  private static JsonObject model() {
    try (var input = JoineryChecks.class.getResourceAsStream("/manifold-build.json")) {
      return JsonParser
          .parseReader(new InputStreamReader(Objects.requireNonNull(input),
                                             StandardCharsets.UTF_8))
          .getAsJsonObject();
    } catch (Exception e) {
      throw new RuntimeException(e);
    }
  }
  private static double[][][] frames() {
    var array = MODEL.getAsJsonArray("frames");
    double[][][] values = new double[array.size()][3][3];
    for (int i = 0; i < array.size(); i++)
      for (int a = 0; a < 3; a++)
        for (int b = 0; b < 3; b++)
          values[i][a][b] = array.get(i)
                                .getAsJsonArray()
                                .get(a)
                                .getAsJsonArray()
                                .get(b)
                                .getAsDouble();
    return values;
  }
  private static void check(boolean value, String message) {
    if (!value)
      throw new AssertionError(message);
  }
}
