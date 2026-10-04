"""Report an autonomous shader message received by the data pack."""

import json


def analyze_ping(report, directory):
    receiver = report.get("receiver", report.get("latest", {}))
    elapsed = receiver.get("elapsed_ms", 0) / 1000
    transfer = receiver.get("transfer_ms", 0) / 1000
    message = receiver.get("message", "")
    bits = len(receiver.get("bits", []))
    summary = {
        "result": report["result"],
        "experiment": "pingpong",
        "status": receiver.get("status"),
        "message": message,
        "bytes": receiver.get("bytes", []),
        "wire_bits": bits,
        "bit_debug_messages": report.get("bit_messages"),
        "character_debug_messages": report.get("character_messages"),
        "crc_verified": receiver.get("status") == "complete"
        and receiver.get("crc_received") == receiver.get("crc_expected"),
        "elapsed_seconds": elapsed,
        "transfer_seconds": transfer,
        "wire_bits_per_second": bits / transfer if transfer else None,
        "payload_bits_per_second_including_calibration": len(message) * 8 / elapsed
        if elapsed
        else None,
        "bit_retries": receiver.get("total_bit_retries"),
        "frame_retries": receiver.get("frame_retries"),
        "tick_rate": receiver.get("tick_rate"),
        "posteffect_active": receiver.get("posteffect_active"),
        "driver": report.get("driver"),
        "gpu_readback": report.get("gpu_readback"),
    }
    (directory / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    print(
        f"Ping-pong {summary['status']}: {message!r}; {bits} bits, {elapsed:.3f}s total, CRC={summary['crc_verified']}"
    )
