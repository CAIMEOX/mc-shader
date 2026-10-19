package dev.caimeo.manifold;

import net.minecraft.network.chat.Component;
import net.minecraft.network.chat.contents.KeybindContents;
import net.minecraft.network.chat.contents.TranslatableContents;
import java.util.*;

/** Records client-resolved messages delivered by native commands. */
public final class MessageCapture {
  record Message(String channel, String key, String text, List<String> arguments,
                 List<String> bindings) {}
  private static final List<Message> messages = new ArrayList<>();
  private static boolean enabled;

  public static void record(String channel, Component component) {
    if (!enabled || component.getString().isBlank())
      return;
    String key = component.getContents() instanceof TranslatableContents text
                     ? text.getKey()
                     : "";
    if (channel.equals("chat") && !key.startsWith("manifold."))
      return;
    var bindings = new ArrayList<String>();
    var arguments = new ArrayList<String>();
    if (component.getContents() instanceof TranslatableContents text)
      for (Object arg : text.getArgs()) {
        arguments.add(arg instanceof Component value ? value.getString()
                                                     : String.valueOf(arg));
        if (arg instanceof Component value && value.getContents() instanceof
                                                  KeybindContents binding)
          bindings.add(binding.getName());
      }
    messages.add(new Message(channel, key, component.getString(), arguments, bindings));
  }
  static void start() {
    enabled = true;
    messages.clear();
  }
  static void stop() {
    enabled = false;
    messages.clear();
  }
  static List<Message> take() {
    var result = List.copyOf(messages);
    messages.clear();
    return result;
  }
}
