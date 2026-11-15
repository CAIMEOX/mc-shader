package linktiles.integration;

import com.mojang.authlib.GameProfile;
import io.netty.channel.embedded.EmbeddedChannel;
import java.util.*;
import net.minecraft.core.BlockPos;
import net.minecraft.core.registries.Registries;
import net.minecraft.gametest.framework.GameTestHelper;
import net.minecraft.gametest.framework.TestFunctionLoader;
import net.minecraft.network.Connection;
import net.minecraft.network.protocol.PacketFlow;
import net.minecraft.network.protocol.game.ServerboundInteractPacket;
import net.minecraft.network.protocol.game.ServerboundPlayerLoadedPacket;
import net.minecraft.resources.Identifier;
import net.minecraft.resources.ResourceKey;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.server.network.CommonListenerCookie;
import net.minecraft.world.entity.Entity;
import net.minecraft.world.entity.Interaction;
import net.minecraft.world.InteractionHand;
import net.minecraft.world.phys.Vec3;
import net.minecraft.nbt.*;
import net.minecraft.commands.Commands;
import net.minecraft.commands.execution.ExecutionContext;
import net.minecraft.world.scores.ScoreHolder;
import net.minecraft.server.commands.data.EntityDataAccessor;
import net.minecraft.network.chat.ComponentSerialization;
import net.minecraft.resources.RegistryOps;

/** Real event criteria exercise the generated input decoder and final datapack. */
public final class Acceptance {
    private static int buildTickMax, clickTickMax;
    public static void main(String[] args) throws Exception {
        TestFunctionLoader.registerLoader(registrar -> registrar.accept(
            ResourceKey.create(Registries.TEST_FUNCTION, Identifier.parse("link_tiles_test:game")), Acceptance::run));
        net.minecraft.gametest.Main.main(args);
    }

    private static ServerPlayer join(GameTestHelper t, String name) {
        var server = t.getLevel().getServer();
        var profile = new GameProfile(UUID.randomUUID(), name);
        var cookie = CommonListenerCookie.createInitial(profile, false);
        var p = new ServerPlayer(server, t.getLevel(), profile, cookie.clientInformation());
        var connection = new Connection(PacketFlow.SERVERBOUND);
        new EmbeddedChannel(connection);
        server.getPlayerList().placeNewPlayer(connection, p, cookie);
        p.connection.handleAcceptPlayerLoad(new ServerboundPlayerLoadedPacket());
        var pos = t.absolutePos(new BlockPos(2, 1, 2));
        p.setPos(pos.getX() + 0.5, pos.getY(), pos.getZ() + 0.5);
        return p;
    }

    private static void command(GameTestHelper t, ServerPlayer p, String text) {
        var server = t.getLevel().getServer();
        server.getCommands().performPrefixedCommand(
            server.createCommandSourceStack().withEntity(p).withPosition(p.position()).withSuppressedOutput(), text);
    }

    private static void server(GameTestHelper t, String text) {
        t.getLevel().getServer().getCommands().performPrefixedCommand(
            t.getLevel().getServer().createCommandSourceStack().withSuppressedOutput(), text);
    }

    private static net.minecraft.nbt.CompoundTag state(GameTestHelper t) {
        return t.getLevel().getServer().getCommandStorage().get(Identifier.parse("link_tiles:board"))
            .getCompoundOrEmpty("game");
    }

    private static Interaction cell(GameTestHelper t, int r, int c) {
        for (Entity e : t.getLevel().getAllEntities()) {
            if (e instanceof Interaction i && e.entityTags().contains("link_tiles.cell") &&
                e.entityTags().contains("link_tiles.r" + r) && e.entityTags().contains("link_tiles.c" + c)) return i;
        }
        throw new AssertionError("missing cell " + r + "," + c);
    }

    private static Entity display(GameTestHelper t, String tag) {
        for (Entity e : t.getLevel().getAllEntities()) if (e.entityTags().contains(tag) &&
            !e.entityTags().contains("link_tiles.cell")) return e;
        throw new AssertionError("missing display " + tag);
    }

