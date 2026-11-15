package dev.caimeo.linktiles;

import com.google.gson.GsonBuilder;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Arrays;
import java.util.List;
import java.util.Map;
import net.fabricmc.api.ClientModInitializer;
import net.fabricmc.fabric.api.client.event.lifecycle.v1.ClientTickEvents;
import net.minecraft.client.Minecraft;
import net.minecraft.client.Screenshot;
import net.minecraft.client.gui.screens.TitleScreen;
import net.minecraft.core.registries.Registries;
import net.minecraft.core.UUIDUtil;
import net.minecraft.resources.Identifier;
import net.minecraft.world.Difficulty;
import net.minecraft.world.level.DataPackConfig;
import net.minecraft.world.level.GameType;
import net.minecraft.world.level.LevelSettings;
import net.minecraft.world.level.WorldDataConfiguration;
import net.minecraft.world.level.levelgen.WorldOptions;
import net.minecraft.world.level.levelgen.presets.WorldPresets;
import net.minecraft.world.phys.EntityHitResult;
import net.minecraft.world.phys.Vec3;

/** Dedicated local world setup; gameplay stays in the compiled vanilla datapack. */
public final class PlayClient implements ClientModInitializer {
    private static final String WORLD = "LinkTiles";
    private Object serverIdentity;
    private boolean opened, preparing, ready, checking;
    private int ticks, readyTicks;

    @Override
    public void onInitializeClient() {
        ClientTickEvents.END_CLIENT_TICK.register(this::tick);
    }

