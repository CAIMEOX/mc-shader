# Timing-channel protocol

The data pack and shader exchange requests and responses through two different
observables. Requests use pixels written by core shaders; responses use the
timing of ordinary client replies. The receiver operates on command-visible
game state.

## Requests and GPU work

An `item_display` carries an integer color through `custom_model_data`. Its core
shader writes a marker and the request word into two corner pixels. The post
effect decodes them, retains the request in a persistent render target, and
repairs the visible corner.

In message mode, the request identifies a bit, a calibration mode, and a workload
power. The shader reads the requested bit from its compiled frame and selects
light or heavy GPU work. The data pack keeps the request steady while measuring.

## Rotation observation

The data pack adds an equivalent whole turn to the player's yaw. The server
stores an unwrapped angle; a subsequent client reply restores the normalized
representation. Scheduled functions observe the transition with `/stopwatch`
and server tick counts. Completing a measurement compensates the accumulated
whole turns.

The probe guards headings within 0.01 degrees of zero because float rounding can
remove the marker. Replies transiently clear server-side `OnGround`. Ordinary
movement updates can also clear a marker, so measurements may contain short
reply bursts and scheduling noise.

## Message frame

| Field | Size | Meaning |
|---|---:|---|
| Length | 1 byte | Payload length, 1–64 characters |
| Payload | Length bytes | Printable ASCII |
| CRC | 1 byte | CRC-8 over length and payload |

Bits are sent most significant first. CRC uses polynomial `0x07`, initial value
`0`, and no reflection or final XOR. EOF requires the declared payload length and
a matching CRC. The default frame is:

```text
0E 68 69 20 66 72 6F 6D 20 73 68 61 64 65 72 70
```

This contains 14 characters (`hi from shader`) and 128 transmitted bits including
length and CRC. The message is compiled into
`assets/signal/shaders/include/message.glsl`; the data pack supplies generic ASCII
and CRC tables.

## Message receiver

Sixteen known light/heavy windows calibrate the decoder. Each payload request has
a 100 ms settling interval followed by a 500 ms measurement window. Ambiguous
observations retry the current bit up to three times. Invalid lengths,
non-printable bytes, and CRC failures allow up to two frame restarts with
recalibration. The session timeout is ten minutes.

`signal:ping` command storage exposes:

| Field | Meaning |
|---|---|
| `status` | `idle`, `starting`, `calibrating`, `receiving`, `complete`, `error`, or `cancelled` |
| `bits`, `bytes`, `chars` | Accepted bits, frame bytes, and assembled payload |
| `length` | Declared payload length |
| `crc_expected`, `crc_received` | CRC verification state |
| `elapsed_ms`, `transfer_ms` | Session and payload timing |
| `total_bit_retries`, `frame_retries` | Recovery counts |

The receiver prints bits and completed characters in chat. EOF prints the
assembled message and removes the effect and carrier. See the
[message verification commands](experiments.md#message-reception).

## Autonomous frame streams

The frame sender stores its index in a persistent render target. A request selects
low/high workload powers, a test pattern, stream mode, and restart epoch. The
shader emits eight warmup frames, a long delimiter, 64 data frames, and a closing
delimiter. Each data frame advances the index once.

The receiver merges updates fewer than four server ticks apart into a burst and
classifies intervals between burst starts. Calibration chooses workload levels
near 60 and 100 ms and supplies data and delimiter thresholds. The closing
delimiter ends reception. The raw-stream experiments expose received bits in
`signal:rstream bits` or `signal:fall bits` and publish the latest bit to the
player's `signal.rx` scoreboard.

`Signal.Stream` generates common framing resources. `Signal.RotateStream` supplies
the yaw sampler, and `Signal.Fall` supplies the Y-position sampler. The native
runner requests each stream once, then polls the data-pack result. GPU checks
occur before and after sampling.

The raw streams exercise consecutive equal bits and transitions independently
of the message receiver's length/CRC framing. Higher GPU workloads reduce frame
rate, and tick counts do not represent a perfectly uniform wall clock. Accuracy,
missing symbols, extra symbols, and throughput are measured separately in the
[frame experiments](experiments.md#rotation-frame-stream).