    private static void rows(GameTestHelper t) {
        int[] tiles = values(state(t), "tiles");
        for (int r = 0; r < 10; r++) {
            var data = new EntityDataAccessor(display(t, "link_tiles.r" + r)).getData();
            var component = ComponentSerialization.CODEC.parse(
                RegistryOps.create(NbtOps.INSTANCE, t.getLevel().registryAccess()), data.get("text")).getOrThrow();
            var expected = new StringBuilder("|");
            for (int c = 0; c < 10; c++) {
                int n = tiles[(r + 1) * 12 + c + 1];
                expected.append(n == 0 ? "    " : String.format(Locale.ROOT, "%02d ", n));
            }
            t.assertTrue(component.getString().equals(expected.append('|').toString()),
                "native row text agrees with saved tiles, including width-preserving blanks");
        }
    }

    private static void beams(GameTestHelper t) {
        int[] points = values(state(t), "route");
        for (int i = 0; i < points.length - 1; i++) {
            var data = new EntityDataAccessor(display(t, "link_tiles.beam" + i)).getData();
            t.assertTrue(data.get("block_state").toString().contains("minecraft:gold_block"), "route bar has its material");
            var transform = data.getCompoundOrEmpty("transformation");
            var translation = transform.getListOrEmpty("translation");
            var scale = transform.getListOrEmpty("scale");
            int a = points[i], b = points[i + 1];
            double x = (Math.min(a % 12, b % 12) - 1) * 0.25 + 0.125;
            double z = (Math.min(a / 12, b / 12) - 1) * 0.25 + 0.125;
            double w = Math.abs(a % 12 - b % 12) * 0.25 + 0.03125;
            double h = Math.abs(a / 12 - b / 12) * 0.25 + 0.03125;
            t.assertTrue(Math.abs(translation.getFloatOr(0, -999) - x) < 0.00001 &&
                Math.abs(translation.getFloatOr(2, -999) - z) < 0.00001, "route translation matches grid corners");
            t.assertTrue(Math.abs(scale.getFloatOr(0, -1) - w) < 0.00001 &&
                Math.abs(scale.getFloatOr(2, -1) - h) < 0.00001, "route scale matches exact axis-aligned segments");
        }
    }

    private static void event(ServerPlayer p, Interaction cell) {
        p.setPos(cell.getX(), cell.getY() + 0.5, cell.getZ());
        p.connection.handleInteract(new ServerboundInteractPacket(cell.getId(), InteractionHand.MAIN_HAND,
            new Vec3(0, 0.02, 0), false));
    }

    private static void tick(GameTestHelper t) { server(t, "function link_tiles:tick"); }

    private static int remaining(ExecutionContext<?> context) {
        try {
            var field = ExecutionContext.class.getDeclaredField("commandQuota");
            field.setAccessible(true);
            return field.getInt(context);
        } catch (ReflectiveOperationException e) { throw new AssertionError(e); }
    }

    private static int measure(GameTestHelper t, Runnable action) {
        ExecutionContext<?>[] observed = {null};
        int[] initial = {0};
        Commands.executeCommandInContext(t.getLevel().getServer().createCommandSourceStack(), context -> {
            observed[0] = context;
            initial[0] = remaining(context);
            action.run();
        });
        return initial[0] - remaining(observed[0]);
    }

    private static int[] values(CompoundTag tag, String name) {
        var list = tag.getListOrEmpty(name);
        int[] result = new int[list.size()];
        for (int i = 0; i < result.length; i++) result[i] = list.getIntOr(i, -1);
        return result;
    }

    private static int neighbor(int p, int d) {
        return switch (d) {
            case 0 -> p % 12 == 0 ? -1 : p - 1;
            case 1 -> p % 12 == 11 ? -1 : p + 1;
            case 2 -> p < 12 ? -1 : p - 12;
            default -> p >= 132 ? -1 : p + 12;
        };
    }

    private static int nearest(int[] tiles, int p, int d) {
        for (int q = neighbor(p, d); q >= 0; q = neighbor(q, d)) if (tiles[q] != 0) return q;
        return -1;
    }