    private void tick(Minecraft client) {
        var server = client.getSingleplayerServer();
        if (!opened && client.gui.screen() instanceof TitleScreen && client.gui.overlay() == null) {
            opened = true;
            var flows = client.createWorldOpenFlows();
            if (Files.exists(Path.of("saves", WORLD, "level.dat"))) {
                flows.openWorld(WORLD, () -> client.gui.setScreen(new TitleScreen()));
            } else {
                var data = new WorldDataConfiguration(
                    new DataPackConfig(List.of("vanilla", "file/link-tiles.zip"), List.of()),
                    WorldDataConfiguration.DEFAULT.enabledFeatures());
                var settings = new LevelSettings(WORLD, GameType.ADVENTURE,
                    new LevelSettings.DifficultySettings(Difficulty.PEACEFUL, false, false), true, data);
                flows.createFreshLevel(WORLD, settings, new WorldOptions(42, false, false),
                    registries -> registries.lookupOrThrow(Registries.WORLD_PRESET)
                        .getOrThrow(WorldPresets.FLAT).value().createWorldDimensions(), new TitleScreen());
            }
        }
        if (server == null || client.player == null || !server.getWorldData().getLevelName().equals(WORLD)) return;
        if (serverIdentity != server) {
            serverIdentity = server;
            preparing = ready = checking = false;
            ticks = readyTicks = 0;
        }
        if (!preparing && ++ticks >= 20 && client.gui.screen() == null && client.gui.overlay() == null) {
            preparing = true;
            var uuid = client.player.getUUID();
            server.execute(() -> {
                var player = server.getPlayerList().getPlayer(uuid);
                if (player == null) return;
                server.setWorldAllowCommands(true);
                server.getPlayerList().op(player.nameAndId());
                server.getPlayerList().sendPlayerPermissionLevel(player);
                server.getCommands().sendCommands(player);
                player.setGameMode(GameType.ADVENTURE);
                var source = server.createCommandSourceStack().withSuppressedOutput();
                var game = server.getCommandStorage().get(Identifier.parse("link_tiles:board")).getCompoundOrEmpty("game");
                boolean fresh = game.getIntOr("phase", 0) == 0;
                double x = 0.625, y = 64, z = 0.625;
                if (fresh) {
                    server.getCommands().performPrefixedCommand(source,
                        "fill -4 63 -4 4 63 4 minecraft:smooth_quartz strict");
                    server.getCommands().performPrefixedCommand(source,
                        "fill -4 64 -4 4 67 4 minecraft:air strict");
                    server.getCommands().performPrefixedCommand(source, "time set noon");
                    server.getCommands().performPrefixedCommand(source, "weather clear");
                } else {
                    var origin = game.getListOrEmpty("origin");
                    x = origin.getIntOr(0, -1) + 1.625;
                    y = origin.getIntOr(1, 64);
                    z = origin.getIntOr(2, -1) + 1.625;
                }
                server.getCommands().performPrefixedCommand(source,
                    "tp " + player.getStringUUID() + " " + x + " " + y + " " + z + " 180 90");
                if (fresh) server.getCommands().performPrefixedCommand(
                    source.withEntity(player).withPosition(player.position()), "function link_tiles:new");
                client.execute(() -> {
                    client.options.bobView().set(false);
                    client.options.fov().set(100);
                    client.options.pauseOnLostFocus = false;
                    client.getWindow().setTitle("LinkTiles · aim and right-click matching tiles");
                    ready = true;
                    status("ready", Map.of());
                });
            });
        }
        if (ready && Boolean.getBoolean("linktiles.smoke") && ++readyTicks > 140 && !checking) {
            checking = true;
            int hitId = client.hitResult instanceof EntityHitResult hit ? hit.getEntity().getId() : -1;
            var uuid = client.player.getUUID();
            server.execute(() -> {
                var game = server.getCommandStorage().get(Identifier.parse("link_tiles:board")).getCompoundOrEmpty("game");
                var level = server.overworld();
                var hit = level.getEntity(hitId);
                boolean aimed = hit != null && hit.entityTags().contains("link_tiles.cell") &&
                    hit.entityTags().contains("link_tiles.r4") && hit.entityTags().contains("link_tiles.c4");
                var origin = game.getListOrEmpty("origin");
                double x = origin.getIntOr(0, -1) + 1.625;
                double y = origin.getIntOr(1, 64);
                double z = origin.getIntOr(2, -1) + 1.625;
                boolean aligned = false;
                int count = 0;
                for (var entity : level.getAllEntities()) {
                    if (entity.entityTags().contains("link_tiles.display")) count++;
                    if (entity.entityTags().contains("link_tiles.cell") && entity.entityTags().contains("link_tiles.r4") &&
                        entity.entityTags().contains("link_tiles.c4")) {
                        aligned = entity.getBoundingBox().clip(new Vec3(x, y + 1.62, z), new Vec3(x, y, z)).isPresent();
                    }
                }
                var owner = game.getListOrEmpty("owner");
                int[] stored = {owner.getIntOr(0, 0), owner.getIntOr(1, 0), owner.getIntOr(2, 0), owner.getIntOr(3, 0)};
                boolean owned = Arrays.equals(stored, UUIDUtil.uuidToIntArray(uuid));
                var snapshot = Map.<String, Object>of("phase", game.getIntOr("phase", -1),
                    "remaining", game.getIntOr("remaining", -1), "entities", count, "owned", owned,
                    "crosshairCell", aimed, "hitboxAligned", aligned);
                boolean passed = game.getIntOr("phase", 0) >= 3 && count == 113 && owned && aligned;
                client.execute(() -> {
                    status(passed ? "passed" : "failed", snapshot);
                    Screenshot.grab(client.gameDirectory, "link-tiles.png", client.gameRenderer.mainRenderTarget(), 1,
                        message -> client.execute(client::stop));
                });
            });
        }
    }

    private static void status(String state, Map<String, Object> snapshot) {
        try {
            Files.writeString(Path.of("play-status.json"), new GsonBuilder().setPrettyPrinting().create().toJson(
                Map.of("status", state, "minecraft", "26.3", "world", WORLD,
                    "nativeInput", true, "snapshot", snapshot)));
        } catch (Exception error) { throw new RuntimeException(error); }
    }
}
