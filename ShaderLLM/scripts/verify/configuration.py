"""Verify Config-derived resources, sharded checkpoints and page-local addressing."""

if __package__ in (None, ""):
    import sys
    from pathlib import Path

    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

import json
import math
import struct
import subprocess
from pathlib import Path
import numpy as np
from scripts.build.compile import compiler
from scripts.common.paths import ROOT


def specs(c):
    d, ff, hd = c["hidden_size"], c["intermediate_size"], c["head_dim"]
    q, kv = c["num_attention_heads"] * hd, c["num_key_value_heads"] * hd
    out = {"model.embed_tokens.weight": (c["vocab_size"], d), "model.norm.weight": (d,)}
    for layer in range(c["num_hidden_layers"]):
        prefix = f"model.layers.{layer}."
        for field, shape in {
            "self_attn.q_proj.weight": (q, d),
            "self_attn.k_proj.weight": (kv, d),
            "self_attn.v_proj.weight": (kv, d),
            "self_attn.o_proj.weight": (d, q),
            "mlp.gate_proj.weight": (ff, d),
            "mlp.up_proj.weight": (ff, d),
            "mlp.down_proj.weight": (d, ff),
            "input_layernorm.weight": (d,),
            "post_attention_layernorm.weight": (d,),
            "self_attn.q_norm.weight": (hd,),
            "self_attn.k_norm.weight": (hd,),
        }.items():
            out[prefix + field] = shape
    if not c["tie_word_embeddings"]:
        out["lm_head.weight"] = (c["vocab_size"], d)
    return out


def values(shape, seed):
    if len(shape) == 1:
        return (1 + np.arange(math.prod(shape), dtype=np.float32) / 1024).reshape(shape)
    return ((np.arange(math.prod(shape), dtype=np.float32) + seed) % 129 - 64).reshape(
        shape
    ) / 8


def safetensors(path, tensors):
    header, chunks, offset = {}, [], 0
    for key, array in tensors.items():
        dtype = "BF16" if array.ndim == 2 else "F32"
        raw = (
            (array.view(np.uint32) >> 16).astype("<u2").tobytes()
            if dtype == "BF16"
            else array.astype("<f4").tobytes()
        )
        header[key] = {
            "dtype": dtype,
            "shape": list(array.shape),
            "data_offsets": [offset, offset + len(raw)],
        }
        chunks.append(raw)
        offset += len(raw)
    encoded = json.dumps(header).encode()
    path.write_bytes(struct.pack("<Q", len(encoded)) + encoded + b"".join(chunks))


def fixture(path, c, sharded):
    path.mkdir(parents=True, exist_ok=True)
    (path / "config.json").write_text(json.dumps(c))
    tensors = {
        key: values(shape, i * 7) for i, (key, shape) in enumerate(specs(c).items())
    }
    if sharded:
        mapping = {}
        for index in range(3):
            name = f"model-{index + 1:05}-of-00003.safetensors"
            part = {k: v for i, (k, v) in enumerate(tensors.items()) if i % 3 == index}
            safetensors(path / name, part)
            mapping.update({k: name for k in part})
        (path / "model.safetensors.index.json").write_text(
            json.dumps({"weight_map": mapping})
        )
    else:
        safetensors(path / "model.safetensors", tensors)
    return tensors


def tokenizer_layout(directory, vocab):
    directory.mkdir(parents=True, exist_ok=True)
    value = json.loads((ROOT / "build/tokenizer/tokenizer-layout.json").read_text())
    value["vocab_size"] = vocab
    (directory / "tokenizer-layout.json").write_text(json.dumps(value))


def run(binary, *args, success=True):
    result = subprocess.run(
        [str(binary), *map(str, args)], text=True, capture_output=True
    )
    if success and result.returncode:
        raise AssertionError(result.stdout + result.stderr)
    if not success and not result.returncode:
        raise AssertionError("Invalid checkpoint was accepted")
    return result