    // Independent direction/turn search, without segment indices or nearest-obstacle caches.
    private static boolean reachable(int[] tiles, int a, int b, int maxTurns) {
        if (a == b || tiles[a] == 0 || tiles[a] != tiles[b]) return false;
        var queue = new ArrayDeque<int[]>();
        int[][] turns = new int[144][4];
        for (var row : turns) Arrays.fill(row, maxTurns + 1);
        for (int d = 0; d < 4; d++) { turns[a][d] = 0; queue.add(new int[]{a, d, 0}); }
        while (!queue.isEmpty()) {
            var current = queue.remove();
            for (int d = 0; d < 4; d++) {
                int n = current[2] + (d == current[1] ? 0 : 1), q = neighbor(current[0], d);
                if (q < 0 || n > maxTurns) continue;
                if (q == b) return true;
                if (tiles[q] == 0 && turns[q][d] > n) {
                    turns[q][d] = n;
                    queue.add(new int[]{q, d, n});
                }
            }
        }
        return false;
    }

    // The public save format is checked against a complete reconstruction after each turn.
    private static void index(GameTestHelper t) {
        var saved = state(t);
        int[] tiles = values(saved, "tiles");
        t.assertTrue(tiles.length == 144, "save contains the playable cells and outer ring");
        String[] directions = {"left", "right", "up", "down"};
        for (int d = 0; d < 4; d++) {
            int[] actual = values(saved, directions[d]);
            for (int p = 0; p < 144; p++)
                t.assertTrue(actual[p] == nearest(tiles, p, d), "nearest obstacle " + directions[d] + " at " + p);
        }
        var expected = new HashMap<Integer, int[]>();
        int[][] owners = new int[2][144];
        for (var row : owners) Arrays.fill(row, -1);
        for (int axis = 0; axis < 2; axis++) for (int line = 0; line < 12; line++) {
            int n = 0;
            while (n < 12) {
                int p = axis == 0 ? line * 12 + n : n * 12 + line;
                if (tiles[p] != 0) { n++; continue; }
                int id = p * 2 + axis;
                var visible = new HashSet<Integer>();
                while (n < 12 && tiles[p] == 0) {
                    owners[axis][p] = id;
                    for (int d = 0; d < 4; d++) {
                        int q = nearest(tiles, p, d);
                        if (q >= 0) visible.add(q);
                    }
                    n++;
                    if (n < 12) p = axis == 0 ? line * 12 + n : n * 12 + line;
                }
                int[] histogram = new int[26];
                for (int q : visible) histogram[tiles[q]]++;
                expected.put(id, histogram);
            }
        }
        int good = 0;
        var segments = saved.getListOrEmpty("segments");
        for (int s = 0; s < 288; s++) {
            var actual = segments.getCompoundOrEmpty(s);
            var counts = expected.get(s);
            t.assertTrue((actual.getIntOr("active", 0) == 1) == (counts != null), "active segment " + s);
            if (counts == null) continue;
            t.assertTrue(Arrays.equals(counts, values(actual, "counts")), "distinct endpoint histogram " + s);
            int dup = (int) Arrays.stream(counts).filter(v -> v >= 2).count();
            t.assertTrue(dup == actual.getIntOr("duplicates", -1), "duplicate-color count " + s);
            if (dup > 0) good++;
        }
        for (int axis = 0; axis < 2; axis++) {
            int[] actual = values(saved, axis == 0 ? "horizontal" : "vertical");
            for (int p = 0; p < 144; p++) if (tiles[p] == 0)
                t.assertTrue(actual[p] == owners[axis][p], "empty-cell segment owner " + p);
        }
        int adjacent = 0, remaining = 0;
        boolean hasMove = false;
        for (int a = 0; a < 144; a++) if (tiles[a] != 0) {
            remaining++;
            for (int d : new int[]{1, 3}) {
                int b = neighbor(a, d);
                if (b >= 0 && tiles[a] == tiles[b]) adjacent++;
            }
            for (int b = a + 1; b < 144; b++)
                if (tiles[a] == tiles[b] && reachable(tiles, a, b, 2)) hasMove = true;
        }
        t.assertTrue(good == saved.getIntOr("good", -1), "global good-segment count");
        t.assertTrue(adjacent == saved.getIntOr("adjacent", -1), "global adjacency count");
        t.assertTrue(remaining == saved.getIntOr("remaining", -1), "remaining tile count");
        t.assertTrue(hasMove == (good + adjacent > 0), "indexed existence agrees with independent search");
    }

