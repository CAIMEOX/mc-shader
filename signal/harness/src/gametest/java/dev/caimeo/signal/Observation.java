package dev.caimeo.signal;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentLinkedQueue;

/** Read-only timestamps; observations never control packets or rendering. */
public final class Observation {
  public enum Stream { FRAME, SENT, ARRIVED, HANDLED, SERVER_TICK }
  private static final class Window {
    final long start = System.nanoTime();
    final List<ConcurrentLinkedQueue<Long>> events = new ArrayList<>();
    Window() {
      for (var stream : Stream.values())
        events.add(new ConcurrentLinkedQueue<>());
    }
  }
  private static volatile Window active;

  public static void record(Stream stream) {
    var window = active;
    if (window != null)
      window.events.get(stream.ordinal()).add(System.nanoTime());
  }

  public static void begin() {
    active = new Window();
  }

  public static Map<String, Object> finish() {
    long end = System.nanoTime();
    var window = active;
    active = null;
    var out = new LinkedHashMap<String, Object>();
    out.put("duration_ms", (end - window.start) / 1e6);
    for (var stream : Stream.values()) {
      out.put(stream.name().toLowerCase(), window.events.get(stream.ordinal())
                                               .stream()
                                               .filter(n -> n <= end)
                                               .map(n -> (n - window.start) / 1e6)
                                               .toList());
    }
    return out;
  }
}
