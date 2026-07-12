#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import math
import statistics
import sys
from pathlib import Path
from typing import Any


GATES = {
    "warm_locale_switch_ms": 16.0,
    "cold_locale_switch_ms": 100.0,
    "decoded_catalogs_mib": 32.0,
    "catalogs_rollback_incremental_mib": 48.0,
    "rendered_frame_regression_percent": 5.0,
}


def p95(samples: list[float]) -> float:
    return sorted(samples)[math.ceil(0.95 * len(samples)) - 1]


def numbers(value: Any, path: str, count: int, errors: list[str]) -> list[float]:
    if not isinstance(value, list) or len(value) != count:
        errors.append(f"{path} must contain exactly {count} samples")
        return []
    result: list[float] = []
    for index, item in enumerate(value):
        if isinstance(item, bool) or not isinstance(item, (int, float)) or not math.isfinite(item) or item < 0:
            errors.append(f"{path}[{index}] must be a finite non-negative number")
        else:
            result.append(float(item))
    return result


def build_report(data: Any, input_digest: str) -> tuple[dict[str, Any], list[str]]:
    errors: list[str] = []
    if not isinstance(data, dict) or data.get("schema_version") != 1:
        return {}, ["schema_version must be 1"]
    if not isinstance(data.get("environment"), dict) or not data["environment"]:
        errors.append("environment must be a non-empty object")
    runs = data.get("runs")
    if not isinstance(runs, list):
        return {}, errors + ["runs must be an array"]

    p95s: dict[str, list[float]] = {"warm": [], "cold": []}
    seen_ids: set[str] = set()
    for index, run in enumerate(runs):
        path = f"runs[{index}]"
        if not isinstance(run, dict):
            errors.append(f"{path} must be an object")
            continue
        run_id = run.get("id")
        if not isinstance(run_id, str) or not run_id or run_id in seen_ids:
            errors.append(f"{path}.id must be unique and non-empty")
        else:
            seen_ids.add(run_id)
        mode = run.get("mode")
        if mode not in p95s:
            errors.append(f"{path}.mode must be warm or cold")
            continue
        expected = 1000 if mode == "warm" else 100
        if mode == "warm" and run.get("warmed_up") is not True:
            errors.append(f"{path}.warmed_up must be true")
        if mode == "cold":
            if run.get("fresh_sessions") is not True:
                errors.append(f"{path}.fresh_sessions must be true")
            numbers(run.get("catalog_decode_ms"), f"{path}.catalog_decode_ms", 100, errors)
            numbers(run.get("first_gpu_glyph_upload_ms"), f"{path}.first_gpu_glyph_upload_ms", 100, errors)
        samples = numbers(run.get("samples_ms"), f"{path}.samples_ms", expected, errors)
        if len(samples) == expected:
            p95s[mode].append(p95(samples))

    for mode in ("warm", "cold"):
        if len(p95s[mode]) != 5:
            errors.append(f"runs must contain exactly five process-isolated {mode} repetitions")

    memory = data.get("memory")
    frame = data.get("frame")
    if not isinstance(memory, dict):
        errors.append("memory must be an object")
        memory = {}
    if not isinstance(frame, dict):
        errors.append("frame must be an object")
        frame = {}

    def metric(container: dict[str, Any], name: str) -> float:
        value = container.get(name)
        if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value) or value < 0:
            errors.append(f"{name} must be a finite non-negative number")
            return 0.0
        return float(value)

    decoded = metric(memory, "decoded_catalogs_mib")
    rollback = metric(memory, "catalogs_rollback_incremental_mib")
    if memory.get("rollback_checkpoints") != 64:
        errors.append("rollback_checkpoints must equal 64")
    baseline = metric(frame, "baseline_p95_ms")
    candidate = metric(frame, "candidate_p95_ms")
    if baseline == 0:
        errors.append("baseline_p95_ms must be greater than zero")

    if errors:
        return {}, errors
    warm = statistics.median(p95s["warm"])
    cold = statistics.median(p95s["cold"])
    regression = ((candidate / baseline) - 1.0) * 100.0
    values = {
        "warm_locale_switch_ms": warm,
        "cold_locale_switch_ms": cold,
        "decoded_catalogs_mib": decoded,
        "catalogs_rollback_incremental_mib": rollback,
        "rendered_frame_regression_percent": regression,
    }
    metrics = {
        name: {
            "value" if "locale_switch" not in name else "median_run_p95": value,
            "limit": GATES[name],
            "status": "PASS" if value <= GATES[name] else "FAIL",
        }
        for name, value in values.items()
    }
    return {
        "schema_version": 1,
        "input_sha256": input_digest,
        "environment": data["environment"],
        "method": {
            "process_isolated_repetitions": 5,
            "aggregate": "median of run-level nearest-rank p95",
            "warm_samples_per_run": 1000,
            "cold_fresh_sessions_per_run": 100,
        },
        "metrics": metrics,
        "outcome": "PASS" if all(item["status"] == "PASS" for item in metrics.values()) else "FAIL",
    }, []


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate retained Formal 1.0 benchmark samples.")
    parser.add_argument("input", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    try:
        raw = args.input.read_bytes()
        data = json.loads(raw)
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        print(f"error: cannot read benchmark input: {error}", file=sys.stderr)
        return 1
    report, errors = build_report(data, hashlib.sha256(raw).hexdigest())
    if errors:
        for error in errors:
            print(f"error: {error}", file=sys.stderr)
        return 1
    encoded = json.dumps(report, indent=2, sort_keys=True) + "\n"
    if args.output:
        args.output.write_text(encoded, encoding="utf-8")
    else:
        print(encoded, end="")
    return 0 if report["outcome"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
