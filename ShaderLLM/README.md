# Qwen3 in Minecraft

Run Qwen3-0.6B inside Minecraft Java Edition 26.3. A resource pack performs tokenization, language-model inference, and text rendering in GLSL shaders. A data pack supplies prompts through an NBT string, and responses appear in a scrolling text panel.

The project includes a Haskell asset compiler, ready-to-build resource and data packs, and an interactive Fabric playground.

## Requirements

- Minecraft Java Edition **26.3**, provided by the development harness.
- **GHC 9.12.2** and **Cabal** for the asset compiler.
- **Python 3.11+** with `numpy`, `tokenizers`, `huggingface_hub`, and `jinja2`.
- **Java 25**, Git, and a Clang/GCC-compatible C compiler (`cc`) for the harness and reference tests. Set `CC` to select another compiler executable.

The launcher uses `JAVA_HOME` or Java on `PATH`. On macOS, it can also discover Java 25 through `java_home` or Homebrew. Set `JAVA_HOME` to your Java 25 installation if another Java version is the default. The launcher includes Windows and POSIX file locking; native graphics verification currently covers OpenGL and Vulkan on Apple Silicon macOS. Allow several gigabytes of disk space for model weights, Minecraft dependencies, and generated assets.

## Build and run

Run these commands from the directory containing this README to prepare the Python environment and Haskell dependencies:

```sh
python3 -m venv .venv
source .venv/bin/activate
python3 -m pip install numpy tokenizers huggingface_hub jinja2
cabal update
```

On Windows PowerShell, activate the environment with `.venv\Scripts\Activate.ps1` and set Java with `$env:JAVA_HOME = "C:\path\to\jdk-25"`. Use `python` in place of `python3` if that is your interpreter command.

Prepare the Minecraft dependencies and assets once, with network access:

```sh
python3 scripts/build/setup.py
```

The Python launch scripts use Gradle's offline mode after this setup. They respect `GRADLE_USER_HOME`; `QWEN_MINECRAFT_CLIENT` can select an existing Minecraft 26.3 client JAR. From the same directory, download the model, build the packs, run verification, and open the playground:

```sh
python3 scripts/build/fetch.py
python3 scripts/build/prepare.py
python3 scripts/verify/run_tests.py
python3 scripts/run/play.py
```

Use `--backend opengl` or `--backend vulkan` with the verification and play scripts to select a graphics backend. A backend-specific play session requires a successful full test run for that backend.

`fetch.py` downloads the model, tokenizer, font assets, and C reference implementation. `prepare.py` compiles the assets and creates `build/resourcepack.zip` and `build/datapack.zip`. Verification opens a visible Minecraft window and creates the world used by the playground.

After the first successful setup, launch with:

```sh
python3 scripts/run/play.py
```

To rebuild shaders and packs using the existing compiled assets:

```sh
python3 scripts/build/build.py
```

Use `python3 scripts/build/prepare.py --force` after replacing model weights or when a full asset rebuild is needed.

## Send a prompt

In the playground, enter these commands in chat:

```mcfunction
/data modify storage qwen:input prompt set value "What is 2 + 2? Answer briefly."
/data modify storage qwen:input max_tokens set value 256
```

Close chat and press **R** to submit. You can also submit directly:

```mcfunction
/function qwen:submit
```

The playground enables commands automatically. Each submission starts a new response, which scrolls within the text panel as it grows.

| Setting | Limit |
|---|---|
| Prompt text | 128 BMP Unicode characters, including English and Chinese |
| Tokenized prompt | 128 tokens, including the chat template |
| Total context | 1,024 tokens |
| Generated response | 1–256 tokens, controlled by `qwen:input.max_tokens` |

Generation uses Qwen's non-thinking chat template and greedy token selection. It stops at the end-of-sequence token or the configured length limit. Keep prompts short enough to fit both the character and token limits.

## How it works

1. **Pixel transport.** The data pack encodes the prompt in a `text_display` using a custom font. The core text shader writes that data into a small pixel region, which the post-processing shaders can read.
2. **Tokenization.** Shaders normalize Unicode text and apply Qwen's byte-level BPE tokenizer using precompiled lookup textures.
3. **Inference.** Model weights are quantized to INT8 and stored in texture pages. Shader passes perform the Transformer calculations, while persistent render targets hold activations, the KV cache, and generation state across frames.
4. **Text output.** Generated token IDs are decoded into UTF-8 and rendered through a glyph atlas into the on-screen panel.

At build time, Haskell compiles the weights, lookup tables, and fonts, and generates the GLSL programs through `language-glsl`. Python coordinates downloads and packaging. The Fabric harness provides playground controls and automated tests; the model's inference runs in the shader pipeline.

## Verification and performance

Run the complete test suite with:

```sh
python3 scripts/verify/run_tests.py --backend both
```

It checks UTF-8 resource generation, shader generation, checkpoint conversion, tokenization, GPU operators, and complete responses against the C reference implementation. Results are written to `reports/native.json` and `reports/configuration.json`. Backend reports, logs, and screenshots are stored in `reports/inference-opengl/` and `reports/inference-vulkan/`.

To check the pixel transport before downloading model weights, run this after the dependency setup:

```sh
python3 scripts/verify/run_tests.py --transport-only --backend both
```

This builds a small pack using the production font, data pack, and pixel decoder. It verifies Unicode characters, byte boundaries, request-number rollover, empty prompts, and the maximum prompt length. Reports are stored in `reports/transport-opengl/` and `reports/transport-vulkan/`. Use a single `--backend` value on systems that support only one backend.

The harness checks that the required resource packs and shader overrides are active immediately after reload. The playground reports resource-loading failures before accepting a prompt. Windows/NVIDIA graphics still require a native test run on that hardware.

Qwen3-0.6B achieves approximately **6.6 generated tokens per second** on an Apple M3 Max at 1280 × 720 with a 60 FPS cap. The English, Chinese, and 40-token generation fixtures match the C reference. Performance depends on hardware, frame rate, and prompt length.

The exporter also supports larger Dense Qwen3 configurations and sharded safetensors checkpoints. Qwen3-1.7B, 4B, and 8B have configuration and texture-layout coverage; the complete model benchmark uses 0.6B.

## Source layout

| Directory | Contents |
|---|---|
| `codegen/` | Haskell asset compiler and GLSL generation |
| `shaders/` | Tokenization, inference operators, and text rendering |
| `scripts/` | Download, build, verification, and launch commands |
| `harness/` | Fabric playground and Minecraft integration tests |
| `build/` | Generated textures, packs, and reference fixtures |
| `playground/` | Interactive world and launcher logs |

Haskell dependencies are managed by `cabal.project` and `cabal.project.freeze`. For quick compiler checks, run `cabal test shader-semantics resource-encoding`. Python build and launcher checks run with `python3 -m unittest discover -s scripts/tests`. Source formatting uses Ruff, Ormolu, and clang-format through `python3 scripts/dev/format.py`.

## Credits

- [Qwen3](https://huggingface.co/Qwen/Qwen3-0.6B): model weights and tokenizer.
- [qwen3.c](https://github.com/adriancable/qwen3.c): C inference reference.
- [language-glsl](https://github.com/CAIMEOX/language-glsl): GLSL parsing and pretty-printing.
- Unifont assets distributed with Minecraft: text rendering. Asset licenses are included in the generated resource pack's `licenses/` directory.
