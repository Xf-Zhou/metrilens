#!/usr/bin/env python3
import hashlib
import json
import os
import platform
import select
import signal
import statistics
import subprocess
import sys
import time
import uuid
from pathlib import Path

from measure_lightweight import capture_power_observation, validate_power_environment

REPO = Path(__file__).resolve().parent.parent
EXECUTABLE = REPO / ".build/DerivedData/Build/Products/Release/Metrilens.app/Contents/MacOS/Metrilens"
RUNS = 20
TIMEOUT_SECONDS = 2.0
PROTOCOL_VERSION = 6


def repository_identity() -> tuple[str, Path]:
    status = subprocess.check_output(
        ["git", "-C", str(REPO), "status", "--porcelain"], text=True
    ).strip()
    if status:
        raise RuntimeError("performance gate requires a clean worktree")
    commit = subprocess.check_output(
        ["git", "-C", str(REPO), "rev-parse", "HEAD"], text=True
    ).strip()
    return commit, Path("/tmp/metrilens-perf") / commit


def executable_sha256() -> str:
    digest = hashlib.sha256()
    with EXECUTABLE.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def measurement_identity(commit: str) -> dict:
    return {
        "protocol_version": PROTOCOL_VERSION,
        "commit": commit,
        "executable_sha256": executable_sha256(),
        "machine_model": subprocess.check_output(
            ["sysctl", "-n", "hw.model"], text=True
        ).strip(),
        "architecture": platform.machine(),
        "macos_version": platform.mac_ver()[0],
    }


def ensure_no_existing_instance() -> None:
    try:
        result = subprocess.run(
            ["pgrep", "-x", "Metrilens"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
    except OSError as error:
        raise RuntimeError(f"pgrep unavailable: {error}") from error
    if result.returncode == 0:
        raise RuntimeError("A Metrilens process is already running")
    if result.returncode != 1:
        raise RuntimeError(f"pgrep failed with exit code {result.returncode}")


def terminate_exact_process(pid: int) -> None:
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    deadline = time.monotonic() + 1
    while time.monotonic() < deadline:
        finished, _ = os.waitpid(pid, os.WNOHANG)
        if finished == pid:
            return
        time.sleep(0.01)
    os.kill(pid, signal.SIGKILL)
    os.waitpid(pid, 0)


def run_once() -> float:
    ensure_no_existing_instance()
    read_fd, write_fd = os.pipe()
    os.set_inheritable(write_fd, True)
    token = f"METRILENS_READY_{uuid.uuid4().hex}"
    environment = os.environ.copy()
    environment["METRILENS_PERF_READY_FD"] = str(write_fd)
    environment["METRILENS_PERF_READY_TOKEN"] = token
    started = time.monotonic_ns()
    pid = os.posix_spawn(str(EXECUTABLE), [str(EXECUTABLE)], environment)
    os.close(write_fd)
    try:
        ready, _, _ = select.select([read_fd], [], [], TIMEOUT_SECONDS)
        if not ready:
            raise TimeoutError("ready token timed out")
        payload = os.read(read_fd, 4096).decode("utf-8").strip()
        finished = time.monotonic_ns()
        if payload != token:
            raise RuntimeError(f"unexpected ready token: {payload!r}")
        child, status = os.waitpid(pid, os.WNOHANG)
        if child == pid:
            raise RuntimeError(f"child exited before measurement completed: {status}")
        return (finished - started) / 1_000_000
    finally:
        os.close(read_fd)
        terminate_exact_process(pid)


def main() -> int:
    if not EXECUTABLE.is_file():
        print(f"Release executable not found: {EXECUTABLE}", file=sys.stderr)
        return 2
    commit, output_dir = repository_identity()
    started = time.monotonic()
    host_power_at_start = capture_power_observation(
        "standard",
        "launch-start",
        0,
    )
    power_observations = []
    samples = []
    for index in range(RUNS):
        power_observations.append(
            capture_power_observation(
                "standard",
                f"run-{index + 1}-before",
                time.monotonic() - started,
            )
        )
        samples.append(run_once())
        power_observations.append(
            capture_power_observation(
                "standard",
                f"run-{index + 1}-after",
                time.monotonic() - started,
            )
        )
    host_power_at_end = capture_power_observation(
        "standard",
        "launch-end",
        time.monotonic() - started,
    )
    validate_power_environment(host_power_at_end, "standard", "launch end")
    median_ms = statistics.median(samples)
    summary = {
        "metric": "new-process-to-status-item-ready",
        "cache_policy": "system-caches-allowed",
        "runs": RUNS,
        "samples_ms": samples,
        "median_ms": median_ms,
        "threshold_ms": 300,
        "passed": median_ms <= 300,
        "identity": measurement_identity(commit),
        "host_power_at_start": host_power_at_start,
        "host_power_at_end": host_power_at_end,
        "power_observations": power_observations,
    }
    output_dir.mkdir(parents=True, exist_ok=True)
    (output_dir / "launch.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    return 0 if summary["passed"] else 1


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, subprocess.CalledProcessError) as error:
        print(f"performance infrastructure error: {error}", file=sys.stderr)
        raise SystemExit(2)
