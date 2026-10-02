"""Fetch pinned upstream references and a Dense Qwen3 checkpoint."""

if __package__ in (None, ""):
    import sys
    from pathlib import Path

    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from pathlib import Path
import hashlib
import json
import subprocess
import io
import zipfile
import argparse
from urllib.request import urlopen
from huggingface_hub import HfApi, snapshot_download

from scripts.common.paths import ROOT

MODEL_ID = "Qwen/Qwen3-0.6B"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model", help="Hugging Face Dense Qwen3 repository")
    parser.add_argument("--revision", help="Pinned model revision")
    args = parser.parse_args()
    root = ROOT / "vendor/qwen3.c"
    if not (root / ".git").exists():
        subprocess.run(
            ["git", "clone", "https://github.com/adriancable/qwen3.c.git", str(root)],
            check=True,
        )
    commit = subprocess.check_output(
        ["git", "-C", str(root), "rev-parse", "HEAD"], text=True
    ).strip()
    pin = ROOT / "model-source.json"
    previous = json.loads(pin.read_text()) if pin.exists() else {}
    model_id = args.model or previous.get("model", MODEL_ID)
    revision = args.revision or (
        previous.get("revision") if previous.get("model") == model_id else None
    )
    if revision is None:
        revision = HfApi(token=False).model_info(model_id).sha
    if previous.get("model") != model_id or previous.get("revision") != revision:
        pin.write_text(
            json.dumps(
                {
                    "model": model_id,
                    "revision": revision,
                    "reference_repository": "https://github.com/adriancable/qwen3.c",
                    "reference_commit": commit,
                },
                indent=2,
            )
            + "\n"
        )
    print("Reference commit:", commit, "model revision:", revision, flush=True)
    snapshot_download(
        model_id,
        revision=revision,
        token=False,
        local_dir=ROOT / "model",
        allow_patterns=["*.json", "*.safetensors", "*.txt", "LICENSE", "README.md"],
    )
    remote_files = HfApi(token=False).list_repo_files(model_id, revision=revision)
    if "model.safetensors.index.json" not in remote_files:
        (ROOT / "model/model.safetensors.index.json").unlink(missing_ok=True)
    font = ROOT / "model/unifont.hex"
    if not font.exists() or font.stat().st_size < 1_000_000:
        manifest = json.load(
            urlopen("https://piston-meta.mojang.com/mc/game/version_manifest_v2.json")
        )
        entry = next(v for v in manifest["versions"] if v["id"] == "26.3")
        version = json.load(urlopen(entry["url"]))
        index = json.load(urlopen(version["assetIndex"]["url"]))
        resource = index["objects"]["minecraft/font/unifont.zip"]
        sha = resource["hash"]
        data = urlopen(
            "https://resources.download.minecraft.net/" + sha[:2] + "/" + sha
        ).read()
        if hashlib.sha1(data).hexdigest() != sha:
            raise RuntimeError("Font asset checksum mismatch")
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            font.write_bytes(
                archive.read(next(n for n in archive.namelist() if n.endswith(".hex")))
            )
            (ROOT / "model/unifont-LICENSE.txt").write_bytes(
                archive.read("LICENSE.txt")
            )
    files = {
        p.name: {
            "bytes": p.stat().st_size,
            "sha256": hashlib.sha256(p.read_bytes()).hexdigest(),
        }
        for p in (ROOT / "model").iterdir()
        if p.is_file() and p.name != "files.json"
    }
    (ROOT / "model/files.json").write_text(json.dumps(files, indent=2) + "\n")
    print(
        "Model files verified:", [(n, v["bytes"]) for n, v in files.items()], flush=True
    )


if __name__ == "__main__":
    main()
