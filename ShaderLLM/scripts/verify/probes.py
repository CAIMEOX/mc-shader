"""Build native numerical probes from the generated model operators."""

import json
import struct
import zipfile
import zlib
from pathlib import Path
import numpy as np
from scripts.common.paths import ROOT


def png(path, rgba):
    image = np.ascontiguousarray(rgba, dtype=np.uint8)
    h, w = image.shape[:2]

    def chunk(kind, data):
        return (
            struct.pack(">I", len(data))
            + kind
            + data
            + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
        )

    raw = b"".join(b"\0" + row.tobytes() for row in image)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(raw, 1))
        + chunk(b"IEND", b"")
    )


def words(a):
    a = np.asarray(a, dtype=np.uint32)
    return np.stack([(a >> s) & 255 for s in [24, 16, 8, 0]], axis=-1).astype(np.uint8)


def generate(binary, root, tensors, run, material, tokenizer_layout):
    small = root / "sharded"
    layout = json.loads((small / "model/weights.json").read_text())
    # A compact physical texture is assigned a page ID above the signed-int boundary.
    shifted = root / "large-address"
    (shifted / "model/textures").mkdir(parents=True, exist_ok=True)
    meta = json.loads(json.dumps(layout))
    side = 8192
    capacity = side * side
    shift = 33 * capacity
    for matrix in meta["matrices"]:
        matrix["base"] += shift
    raw = np.fromfile(small / "model/weights.rgba", np.uint8).reshape(-1, 4)
    height = (len(raw) + side - 1) // side
    padded = np.zeros((height * side, 4), np.uint8)
    padded[: len(raw)] = raw
    png(shifted / "model/textures/weights_33.png", padded.reshape(height, side, 4))
    meta.update(
        page_width=side,
        page_height=side,
        pages=[
            {
                "file": f"weights_{i}.png",
                "width": side,
                "height": side if i < 33 else height,
            }
            for i in range(34)
        ],
    )
    (shifted / "model/weights.json").write_text(json.dumps(meta))
    tokenizer_layout(shifted / "tokenizer", meta["config"]["vocab_size"])
    run(binary, "pipeline", shifted / "model", ROOT / "shaders", shifted / "pipeline")
    out = root / "probe-pack"
    shader_dir = out / "assets/qwen_probe/shaders"
    texture_dir = out / "assets/qwen_probe/textures/effect"
    effects = out / "assets/qwen_probe/post_effect"
    for d in (shader_dir, texture_dir, effects, shader_dir / "include"):
        d.mkdir(parents=True, exist_ok=True)
    (out / "pack.mcmeta").write_text(
        json.dumps(
            {
                "pack": {
                    "description": "Qwen operator probes",
                    "min_format": [97, 1],
                    "max_format": [97, 1],
                }
            }
        )
    )
    (shader_dir / "include/codec.glsl").write_bytes(
        (ROOT / "shaders/codec.glsl").read_bytes()
    )
    for name in ("model.glsl", "limits.glsl"):
        (shader_dir / "include" / name).write_bytes(
            (small / "pipeline" / name).read_bytes()
        )
    expected = []

    def texture(label, data):
        png(texture_dir / (label + ".png"), data)
        return {
            "location": "qwen_probe:" + label,
            "width": data.shape[1],
            "height": data.shape[0],
            "bilinear": False,
        }

    def scalar_texture(label, data):
        return texture(label, words(np.asarray(data, dtype=np.float32).view(np.uint32)))

    def case(label, model, stage_name, control, inputs, values, indices=None):
        inputs = {
            "Control": texture(
                label + "_control",
                words(np.array(control, np.uint32)).reshape(1, 12, 4),
            ),
            **inputs,
        }
        stage = next(
            p
            for p in json.loads((model / "pipeline/pipeline.json").read_text())[
                "passes"
            ]
            if p["fragment_shader"] == "qwen:" + stage_name
        )
        # Resolve the actual generated weight bindings, including their page IDs.
        for item in stage["inputs"]:
            name = item["sampler_name"]
            if name in inputs:
                continue
            file = item["location"].split(":")[1] + ".png"
            source = model / "model/textures" / file
            if not source.exists():
                source = small / "model/textures" / file
            dest = label + "_" + Path(file).stem
            (texture_dir / (dest + ".png")).write_bytes(source.read_bytes())
            inputs[name] = {
                "location": "qwen_probe:" + dest,
                "width": item["width"],
                "height": item["height"],
                "bilinear": False,
            }
        for kind, extension in [("vertex_shader", "vsh"), ("fragment_shader", "fsh")]:
            src = model / "pipeline" / (stage[kind].split(":")[1] + "." + extension)
            text = src.read_text().replace("<qwen:", "<qwen_probe:")
            (shader_dir / (label + "." + extension)).write_text(text)
        target = json.loads((model / "pipeline/pipeline.json").read_text())["targets"][
            stage["output"]
        ]
        pipeline = {
            "targets": {"result": target},
            "passes": [
                {
                    "vertex_shader": "qwen_probe:" + label,
                    "fragment_shader": "qwen_probe:" + label,
                    "inputs": [{"sampler_name": n, **i} for n, i in inputs.items()],
                    "output": "result",
                }
            ],
        }
        (effects / (label + ".json")).write_text(json.dumps(pipeline))
        flat = np.asarray(values, dtype=np.float32).reshape(-1)
        expected.append(
            {
                "name": label,
                "effect": "qwen_probe:" + label,
                "indices": list(range(len(flat))) if indices is None else indices,
                "values": flat.tolist(),
            }
        )

    c = layout["config"]
    d = c["hidden_size"]
    hd = c["head_dim"]
    heads = c["num_attention_heads"]
    kv = c["num_key_value_heads"] * hd
    control = [0] * 12
    control[0] = 2
    control[4] = c["vocab_size"] - 1
    matrix = next(
        m for m in layout["matrices"] if m["name"] == "model.embed_tokens.weight"
    )
    decoded, _ = material(small / "model", matrix)
    case("embedding_pages", small, "embedding", control, {}, decoded[-1])
    case("embedding_large_address", shifted, "embedding", control, {}, decoded[-1])
    control[0] = 3
    control[2] = 17
    control[3] = 4
    query = (np.arange(heads * hd, dtype=np.float32) % 31 - 15).reshape(heads, hd) / 8
    norm = tensors["model.layers.4.self_attn.q_norm.weight"]
    normalized = (
        query
        / np.sqrt(np.mean(query * query, axis=1, keepdims=True) + c["rms_norm_eps"])
        * norm
    )
    angle = control[2] * np.power(
        c["rope_theta"], -np.arange(hd // 2, dtype=np.float32) / (hd // 2)
    )
    x, y = normalized[:, : hd // 2], normalized[:, hd // 2 :]
    rotated = np.concatenate(
        [x * np.cos(angle) - y * np.sin(angle), x * np.sin(angle) + y * np.cos(angle)],
        axis=1,
    )
    case(
        "rope_config",
        small,
        "layer0_q_rope",
        control,
        {"Input0": scalar_texture("query_rope", query.reshape(1, -1))},
        rotated,
    )
    runtime = json.loads((small / "pipeline/limits.json").read_text())
    width, height = runtime["cache_width"], runtime["cache_height"]
    ctx = runtime["context_size"]
    cache = np.zeros(width * height, np.float32)
    start = (control[3] * ctx + control[2]) * kv
    cache[start : start + kv] = np.arange(kv, dtype=np.float32) + 0.25
    cache_input = scalar_texture("cache_values", cache.reshape(height, width))
    q = np.zeros((heads, hd), np.float32)
    q[:, 0] = 1
    scores = np.repeat(
        np.arange(c["num_key_value_heads"], dtype=np.float32) * hd + 0.25,
        heads // c["num_key_value_heads"],
    ) / np.sqrt(hd)
    case(
        "gqa_scores",
        small,
        "layer0_scores",
        control,
        {
            "Input0": scalar_texture("query_scores", q.reshape(1, -1)),
            "Keys": cache_input,
        },
        scores,
        [h * ctx + control[2] for h in range(heads)],
    )
    probability = np.zeros((heads, ctx), np.float32)
    probability[:, control[2]] = 1
    joined = np.repeat(
        (np.arange(kv, dtype=np.float32) + 0.25).reshape(-1, hd),
        heads // c["num_key_value_heads"],
        axis=0,
    )
    case(
        "gqa_values",
        small,
        "layer0_attention",
        control,
        {"Input0": scalar_texture("probability", probability), "Values": cache_input},
        joined,
    )
    control[0] = 4
    quantized = np.full((d // 64, 17, 4), 128, np.uint8)
    quantized[:, 16] = 0
    quantized[0, 0, 0] = 255
    quantized[0, 16] = words(np.array([1 / 127], np.float32).view(np.uint32))[0]
    head = next(m for m in layout["matrices"] if m["name"] == "lm_head.weight")
    head_values, _ = material(small / "model", head)
    case(
        "independent_head",
        small,
        "logits",
        control,
        {"Input0": texture("head_input", quantized.reshape(1, -1, 4))},
        head_values[:, 0],
    )
    (root / "probes.json").write_text(json.dumps(expected))
    with zipfile.ZipFile(
        ROOT / "build/probes.zip", "w", zipfile.ZIP_DEFLATED, compresslevel=1
    ) as z:
        for p in out.rglob("*"):
            if p.is_file():
                z.write(p, p.relative_to(out))
    return {"native_probes": len(expected), "large_address": shift}