    private static void settle(GameTestHelper t) {
        for (int i = 0; i < 76 && state(t).getIntOr("phase", 0) < 3; i++)
            buildTickMax = Math.max(buildTickMax, measure(t, () -> tick(t)));
        t.assertTrue(state(t).getIntOr("phase", -1) >= 3, "bounded construction finishes");
        index(t);
    }

    private static void click(GameTestHelper t, ServerPlayer p, int tile) {
        event(p, cell(t, tile / 12 - 1, tile % 12 - 1));
        clickTickMax = Math.max(clickTickMax, measure(t, () -> tick(t)));
        var runtime = t.getLevel().getServer().getCommandStorage().get(Identifier.parse("link_tiles:runtime"));
        t.assertFalse(runtime.contains("arena") || runtime.contains("stack"), "turn releases its arena and frames");
    }

    private static void certificate(GameTestHelper t) {
        int[] tiles = values(state(t), "tiles").clone(), solution = values(state(t), "solution");
        t.assertTrue(solution.length == state(t).getIntOr("remaining", -1), "certificate covers every live tile");
        for (int i = 0; i < solution.length; i += 2) {
            int a = solution[i], b = solution[i + 1];
            t.assertTrue(reachable(tiles, a, b, 2), "certificate step " + i / 2 + " is a legal pair");
            tiles[a] = tiles[b] = 0;
        }
        t.assertTrue(Arrays.stream(tiles).allMatch(v -> v == 0), "certificate clears the entire position");
    }

    private static void fixture(GameTestHelper t, int[] tiles) {
        var root = t.getLevel().getServer().getCommandStorage().get(Identifier.parse("link_tiles:board")).copy();
        var game = root.getCompoundOrEmpty("game");
        var list = new ListTag();
        for (int n : tiles) list.add(IntTag.valueOf(n));
        game.put("tiles", list);
        game.putInt("remaining", (int) Arrays.stream(tiles).filter(n -> n != 0).count());
        root.put("game", game);
        t.getLevel().getServer().getCommandStorage().set(Identifier.parse("link_tiles:board"), root);
        server(t, "function link_tiles:rebuild");
        for (int i = 0; i < 24; i++) server(t, "function link_tiles:index-step");
        index(t);
    }

    private static void arguments(GameTestHelper t, int a, int b) {
        server(t, "scoreboard players set #test link.a " + a);
        server(t, "scoreboard players set #test link.b " + b);
    }

    private static boolean query(GameTestHelper t, int a, int b) {
        arguments(t, a, b);
        server(t, "function link_tiles:query");
        var board = t.getLevel().getScoreboard();
        return board.getPlayerScoreInfo(ScoreHolder.forNameOnly("#test"), board.getObjective("link.ok")).value() != 0;
    }

    private static void path(GameTestHelper t, int[] tiles, int a, int b) {
        boolean expected = reachable(tiles, a, b, 2), actual = query(t, a, b);
        t.assertTrue(actual == expected, "compiled route matches independent search for " + a + "," + b);
        if (!actual) return;
        int[] points = values(state(t), "route");
        t.assertTrue(points.length >= 2 && points.length <= 4 && points[0] == a && points[points.length - 1] == b,
            "a route retains endpoints and at most two bends");
        for (int i = 1; i < points.length; i++) {
            int p = points[i - 1], q = points[i];
            t.assertTrue(p / 12 == q / 12 || p % 12 == q % 12, "route segments are axis-aligned");
            int d = p / 12 == q / 12 ? (p < q ? 1 : -1) : (p < q ? 12 : -12);
            for (int j = p + d; j != q; j += d) t.assertTrue(tiles[j] == 0, "route does not cross occupied cells");
            if (i < points.length - 1) t.assertTrue(tiles[q] == 0, "bend is empty");
        }
    }