def material(output, matrix):
    raw = np.fromfile(output / "weights.rgba", np.uint8).reshape(-1, 4)
    count = matrix["rows"] * matrix["cols"] // 64
    blocks = raw[matrix["base"] : matrix["base"] + count * 17].reshape(count, 17, 4)
    q = blocks[:, :16].reshape(count, 64).astype(np.int16) - 128
    scale = (
        np.ascontiguousarray(blocks[:, 16]).view(">f4").astype(np.float32).reshape(-1)
    )
    return (q * scale[:, None]).reshape(matrix["rows"], matrix["cols"]), scale


def fake_manifest(c, side=8192):
    shapes = specs(c)
    ordered = ["model.embed_tokens.weight"]
    for suffix in [
        "self_attn.q_proj.weight",
        "self_attn.k_proj.weight",
        "self_attn.v_proj.weight",
        "self_attn.o_proj.weight",
        "mlp.gate_proj.weight",
        "mlp.down_proj.weight",
        "mlp.up_proj.weight",
    ]:
        ordered += [f"model.layers.{i}.{suffix}" for i in range(c["num_hidden_layers"])]
    if not c["tie_word_embeddings"]:
        ordered.append("lm_head.weight")
    matrices, offset = [], 0
    for key in ordered:
        rows, cols = shapes[key]
        matrices.append({"name": key, "base": offset, "rows": rows, "cols": cols})
        offset += rows * cols // 64 * 17
    norms, norm_offset = [], 0
    for key, shape in shapes.items():
        if len(shape) == 1:
            norms.append({"name": key, "base": norm_offset, "length": shape[0]})
            norm_offset += shape[0]
    pages = [
        {
            "file": f"weights_{i}.png",
            "width": side,
            "height": min(side, (offset - i * side * side + side - 1) // side),
        }
        for i in range((offset + side * side - 1) // (side * side))
    ]
    return {
        "config": c,
        "page_width": side,
        "page_height": side,
        "pages": pages,
        "matrices": matrices,
        "norms": norms,
        "norm_texture": {
            "width": c["hidden_size"],
            "height": (norm_offset + c["hidden_size"] - 1) // c["hidden_size"],
        },
    }


def check_pipeline(root, c):
    layout = json.loads((root / "model/weights.json").read_text())
    pipeline = json.loads((root / "pipeline/pipeline.json").read_text())
    runtime = json.loads((root / "pipeline/limits.json").read_text())
    n, kv = c["num_hidden_layers"], c["num_key_value_heads"] * c["head_dim"]
    assert runtime["config"] == c
    assert (
        runtime["logical_elements"]["q_proj"]
        == c["num_attention_heads"] * c["head_dim"]
    )
    assert runtime["logical_elements"]["gate"] == c["intermediate_size"]
    assert runtime["logical_elements"]["embedding"] == c["hidden_size"]
    width, height = runtime["cache_width"], runtime["cache_height"]
    assert width % kv == 0 and width * height >= n * runtime["context_size"] * kv
    assert all(
        0 < t.get("width", 1) <= 16384 and 0 < t.get("height", 1) <= 16384
        for t in pipeline["targets"].values()
    )
    for stage in pipeline["passes"]:
        assert stage["output"] not in [i.get("target") for i in stage["inputs"]]
        assert len(stage["inputs"]) <= 16
    head = next(s for s in pipeline["passes"] if s["output"] == "logits")
    head_matrix = next(
        m
        for m in layout["matrices"]
        if m["name"]
        == (
            "model.embed_tokens.weight"
            if c["tie_word_embeddings"]
            else "lm_head.weight"
        )
    )
    first = head_matrix["base"] // (layout["page_width"] * layout["page_height"])
    locations = [i["location"] for i in head["inputs"] if "location" in i]
    assert locations[0] == "qwen:" + Path(layout["pages"][first]["file"]).stem
    return runtime


def main():
    binary = compiler()
    root = ROOT / "build/configuration-tests"
    root.mkdir(parents=True, exist_ok=True)
    base = dict(
        hidden_size=128,
        intermediate_size=384,
        num_hidden_layers=5,
        num_attention_heads=6,
        num_key_value_heads=2,
        head_dim=32,
        vocab_size=513,
        rms_norm_eps=1e-5,
        rope_theta=12345.0,
        tie_word_embeddings=False,
    )
    single = root / "single"
    sharded = root / "sharded"
    tensors = fixture(single / "source", base, False)
    fixture(sharded / "source", base, True)
    for case in (single, sharded):
        run(binary, "weights-page", case / "source", case / "model", 128)
        tokenizer_layout(case / "tokenizer", base["vocab_size"])
        run(binary, "pipeline", case / "model", ROOT / "shaders", case / "pipeline")
        check_pipeline(case, base)
    a = np.fromfile(single / "model/weights.rgba", ">u4")
    b = np.fromfile(sharded / "model/weights.rgba", ">u4")
    np.testing.assert_array_equal(a, b)
    compiled = json.loads((sharded / "model/weights.json").read_text())
    for matrix in compiled["matrices"]:
        decoded, scale = material(sharded / "model", matrix)
        bound = np.repeat(scale / 2 + 1e-5, 64).reshape(decoded.shape)
        assert np.all(np.abs(decoded - tensors[matrix["name"]]) <= bound)
    assert len(compiled["pages"]) > 16
    shared = root / "shared"
    tied = {**base, "tie_word_embeddings": True}
    fixture(shared / "source", tied, True)
    run(binary, "weights-page", shared / "source", shared / "model", 128)
    tokenizer_layout(shared / "tokenizer", tied["vocab_size"])
    run(binary, "pipeline", shared / "model", ROOT / "shaders", shared / "pipeline")
    check_pipeline(shared, tied)
    assert not any(
        m["name"] == "lm_head.weight"
        for m in json.loads((shared / "model/weights.json").read_text())["matrices"]
    )
    with (shared / "model/reference.bin").open("rb") as stream:
        stream.seek(40)
        assert struct.unpack("<i", stream.read(4))[0] == 1
    with (sharded / "model/reference.bin").open("rb") as stream:
        stream.seek(40)
        assert struct.unpack("<i", stream.read(4))[0] == 0
    # A malformed index must fail before producing weight resources.
    index = sharded / "source/model.safetensors.index.json"
    saved = index.read_text()
    value = json.loads(saved)
    value["weight_map"]["model.embed_tokens.weight"] = "missing.safetensors"
    index.write_text(json.dumps(value))
    run(
        binary, "weights-page", sharded / "source", root / "invalid", 128, success=False
    )
    index.write_text(saved)
    profiles = []
    for label, hidden, ff, layers, heads, tie in [
        ("1.7B", 2048, 6144, 28, 16, True),
        ("4B", 2560, 9728, 36, 32, True),
        ("8B", 4096, 12288, 36, 32, False),
    ]:
        c = {
            **base,
            "hidden_size": hidden,
            "intermediate_size": ff,
            "num_hidden_layers": layers,
            "num_attention_heads": heads,
            "num_key_value_heads": 8,
            "head_dim": 128,
            "vocab_size": 151936,
            "rms_norm_eps": 1e-6,
            "rope_theta": 1000000.0,
            "tie_word_embeddings": tie,
        }
        case = root / label
        (case / "model").mkdir(parents=True, exist_ok=True)
        (case / "model/weights.json").write_text(json.dumps(fake_manifest(c)))
        tokenizer_layout(case / "tokenizer", c["vocab_size"])
        run(binary, "pipeline", case / "model", ROOT / "shaders", case / "pipeline")
        runtime = check_pipeline(case, c)
        profiles.append(
            {
                "model": label,
                "cache_extent": [runtime["cache_width"], runtime["cache_height"]],
                "max_weight_pages": max(map(len, runtime["weight_windows"].values())),
            }
        )
    from scripts.verify.probes import generate

    probes = generate(binary, root, tensors, run, material, tokenizer_layout)
    report = {
        "shards": 3,
        "partition_equivalence": True,
        "tied_and_untied_heads": True,
        "small_model_pages": len(compiled["pages"]),
        "profiles": profiles,
        **probes,
    }
    (ROOT / "reports/configuration.json").write_text(
        json.dumps(report, indent=2) + "\n"
    )
    print(report)


if __name__ == "__main__":
    main()
