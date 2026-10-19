package dev.caimeo.manifold;

import net.fabricmc.fabric.api.client.gametest.v1.context.TestServerContext;
import java.nio.file.*;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.util.Set;
import java.util.stream.Collectors;

/** Captures Minecraft's function trace for one controller tick in a known phase. */
final class TickTrace {
  static void capture(TestServerContext server, String phase) {
    capture(server, phase, "manifold:tick");
  }

  static void capture(TestServerContext server, String phase, String function) {
    server.runOnServer(s -> {
      try {
        Path directory = Path.of("debug");
        Files.createDirectories(directory);
        s.getCommands().performPrefixedCommand(
            s.createCommandSourceStack(),
            "execute as @a[limit=1] at @s run debug function " + function);
        Path latest = null;
        for (Path candidate : files(directory))
          if (latest == null || Files.getLastModifiedTime(candidate).compareTo(
                                    Files.getLastModifiedTime(latest)) > 0)
            latest = candidate;
        if (latest == null)
          throw new AssertionError("Minecraft emits a function trace for " + phase);
        Files.copy(latest, Path.of("manifold-tick-" + phase + ".txt"),
                   StandardCopyOption.REPLACE_EXISTING);
      } catch (IOException error) {
        throw new UncheckedIOException(error);
      }
    });
  }

  private static Set<Path> files(Path directory) throws IOException {
    try (var files = Files.list(directory)) {
      return files.filter(Files::isRegularFile).collect(Collectors.toSet());
    }
  }
}