    private static void geometricCases(GameTestHelper t, ServerPlayer owner) {
        for (String objective : new String[]{"link.a", "link.b", "link.ok"})
            server(t, "scoreboard objectives add " + objective + " dummy");
        int[] single = new int[144]; single[65] = 1;
        fixture(t, single);
        t.assertTrue(state(t).getIntOr("phase", -1) == 5, "one tile cannot count twice on the same segment");
        int[] outside = new int[144]; outside[13] = outside[15] = 1; outside[14] = 2;
        fixture(t, outside);
        path(t, outside, 13, 15);
        t.assertTrue(values(state(t), "route").length == 4, "blocked straight route uses the empty outside ring");
        var random = new Random(20261115);
        boolean threeTurns = false;
        int queries = 1;
        for (int board = 0; board < 10; board++) {
            int[] tiles = new int[144];
            var live = new ArrayList<Integer>();
            for (int r = 1; r <= 10; r++) for (int c = 1; c <= 10; c++) {
                if (random.nextDouble() < 0.48) { int p = r * 12 + c; tiles[p] = 1; live.add(p); }
            }
            fixture(t, tiles);
            for (int k = 0; k < 40; k++) {
                int a = live.get(random.nextInt(live.size())), b = live.get(random.nextInt(live.size()));
                path(t, tiles, a, b); queries++;
                if (a != b && !reachable(tiles, a, b, 2) && reachable(tiles, a, b, 3)) threeTurns = true;
            }
        }
        t.assertTrue(threeTurns, "the fixture includes a pair that requires three bends and is rejected");
        var labels = new ArrayList<Integer>();
        for (int i = 1; i <= 8; i++) { labels.add(i); labels.add(i); }
        int[] stuck = null;
        for (int attempt = 0; attempt < 5000 && stuck == null; attempt++) {
            Collections.shuffle(labels, random);
            int[] tiles = new int[144];
            for (int i = 0; i < 16; i++) tiles[(i / 4 + 4) * 12 + i % 4 + 4] = labels.get(i);
            boolean found = false;
            for (int a = 0; a < 144; a++) if (tiles[a] != 0) for (int b = a + 1; b < 144; b++)
                if (tiles[a] == tiles[b] && reachable(tiles, a, b, 2)) found = true;
            if (!found) stuck = tiles;
        }
        t.assertTrue(stuck != null, "independent search constructs an even-multiplicity dead position");
        fixture(t, stuck);
        t.assertTrue(state(t).getIntOr("phase", -1) == 5, "dead position is reported as stuck");
        command(t, owner, "function link_tiles:reshuffle");
        settle(t);
        t.assertTrue(state(t).getIntOr("phase", -1) == 3, "reshuffle recovers a stuck game");
        certificate(t);
        System.out.println("LINK_TILES " + queries + " compiled routing queries, including outside/three-bend cases, passed");
    }

    private static void costs(GameTestHelper t, ServerPlayer owner) {
        command(t, owner, "function link_tiles:replay"); settle(t);
        int idle = measure(t, () -> tick(t));
        int[] solution = values(state(t), "solution");
        arguments(t, solution[0], solution[1]);
        int deleted = measure(t, () -> server(t, "function link_tiles:erase-pair"));
        index(t);
        int rebuilt = measure(t, () -> server(t, "function link_tiles:rebuild"));
        for (int i = 0; i < 24; i++) rebuilt += measure(t, () -> server(t, "function link_tiles:index-step"));
        index(t);
        t.assertTrue(deleted < rebuilt, "incremental deletion costs less than rebuilding on the same resulting board");
        System.out.println("LINK_TILES_COST delete-pair=" + deleted + " rebuild-same-board=" + rebuilt +
            " max-building-tick=" + buildTickMax + " max-click-tick=" + clickTickMax + " idle-tick=" + idle);
    }

