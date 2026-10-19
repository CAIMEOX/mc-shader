"""Vector-authored HUD sprites and the carpenter's square inventory icon."""

import json
import math

INK = (0.86, 0.83, 0.74)
PAPER = (0.12, 0.15, 0.14)


def clamp(x):
    return min(1.0, max(0.0, x))


def box(x, y, cx, cy, hx, hy, radius=0.0):
    dx, dy = abs(x - cx) - hx + radius, abs(y - cy) - hy + radius
    return math.hypot(max(dx, 0), max(dy, 0)) + min(max(dx, dy), 0) - radius


def segment(x, y, ax, ay, bx, by):
    vx, vy = bx - ax, by - ay
    t = clamp(((x - ax) * vx + (y - ay) * vy) / (vx * vx + vy * vy))
    return math.hypot(x - ax - vx * t, y - ay - vy * t)


def triangle(x, y):
    vertices = ((1.5, 3.5), (7.5, 3.5), (4.5, 7.3))
    distances = [
        segment(x, y, *a, *b) for a, b in zip(vertices, vertices[1:] + vertices[:1])
    ]
    signs = [
        (b[0] - a[0]) * (y - a[1]) - (b[1] - a[1]) * (x - a[0])
        for a, b in zip(vertices, vertices[1:] + vertices[:1])
    ]
    return min(distances) * (-1 if all(s >= 0 for s in signs) else 1)


def heart(x, y):
    return min(
        math.hypot(x - 3.2, y - 3.3) - 1.7,
        math.hypot(x - 5.8, y - 3.3) - 1.7,
        triangle(x, y),
    )


def image(width, height, paint, scale=4):
    pixels = bytearray()
    for y in range(height * scale):
        for x in range(width * scale):
            color, distance, opacity = paint((x + 0.5) / scale, (y + 0.5) / scale)
            alpha = clamp(0.5 - distance * scale) * opacity
            pixels.extend(round(clamp(c) * 255) for c in (*color, alpha))
    return width * scale, height * scale, bytes(pixels)


def health(name):
    color = INK
    if "poisoned" in name:
        color = (0.64, 0.71, 0.45)
    elif "withered" in name:
        color = (0.48, 0.51, 0.47)
    elif "absorbing" in name:
        color = (0.85, 0.71, 0.43)
    elif "frozen" in name:
        color = (0.65, 0.77, 0.78)
    if "blinking" in name:
        color = tuple(min(1, c * 1.1) for c in color)

    def paint(x, y):
        distance = heart(x, y)
        if "container" in name:
            return PAPER, distance - 0.4, 0.60
        if "half" in name:
            distance = max(distance, x - 4.5)
        return color, distance, 0.90

    return image(9, 9, paint)


def food(name):
    def paint(x, y):
        distance = box(x, y, 4.5, 4.5, 1.7, 3.0, 1.5)
        if "empty" in name:
            return PAPER, distance - 0.45, 0.55
        if "half" in name:
            distance = max(distance, x - 4.5)
        return (
            ((0.65, 0.69, 0.47) if "hunger" in name else (0.75, 0.71, 0.59)),
            distance,
            0.78,
        )

    return image(9, 9, paint)


def hotbar(x, y):
    distance = box(x, y, 91, 11, 90.5, 10.5, 2)
    line = abs(distance + 0.7) - 0.25
    return (INK if line < 0 else PAPER), distance, (0.23 if line < 0 else 0.12)


def selection(x, y):
    distance = abs(box(x, y, 12, 12, 10, 10, 2)) - 0.45
    return INK, distance, 0.66


def square(x, y):
    # A walnut stock, satin brass blade, and engraved graduations.
    x, y = 8 + (x - 8) * 0.88 + (y - 8) * 0.48, 8 - (x - 8) * 0.48 + (y - 8) * 0.88
    stock = box(x, y, 5.1, 8.6, 1.5, 5.6, 0.25)
    blade = box(x, y, 9.1, 3.6, 4.0, 0.85, 0.18)
    if stock < blade:
        grain = 0.035 * math.sin(x * 19 + math.sin(y * 0.3))
        color = (0.49 + grain, 0.37 + grain, 0.25 + grain)
    else:
        color = (0.80, 0.73, 0.55)
        if 6.7 < x < 12.6 and abs((x - 7) % 1.2 - 0.6) < 0.08 and y > 3.75:
            color = (0.32, 0.29, 0.21)
    return color, min(stock, blade), 1.0


def assets(vanilla_names, png):
    result = {}
    for path in vanilla_names:
        prefix = "assets/minecraft/textures/gui/sprites/hud/"
        if not path.startswith(prefix) or not path.endswith(".png"):
            continue
        name = path[len(prefix) :]
        if name.startswith("heart/"):
            data = health(name)
        elif name.startswith("food_"):
            data = food(name)
        elif name == "hotbar.png":
            data = image(182, 22, hotbar)
        elif name == "hotbar_selection.png":
            data = image(24, 24, selection)
        elif name.startswith("experience_bar_"):
            progress = "progress" in name
            data = image(
                182,
                5,
                lambda x, y: (
                    INK if progress else PAPER,
                    abs(y - 2.5) - 0.25,
                    0.55 if progress else 0.16,
                ),
            )
        elif name == "crosshair.png":
            data = image(
                15,
                15,
                lambda x, y: (
                    (0.5, 0.5, 0.5),
                    min(segment(x, y, 5, 7.5, 10, 7.5), segment(x, y, 7.5, 5, 7.5, 10))
                    - 0.35,
                    0.8,
                ),
            )
        else:
            continue
        width, height, pixels = data
        result[path] = png(pixels, width, height)
    width, height, pixels = image(16, 16, square)
    result["assets/manifold/textures/item/joinery_tool.png"] = png(
        pixels, width, height
    )
    models = {
        "assets/manifold/models/item/joinery_tool.json": {
            "parent": "minecraft:item/generated",
            "textures": {"layer0": "manifold:item/joinery_tool"},
        },
        "assets/manifold/items/joinery_tool.json": {
            "model": {
                "type": "minecraft:select",
                "property": "minecraft:display_context",
                "cases": [
                    {
                        "when": ["firstperson_righthand", "firstperson_lefthand"],
                        "model": {"type": "minecraft:empty"},
                    }
                ],
                "fallback": {
                    "type": "minecraft:model",
                    "model": "manifold:item/joinery_tool",
                },
            }
        },
    }
    for path, data in models.items():
        result[path] = (json.dumps(data, indent=2) + "\n").encode()
    return result