    private static void run(GameTestHelper t) {
        var owner = join(t, "LinkPlayer");
        var spectator = join(t, "LinkSpectator");
        command(t, owner, "function link_tiles:seeded");
        int entities = 0;
        for (Entity e : t.getLevel().getAllEntities()) if (e.entityTags().contains("link_tiles.display")) entities++;
        t.assertTrue(entities == 113, "100 hitboxes, 10 text rows and three route bars exist; got " + entities);
        var position = owner.position();
        owner.setPos(position.x + 1000, position.y, position.z);
        int[] anchor = values(state(t), "origin");
        for (int i = 0; i < 4; i++) tick(t);
        t.assertTrue(state(t).getIntOr("cursor", -1) == 0, "construction pauses while the owner is away");
        command(t, owner, "function link_tiles:new");
        command(t, owner, "function link_tiles:release");
        t.assertTrue(state(t).getIntOr("phase", -1) == 1 && Arrays.equals(anchor, values(state(t), "origin")),
            "an anchored table is neither relocated nor abandoned from an unloaded area");
        owner.setPos(position);
        settle(t);
        t.assertTrue(state(t).getIntOr("phase", -1) == 3, "a seeded 10 by 10 board becomes playable");
        rows(t);
        event(owner, cell(t, 2, 6));
        event(owner, cell(t, 5, 8));
        tick(t);
        t.assertTrue(state(t).getIntOr("selected", -1) == 3 * 12 + 7,
            "one native event supplies both coordinates; later clicks wait for receipt consumption");
        event(spectator, cell(t, 5, 8));
        tick(t);
        t.assertTrue(state(t).getIntOr("selected", -1) == 43, "spectators cannot mutate another player's table");
        index(t);
        certificate(t);
        click(t, owner, 43);
        int[] initial = values(state(t), "initial");
        int[] solution = values(state(t), "solution");
        for (int i = 0; i < solution.length; i += 2) {
            click(t, owner, solution[i]);
            click(t, owner, solution[i + 1]);
            t.assertTrue(state(t).getIntOr("remaining", -1) == 98 - i, "two accepted clicks remove exactly one pair");
            index(t);
            if (i % 20 == 0) { rows(t); beams(t); }
        }
        t.assertTrue(state(t).getIntOr("phase", -1) == 4, "clearing the certificate wins the game");
        click(t, owner, solution[0]);
        t.assertTrue(state(t).getIntOr("moves", -1) == 50, "a won board ignores further tile clicks");
        command(t, owner, "function link_tiles:replay");
        settle(t);
        t.assertTrue(Arrays.equals(initial, values(state(t), "tiles")), "same seed replays the exact initial deal");
        int[] before = values(state(t), "tiles");
        command(t, owner, "function link_tiles:hint");
        var hint = state(t);
        t.assertTrue(reachable(before, hint.getIntOr("hintA", -1), hint.getIntOr("hintB", -1), 2),
            "an index witness produces a legal, non-mutating hint");
        t.assertTrue(Arrays.equals(before, values(hint, "tiles")), "hint preserves tiles");
        beams(t);
        solution = values(state(t), "solution");
        click(t, owner, solution[0]);
        click(t, owner, solution[1]);
        before = values(state(t), "tiles");
        command(t, owner, "function link_tiles:reshuffle");
        settle(t);
        int[] after = values(state(t), "tiles");
        for (int i = 0; i < 144; i++) t.assertTrue((before[i] == 0) == (after[i] == 0), "reshuffle preserves empty cells");
        Arrays.sort(before); Arrays.sort(after);
        t.assertTrue(Arrays.equals(before, after), "reshuffle preserves the remaining multiset");
        certificate(t);
        geometricCases(t, owner);
        costs(t, owner);
        var saved = state(t).copy();
        server(t, "function link_tiles:__oria/load");
        t.assertTrue(saved.equals(state(t)), "matching-schema load preserves the game and incremental indices");
        System.out.println("LINK_TILES input, certificate clear, 50 incremental updates, hint, replay and reshuffle passed");
        t.succeed();
    }
}
