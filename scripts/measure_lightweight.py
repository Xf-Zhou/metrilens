#!/usr/bin/env python3
import argparse
import hashlib
import json
import math
import os
import platform
import re
import select
import signal
import statistics
import subprocess
import sys
import threading
import time
import uuid
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
APP = REPO / ".build/DerivedData/Build/Products/Release/Metrilens.app"
EXECUTABLE = APP / "Contents/MacOS/Metrilens"
WARMUP_SECONDS = 60
MEASUREMENT_SECONDS = 600
STANDARD_RUNS = 3
LOW_POWER_RUNS = 1
LAUNCH_RUNS = 20
PROTOCOL_VERSION = 6
RUNTIME_MONITOR_INTERVAL_SECONDS = 0.1
RUNTIME_MONITOR_TARGET_INTERVAL_SECONDS = 0.095
RESOURCE_SAMPLE_INTERVAL_SECONDS = 5
DISK_MONITOR_STARTUP_WAIT_SECONDS = 0.5
DISK_MONITOR_DURATION_SECONDS = MEASUREMENT_SECONDS + 2
MEASUREMENT_DURATION_TOLERANCE_SECONDS = 5
DISK_MONITOR_PREPARATION_SECONDS = DISK_MONITOR_STARTUP_WAIT_SECONDS + 0.5
WINDOW_ALIGNMENT_TOLERANCE_SECONDS = 0.1
WRITE_OPERATION = re.compile(
    r"\b(WrData|WrMeta|fsync|fdatasync|rename|unlink|mkdir|rmdir|truncate)\b",
    re.IGNORECASE,
)
NETWORK_FILE = re.compile(r"\sIPv[46]\s")


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


def current_app_size_kib() -> int:
    return int(subprocess.check_output(["du", "-sk", str(APP)], text=True).split()[0])


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
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


def load_result(path: Path, name: str) -> dict:
    if not path.is_file():
        raise RuntimeError(f"missing performance result: {name}")
    return json.loads(path.read_text(encoding="utf-8"))


def validate_result_identity(result: dict, expected: dict, name: str) -> None:
    if result.get("identity") != expected:
        raise RuntimeError(f"{name} result does not match the current binary and host")


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
        raise RuntimeError("another Metrilens instance is already running")
    if result.returncode != 1:
        raise RuntimeError(f"pgrep failed with exit code {result.returncode}")


def parse_power_environment(battery_output: str, custom_output: str) -> dict:
    source_match = re.search(r"Now drawing from '([^']+)'", battery_output)
    if not source_match:
        raise RuntimeError("cannot determine current power source")
    source = source_match.group(1)
    if source not in {"AC Power", "Battery Power"}:
        raise RuntimeError(f"unsupported power source: {source}")

    active_section = None
    low_power_value = None
    for line in custom_output.splitlines():
        section_match = re.match(r"^(AC Power|Battery Power):\s*$", line)
        if section_match:
            active_section = section_match.group(1)
            continue
        if active_section == source:
            low_power_match = re.match(r"^\s*lowpowermode\s+(\d+)\s*$", line)
            if low_power_match:
                low_power_value = low_power_match.group(1)
                break
    if low_power_value is None:
        raise RuntimeError(f"cannot determine low-power mode for {source}")
    return {
        "power_source": source,
        "low_power_mode_enabled": low_power_value != "0",
    }


def current_power_environment() -> dict:
    battery_output = subprocess.check_output(["pmset", "-g", "batt"], text=True)
    custom_output = subprocess.check_output(["pmset", "-g", "custom"], text=True)
    return parse_power_environment(battery_output, custom_output)


def validate_power_environment(power: dict, scenario: str, source: str) -> None:
    if not isinstance(power, dict):
        raise RuntimeError(f"{source} returned an invalid power environment")
    expected_low_power = scenario == "low-power"
    if power.get("power_source") != "AC Power":
        raise RuntimeError(f"{source} requires AC Power")
    if power.get("low_power_mode_enabled") is not expected_low_power:
        expected = "enabled" if expected_low_power else "disabled"
        raise RuntimeError(f"{source} requires low-power mode to be {expected}")


def capture_power_observation(
    scenario: str,
    phase: str,
    elapsed_seconds: float,
    power_provider=current_power_environment,
) -> dict:
    power = power_provider()
    validate_power_environment(power, scenario, phase)
    return {
        "phase": phase,
        "elapsed_seconds": elapsed_seconds,
        **power,
    }


def wait_until(
    deadline: float,
    clock=time.monotonic,
    sleeper=time.sleep,
) -> float:
    remaining = deadline - clock()
    if remaining > 0:
        sleeper(remaining)
    return clock()


def validate_host_for_scenario(scenario: str) -> dict:
    if platform.machine() != "arm64":
        raise RuntimeError(f"performance gate requires arm64, got {platform.machine()}")
    power = current_power_environment()
    validate_power_environment(power, scenario, f"{scenario} scenario")
    return power


def terminate(pid: int) -> None:
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    try:
        os.waitpid(pid, 0)
    except ChildProcessError:
        pass


def inspect_child_processes(
    pid: int,
    runner=subprocess.run,
) -> tuple[str | None, str | None]:
    try:
        children = runner(
            ["pgrep", "-P", str(pid)],
            capture_output=True,
            text=True,
            check=False,
        )
    except OSError as error:
        return None, f"pgrep unavailable: {error}"
    if children.returncode not in (0, 1):
        return None, f"pgrep failed with exit code {children.returncode}"
    if children.returncode == 0:
        child_pids = children.stdout.strip()
        if not child_pids:
            return None, "pgrep returned success without a child PID"
        return f"child-process:{child_pids}", None
    return None, None


def inspect_network_activity(
    pid: int,
    runner=subprocess.run,
) -> tuple[str | None, str | None]:
    try:
        files = runner(
            ["lsof", "-nP", "-a", "-p", str(pid)],
            capture_output=True,
            text=True,
            check=False,
        )
    except OSError as error:
        return None, f"lsof unavailable: {error}"
    if files.returncode != 0:
        return None, f"lsof failed with exit code {files.returncode}"
    if NETWORK_FILE.search(files.stdout):
        return "network-socket", None
    return None, None


def monitor_at_fixed_interval(
    name: str,
    check,
    stop: threading.Event,
    violations: list[str],
    errors: list[str],
    interval: float = RUNTIME_MONITOR_INTERVAL_SECONDS,
    target_interval: float = RUNTIME_MONITOR_TARGET_INTERVAL_SECONDS,
    clock=time.monotonic,
) -> None:
    next_planned_start = clock()
    last_actual_start = None
    while not stop.is_set():
        actual_start = clock()
        if (
            last_actual_start is not None
            and actual_start - last_actual_start > interval
        ):
            errors.append(
                f"{name} monitor exceeded its {interval * 1_000:.0f} ms cadence"
            )
            stop.set()
            return
        last_actual_start = actual_start
        try:
            violation, error = check()
        except Exception as error:
            errors.append(f"unexpected {name} monitor failure: {error}")
            stop.set()
            return
        if error:
            errors.append(error)
            stop.set()
            return
        if violation:
            violations.append(violation)
            stop.set()
            return
        next_planned_start += target_interval
        remaining = next_planned_start - clock()
        if remaining > 0 and stop.wait(remaining):
            return


def start_runtime_monitors(
    pid: int,
    stop: threading.Event,
    violations: list[str],
    errors: list[str],
) -> list[threading.Thread]:
    checks = (
        ("child-process", lambda: inspect_child_processes(pid)),
        ("network", lambda: inspect_network_activity(pid)),
    )
    watchers = [
        threading.Thread(
            target=monitor_at_fixed_interval,
            args=(name, check, stop, violations, errors),
            daemon=True,
        )
        for name, check in checks
    ]
    for watcher in watchers:
        watcher.start()
    return watchers


def start_disk_monitor(
    pid: int,
    log_path: Path,
    clock=time.monotonic,
) -> tuple[subprocess.Popen, object, float]:
    stream = log_path.open("wb")
    process = subprocess.Popen(
        [
            "sudo",
            "-n",
            "fs_usage",
            "-w",
            "-f",
            "filesys",
            "-t",
            str(DISK_MONITOR_DURATION_SECONDS),
            str(pid),
        ],
        stdout=stream,
        stderr=subprocess.STDOUT,
    )
    time.sleep(DISK_MONITOR_STARTUP_WAIT_SECONDS)
    if process.poll() is not None:
        stream.close()
        raise RuntimeError(
            "fs_usage exited before measurement; run `sudo -v` before the performance gate"
        )
    return process, stream, clock()


def verify_disk_monitor_coverage(
    process: subprocess.Popen,
    required_end: float,
    clock=time.monotonic,
) -> float:
    verified_at = clock()
    if verified_at < required_end:
        raise RuntimeError("fs_usage coverage was checked before measurement ended")
    if process.poll() is not None:
        raise RuntimeError("fs_usage exited before the measurement window ended")
    return verified_at


def finish_disk_monitor(
    process: subprocess.Popen,
    stream: object,
    log_path: Path,
) -> list[str]:
    try:
        process.wait(timeout=10)
    except subprocess.TimeoutExpired:
        process.terminate()
        process.wait(timeout=5)
    finally:
        stream.close()
    if process.returncode != 0:
        raise RuntimeError(f"fs_usage failed with exit code {process.returncode}")
    return read_disk_write_violations(log_path)


def read_disk_write_violations(log_path: Path) -> list[str]:
    if not log_path.is_file():
        raise RuntimeError(f"missing fs_usage log: {log_path.name}")
    lines = log_path.read_text(errors="replace").splitlines()
    return [line for line in lines if WRITE_OPERATION.search(line)]


def validate_runtime_context(context: dict, scenario: str) -> None:
    expected_low_power = scenario == "low-power"
    expected_interval = 5 if expected_low_power else 1
    if context.get("primaryMetric") != "cpu":
        raise RuntimeError(f"unexpected primary metric: {context}")
    if context.get("configuredInterval") != 1:
        raise RuntimeError(f"unexpected configured interval: {context}")
    if context.get("effectiveInterval") != expected_interval:
        raise RuntimeError(f"unexpected effective interval: {context}")
    if context.get("lowPowerModeEnabled") is not expected_low_power:
        raise RuntimeError(f"power mode changed during measurement: {context}")
    if context.get("powerSource") != "AC Power":
        raise RuntimeError(f"{scenario} scenario lost AC power: {context}")


def validate_summary_power(summary: dict, scenario: str) -> None:
    expected_runs = STANDARD_RUNS if scenario == "standard" else LOW_POWER_RUNS
    for key in ("host_power_at_start", "host_power_at_end"):
        power = summary.get(key)
        if not isinstance(power, dict):
            raise RuntimeError(f"{scenario} result is missing {key}")
        validate_power_environment(power, scenario, f"{scenario} result {key}")
    runs = summary.get("runs")
    if not isinstance(runs, list) or len(runs) != expected_runs:
        raise RuntimeError(
            f"{scenario} result must contain exactly {expected_runs} run(s)"
        )
    for run in runs:
        validate_runtime_context(run.get("runtime_start", {}), scenario)
        validate_runtime_context(run.get("runtime_end", {}), scenario)
        observations = run.get("power_observations")
        if not isinstance(observations, list) or not observations:
            raise RuntimeError(f"{scenario} run is missing power observations")
        phases = {
            observation.get("phase")
            for observation in observations
            if isinstance(observation, dict)
        }
        required_phases = {
            "before-launch",
            "after-warmup",
            "measurement-sample",
            "after-measurement",
        }
        if not required_phases.issubset(phases):
            raise RuntimeError(f"{scenario} run has incomplete power observations")
        for observation in observations:
            if not isinstance(observation, dict):
                raise RuntimeError(f"{scenario} run has an invalid power observation")
            validate_power_environment(
                observation,
                scenario,
                f"{scenario} run {run.get('run')} {observation.get('phase')}",
            )


def validate_launch_power(result: dict) -> None:
    for key in ("host_power_at_start", "host_power_at_end"):
        power = result.get(key)
        if not isinstance(power, dict):
            raise RuntimeError(f"launch result is missing {key}")
        validate_power_environment(power, "standard", f"launch result {key}")
    runs = result.get("runs")
    observations = result.get("power_observations")
    if not isinstance(runs, int) or runs <= 0:
        raise RuntimeError("launch result has an invalid run count")
    if not isinstance(observations, list) or len(observations) != runs * 2:
        raise RuntimeError("launch result is missing per-run power observations")
    for observation in observations:
        if not isinstance(observation, dict):
            raise RuntimeError("launch result has an invalid power observation")
        validate_power_environment(
            observation,
            "standard",
            f"launch {observation.get('phase')}",
        )


def require_finite_number(value, name: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise RuntimeError(f"{name} must be a number")
    number = float(value)
    if not math.isfinite(number):
        raise RuntimeError(f"{name} must be finite")
    return number


def require_matching_number(actual, expected: float, name: str) -> None:
    number = require_finite_number(actual, name)
    if not math.isclose(number, expected, rel_tol=1e-9, abs_tol=1e-9):
        raise RuntimeError(f"{name} does not match its raw data")


def validate_task_power_window_alignment(
    report: dict,
    requested_start: float,
    resource_started: float,
    resource_ended: float,
    scenario: str,
) -> tuple[float, float]:
    boundaries = {
        name: require_finite_number(
            report.get(name),
            f"{scenario} task-power {name}",
        )
        for name in (
            "startReadBeganAtUptime",
            "startReadEndedAtUptime",
            "endReadBeganAtUptime",
            "endReadEndedAtUptime",
        )
    }
    start_began = boundaries["startReadBeganAtUptime"]
    start_ended = boundaries["startReadEndedAtUptime"]
    end_began = boundaries["endReadBeganAtUptime"]
    end_ended = boundaries["endReadEndedAtUptime"]
    if (
        start_ended < start_began
        or end_ended < end_began
        or start_ended - start_began > WINDOW_ALIGNMENT_TOLERANCE_SECONDS
        or end_ended - end_began > WINDOW_ALIGNMENT_TOLERANCE_SECONDS
    ):
        raise RuntimeError(
            f"{scenario} task-power snapshot read interval is invalid"
        )

    requested_end = requested_start + MEASUREMENT_SECONDS
    if (
        any(
            abs(boundary - expected) > WINDOW_ALIGNMENT_TOLERANCE_SECONDS
            for boundary in (start_began, start_ended)
            for expected in (requested_start, resource_started)
        )
        or any(
            abs(boundary - expected) > WINDOW_ALIGNMENT_TOLERANCE_SECONDS
            for boundary in (end_began, end_ended)
            for expected in (requested_end, resource_ended)
        )
    ):
        raise RuntimeError(
            f"{scenario} task-power and resource measurement windows are not aligned"
        )

    started = require_finite_number(
        report.get("startedAtUptime"),
        f"{scenario} task-power start uptime",
    )
    ended = require_finite_number(
        report.get("endedAtUptime"),
        f"{scenario} task-power end uptime",
    )
    require_matching_number(
        started,
        (start_began + start_ended) / 2,
        f"{scenario} task-power start uptime",
    )
    require_matching_number(
        ended,
        (end_began + end_ended) / 2,
        f"{scenario} task-power end uptime",
    )
    return started, ended


def validate_task_power_report(report: dict, run: dict, scenario: str) -> None:
    if report.get("version") != 3:
        raise RuntimeError(f"{scenario} task-power report has the wrong version")
    if report.get("processID") != run.get("process_id"):
        raise RuntimeError(f"{scenario} task-power report has the wrong process ID")
    if not isinstance(report.get("launchToken"), str) or not report["launchToken"]:
        raise RuntimeError(f"{scenario} task-power report is missing its launch token")

    requested = require_finite_number(
        report.get("requestedStartUptime"),
        f"{scenario} task-power requested start uptime",
    )
    resource_requested = require_finite_number(
        run.get("requested_measurement_start_uptime"),
        f"{scenario} resource requested start uptime",
    )
    if not math.isclose(requested, resource_requested, rel_tol=0, abs_tol=1e-6):
        raise RuntimeError(f"{scenario} task-power shared start uptime does not match")
    started = require_finite_number(
        report.get("startedAtUptime"),
        f"{scenario} task-power start uptime",
    )
    ended = require_finite_number(
        report.get("endedAtUptime"),
        f"{scenario} task-power end uptime",
    )
    elapsed = ended - started
    if not (
        MEASUREMENT_SECONDS
        <= elapsed
        <= MEASUREMENT_SECONDS + MEASUREMENT_DURATION_TOLERANCE_SECONDS
    ):
        raise RuntimeError(f"{scenario} task-power report duration is invalid")
    resource_started = require_finite_number(
        run.get("measurement_started_at_uptime"),
        f"{scenario} resource measurement start uptime",
    )
    resource_ended = require_finite_number(
        run.get("measurement_ended_at_uptime"),
        f"{scenario} resource measurement end uptime",
    )
    validate_task_power_window_alignment(
        report,
        requested,
        resource_started,
        resource_ended,
        scenario,
    )
    external_elapsed = require_finite_number(
        run.get("measurement_elapsed_seconds"),
        f"{scenario} external measurement duration",
    )
    if abs(elapsed - external_elapsed) > MEASUREMENT_DURATION_TOLERANCE_SECONDS:
        raise RuntimeError(
            f"{scenario} task-power and resource measurement durations do not match"
        )
    snapshots = {}
    for name in ("start", "end"):
        snapshot = report.get(name)
        if not isinstance(snapshot, dict):
            raise RuntimeError(f"{scenario} task-power report is missing {name}")
        counters = {}
        for counter in (
            "interruptWakeups",
            "platformIdleWakeups",
            "timerWakeupsBin1",
            "timerWakeupsBin2",
        ):
            value = snapshot.get(counter)
            if isinstance(value, bool) or not isinstance(value, int) or value < 0:
                raise RuntimeError(
                    f"{scenario} task-power {name}.{counter} is invalid"
                )
            counters[counter] = value
        snapshots[name] = counters
    if snapshots["end"]["interruptWakeups"] < snapshots["start"]["interruptWakeups"]:
        raise RuntimeError(f"{scenario} task-power interrupt counter went backwards")
    expected_rate = (
        snapshots["end"]["interruptWakeups"]
        - snapshots["start"]["interruptWakeups"]
    ) / elapsed
    require_matching_number(
        report.get("interruptWakeupsPerSecond"),
        expected_rate,
        f"{scenario} task-power wakeups rate",
    )
    require_matching_number(
        run.get("wakeups_per_second"),
        expected_rate,
        f"{scenario} run wakeups rate",
    )
    validate_runtime_context(report.get("startContext", {}), scenario)
    validate_runtime_context(report.get("endContext", {}), scenario)
    if run.get("runtime_start") != report.get("startContext"):
        raise RuntimeError(f"{scenario} run start context does not match raw report")
    if run.get("runtime_end") != report.get("endContext"):
        raise RuntimeError(f"{scenario} run end context does not match raw report")


def validate_run_integrity(
    run: dict,
    scenario: str,
    index: int,
    output_dir: Path,
) -> None:
    if run.get("scenario") != scenario or run.get("run") != index:
        raise RuntimeError(f"{scenario} run {index} has the wrong identity")
    run_path = output_dir / f"{scenario}-run-{index}.json"
    persisted_run = load_result(run_path, f"{scenario} run {index}")
    if persisted_run != run:
        raise RuntimeError(f"{scenario} run {index} does not match its result file")

    expected_disk_log_name = f"{scenario}-run-{index}-fs_usage.txt"
    if run.get("fs_usage_log_file") != expected_disk_log_name:
        raise RuntimeError(f"{scenario} run {index} has the wrong fs_usage log path")
    disk_log_path = output_dir / expected_disk_log_name
    if not disk_log_path.is_file():
        raise RuntimeError(f"missing fs_usage log: {expected_disk_log_name}")
    if run.get("fs_usage_log_sha256") != file_sha256(disk_log_path):
        raise RuntimeError(f"{scenario} run {index} fs_usage log was modified")
    expected_disk_violations = [
        f"disk-write:{line}" for line in read_disk_write_violations(disk_log_path)
    ]
    recorded_disk_violations = [
        item
        for item in run.get("violations", [])
        if isinstance(item, str) and item.startswith("disk-write:")
    ]
    if recorded_disk_violations != expected_disk_violations:
        raise RuntimeError(
            f"{scenario} run {index} disk violations do not match fs_usage log"
        )
    measurement_started = require_finite_number(
        run.get("measurement_started_at_uptime"),
        f"{scenario} run {index} measurement start",
    )
    disk_verified = require_finite_number(
        run.get("fs_usage_verified_at_uptime"),
        f"{scenario} run {index} fs_usage verification time",
    )
    disk_covered_until = require_finite_number(
        run.get("fs_usage_covered_until_uptime"),
        f"{scenario} run {index} fs_usage coverage time",
    )
    if disk_verified > measurement_started:
        raise RuntimeError(
            f"{scenario} run {index} fs_usage was not verified before measurement"
        )
    if disk_covered_until < measurement_started + MEASUREMENT_SECONDS:
        raise RuntimeError(
            f"{scenario} run {index} fs_usage did not cover the measurement"
        )

    expected_report_name = f"{scenario}-run-{index}-task-power.json"
    if run.get("task_power_report_file") != expected_report_name:
        raise RuntimeError(f"{scenario} run {index} has the wrong raw report path")
    report_path = output_dir / expected_report_name
    if not report_path.is_file():
        raise RuntimeError(f"missing raw task-power report: {expected_report_name}")
    try:
        raw_report = json.loads(report_path.read_bytes())
    except (json.JSONDecodeError, UnicodeDecodeError) as error:
        raise RuntimeError(
            f"raw task-power report is invalid: {expected_report_name}"
        ) from error
    if not isinstance(raw_report, dict) or raw_report != run.get("task_power_report"):
        raise RuntimeError(
            f"{scenario} run {index} does not match its raw task-power report"
        )
    validate_task_power_report(raw_report, run, scenario)

    samples = run.get("samples")
    expected_samples = math.ceil(
        MEASUREMENT_SECONDS / RESOURCE_SAMPLE_INTERVAL_SECONDS
    )
    if not isinstance(samples, list) or len(samples) != expected_samples:
        raise RuntimeError(
            f"{scenario} run {index} must contain {expected_samples} resource samples"
        )
    elapsed_values = []
    cpu_values = []
    rss_values = []
    for sample in samples:
        if not isinstance(sample, dict):
            raise RuntimeError(f"{scenario} run {index} has an invalid sample")
        elapsed_values.append(
            require_finite_number(
                sample.get("elapsed_seconds"),
                f"{scenario} run {index} sample time",
            )
        )
        cpu = require_finite_number(
            sample.get("cpu_percent"),
            f"{scenario} run {index} CPU sample",
        )
        rss = sample.get("rss_kib")
        if cpu < 0 or isinstance(rss, bool) or not isinstance(rss, int) or rss <= 0:
            raise RuntimeError(f"{scenario} run {index} has an invalid resource sample")
        cpu_values.append(cpu)
        rss_values.append(rss)
    if elapsed_values[0] > 1:
        raise RuntimeError(f"{scenario} run {index} is missing its first sample")
    if elapsed_values[-1] < (
        MEASUREMENT_SECONDS - RESOURCE_SAMPLE_INTERVAL_SECONDS - 1
    ):
        raise RuntimeError(f"{scenario} run {index} resource samples are truncated")
    for earlier, later in zip(elapsed_values, elapsed_values[1:]):
        if later <= earlier or later - earlier > RESOURCE_SAMPLE_INTERVAL_SECONDS + 1:
            raise RuntimeError(f"{scenario} run {index} sample cadence is invalid")
    measurement_elapsed = require_finite_number(
        run.get("measurement_elapsed_seconds"),
        f"{scenario} run {index} measurement duration",
    )
    if not (
        MEASUREMENT_SECONDS
        <= measurement_elapsed
        <= MEASUREMENT_SECONDS + MEASUREMENT_DURATION_TOLERANCE_SECONDS
    ):
        raise RuntimeError(f"{scenario} run {index} measurement duration is invalid")
    measurement_ended = require_finite_number(
        run.get("measurement_ended_at_uptime"),
        f"{scenario} run {index} measurement end",
    )
    if not math.isclose(
        measurement_ended - measurement_started,
        measurement_elapsed,
        rel_tol=0,
        abs_tol=1e-6,
    ):
        raise RuntimeError(
            f"{scenario} run {index} measurement endpoints do not match duration"
        )

    require_matching_number(
        run.get("average_cpu_percent"),
        statistics.fmean(cpu_values),
        f"{scenario} run {index} average CPU",
    )
    require_matching_number(
        run.get("maximum_rss_kib"),
        max(rss_values),
        f"{scenario} run {index} maximum RSS",
    )
    require_matching_number(
        run.get("median_rss_kib"),
        statistics.median(rss_values),
        f"{scenario} run {index} median RSS",
    )
    violations = run.get("violations")
    if not isinstance(violations, list) or not all(
        isinstance(item, str) for item in violations
    ):
        raise RuntimeError(f"{scenario} run {index} has invalid violations")
    observations = run.get("power_observations")
    measurement_observations = (
        [
            item
            for item in observations
            if isinstance(item, dict) and item.get("phase") == "measurement-sample"
        ]
        if isinstance(observations, list)
        else []
    )
    if len(measurement_observations) != expected_samples:
        raise RuntimeError(
            f"{scenario} run {index} has incomplete power observations"
        )


def validate_scenario_integrity(
    summary: dict,
    scenario: str,
    output_dir: Path,
    app_size_kib: int,
) -> None:
    if summary.get("version") != PROTOCOL_VERSION:
        raise RuntimeError(f"{scenario} result has the wrong protocol version")
    validate_summary_power(summary, scenario)
    runs = summary["runs"]
    for index, run in enumerate(runs, start=1):
        if not isinstance(run, dict):
            raise RuntimeError(f"{scenario} run {index} is invalid")
        validate_run_integrity(run, scenario, index, output_dir)

    expected_values = {
        "median_cpu_percent": statistics.median(
            run["average_cpu_percent"] for run in runs
        ),
        "maximum_cpu_percent": max(run["average_cpu_percent"] for run in runs),
        "median_rss_kib": statistics.median(run["median_rss_kib"] for run in runs),
        "maximum_rss_kib": max(run["maximum_rss_kib"] for run in runs),
        "median_wakeups_per_second": statistics.median(
            run["wakeups_per_second"] for run in runs
        ),
    }
    for key, expected in expected_values.items():
        require_matching_number(summary.get(key), expected, f"{scenario} {key}")
    expected_wakeup_limit = 1.2 if scenario == "standard" else 0.25
    require_matching_number(
        summary.get("wakeup_limit"),
        expected_wakeup_limit,
        f"{scenario} wakeup limit",
    )
    if summary.get("app_size_kib") != app_size_kib:
        raise RuntimeError(f"{scenario} App size does not match the current bundle")
    expected_passed = (
        (scenario != "standard" or expected_values["median_cpu_percent"] <= 0.3)
        and (scenario != "standard" or expected_values["maximum_cpu_percent"] <= 0.5)
        and expected_values["median_rss_kib"] <= 25 * 1024
        and expected_values["maximum_rss_kib"] <= 40 * 1024
        and expected_values["median_wakeups_per_second"] <= expected_wakeup_limit
        and app_size_kib <= 10_240
        and all(not run["violations"] for run in runs)
    )
    if summary.get("passed") is not expected_passed:
        raise RuntimeError(f"{scenario} passed flag does not match raw results")


def validate_launch_integrity(result: dict) -> None:
    validate_launch_power(result)
    if result.get("runs") != LAUNCH_RUNS:
        raise RuntimeError(f"launch result must contain exactly {LAUNCH_RUNS} runs")
    samples = result.get("samples_ms")
    if not isinstance(samples, list) or len(samples) != LAUNCH_RUNS:
        raise RuntimeError("launch samples are incomplete")
    values = [
        require_finite_number(sample, "launch sample")
        for sample in samples
    ]
    if any(sample < 0 for sample in values):
        raise RuntimeError("launch samples must be non-negative")
    expected_median = statistics.median(values)
    require_matching_number(result.get("median_ms"), expected_median, "launch median")
    require_matching_number(result.get("threshold_ms"), 300, "launch threshold")
    if result.get("passed") is not (expected_median <= 300):
        raise RuntimeError("launch passed flag does not match raw samples")


def read_task_power_report(descriptor: int, timeout: float = 10) -> bytes:
    deadline = time.monotonic() + timeout
    chunks = []
    while True:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise RuntimeError("task power report timed out")
        ready, _, _ = select.select([descriptor], [], [], remaining)
        if not ready:
            raise RuntimeError("task power report timed out")
        chunk = os.read(descriptor, 65_536)
        if not chunk:
            break
        chunks.append(chunk)
    payload = b"".join(chunks)
    if not payload:
        raise RuntimeError("task power report was empty")
    return payload


def save_raw_task_power_report(
    output_dir: Path,
    scenario: str,
    index: int,
    payload: bytes,
) -> Path:
    path = output_dir / f"{scenario}-run-{index}-task-power.json"
    path.write_bytes(payload)
    return path


def run_once(output_dir: Path, scenario: str, index: int) -> dict:
    ensure_no_existing_instance()
    run_started = time.monotonic()
    requested_measurement_start = (
        run_started + WARMUP_SECONDS + DISK_MONITOR_PREPARATION_SECONDS
    )
    power_observations = [
        capture_power_observation(
            scenario,
            "before-launch",
            0,
        )
    ]
    report_read, report_write = os.pipe()
    token = uuid.uuid4().hex
    environment = os.environ.copy()
    environment.update(
        {
            "METRILENS_PERF_MODE": "1",
            "METRILENS_PERF_REPORT_FD": str(report_write),
            "METRILENS_PERF_LAUNCH_TOKEN": token,
            "METRILENS_PERF_START_UPTIME": f"{requested_measurement_start:.9f}",
        }
    )
    app_process = subprocess.Popen(
        [str(EXECUTABLE)],
        env=environment,
        pass_fds=(report_write,),
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    os.close(report_write)
    stop = threading.Event()
    violations: list[str] = []
    monitor_errors: list[str] = []
    watchers = start_runtime_monitors(
        app_process.pid,
        stop,
        violations,
        monitor_errors,
    )
    disk_process = None
    disk_stream = None
    disk_log = output_dir / f"{scenario}-run-{index}-fs_usage.txt"
    samples = []
    try:
        wait_until(
            requested_measurement_start - DISK_MONITOR_PREPARATION_SECONDS
        )
        power_observations.append(
            capture_power_observation(
                scenario,
                "after-warmup",
                time.monotonic() - run_started,
            )
        )
        if monitor_errors:
            raise RuntimeError(f"runtime monitor failed: {monitor_errors[0]}")
        if app_process.poll() is not None:
            raise RuntimeError("Metrilens exited during warmup")
        disk_process, disk_stream, disk_monitor_verified_at = start_disk_monitor(
            app_process.pid,
            disk_log,
        )
        measurement_started = wait_until(requested_measurement_start)
        if (
            abs(measurement_started - requested_measurement_start)
            > WINDOW_ALIGNMENT_TOLERANCE_SECONDS
        ):
            raise RuntimeError("resource measurement missed the shared start uptime")
        deadline = measurement_started + MEASUREMENT_SECONDS
        next_sample_at = measurement_started
        while next_sample_at < deadline:
            remaining = next_sample_at - time.monotonic()
            if remaining > 0:
                time.sleep(remaining)
            sample_elapsed = time.monotonic() - measurement_started
            power_observations.append(
                capture_power_observation(
                    scenario,
                    "measurement-sample",
                    time.monotonic() - run_started,
                )
            )
            if monitor_errors:
                raise RuntimeError(f"runtime monitor failed: {monitor_errors[0]}")
            result = subprocess.run(
                ["ps", "-p", str(app_process.pid), "-o", "%cpu=,rss="],
                capture_output=True,
                text=True,
                check=True,
            )
            fields = result.stdout.split()
            if len(fields) != 2:
                raise RuntimeError("missing ps sample")
            samples.append(
                {
                    "elapsed_seconds": sample_elapsed,
                    "cpu_percent": float(fields[0]),
                    "rss_kib": int(fields[1]),
                }
            )
            next_sample_at += RESOURCE_SAMPLE_INTERVAL_SECONDS
        remaining = deadline - time.monotonic()
        if remaining > 0:
            time.sleep(remaining)
        measurement_ended = time.monotonic()
        measurement_elapsed = measurement_ended - measurement_started
        disk_monitor_covered_until = verify_disk_monitor_coverage(
            disk_process,
            deadline,
        )

        report_payload = read_task_power_report(report_read)
        report_path = save_raw_task_power_report(
            output_dir,
            scenario,
            index,
            report_payload,
        )
        try:
            report = json.loads(report_payload)
        except (json.JSONDecodeError, UnicodeDecodeError) as error:
            raise RuntimeError(
                f"task power report is invalid JSON; raw report saved to {report_path}"
            ) from error
        if not isinstance(report, dict):
            raise RuntimeError(
                f"task power report must be a JSON object; raw report saved to {report_path}"
            )
        power_observations.append(
            capture_power_observation(
                scenario,
                "after-measurement",
                time.monotonic() - run_started,
            )
        )
        if report.get("version") != 3 or report.get("processID") != app_process.pid:
            raise RuntimeError("task power report identity mismatch")
        if report.get("launchToken") != token:
            raise RuntimeError("task power report token mismatch")
        if not math.isclose(
            require_finite_number(
                report.get("requestedStartUptime"),
                "task power requested start",
            ),
            requested_measurement_start,
            rel_tol=0,
            abs_tol=1e-6,
        ):
            raise RuntimeError("task power report has the wrong shared start uptime")
        validate_task_power_window_alignment(
            report,
            requested_measurement_start,
            measurement_started,
            measurement_ended,
            "task power",
        )
        validate_runtime_context(report["startContext"], scenario)
        validate_runtime_context(report["endContext"], scenario)
        write_violations = finish_disk_monitor(disk_process, disk_stream, disk_log)
        disk_process = None
        disk_stream = None
        violations.extend(f"disk-write:{line}" for line in write_violations)
    finally:
        stop.set()
        for watcher in watchers:
            watcher.join(timeout=1)
            if watcher.is_alive():
                monitor_errors.append("runtime monitor did not stop")
        if disk_process is not None:
            disk_process.terminate()
            disk_process.wait(timeout=5)
        if disk_stream is not None:
            disk_stream.close()
        os.close(report_read)
        terminate(app_process.pid)
    if monitor_errors:
        raise RuntimeError(f"runtime monitor failed: {monitor_errors[0]}")

    result = {
        "scenario": scenario,
        "run": index,
        "process_id": app_process.pid,
        "samples": samples,
        "requested_measurement_start_uptime": requested_measurement_start,
        "measurement_started_at_uptime": measurement_started,
        "measurement_ended_at_uptime": measurement_ended,
        "measurement_elapsed_seconds": measurement_elapsed,
        "average_cpu_percent": statistics.fmean(item["cpu_percent"] for item in samples),
        "maximum_rss_kib": max(item["rss_kib"] for item in samples),
        "median_rss_kib": statistics.median(item["rss_kib"] for item in samples),
        "wakeups_per_second": report["interruptWakeupsPerSecond"],
        "fs_usage_log_file": disk_log.name,
        "fs_usage_log_sha256": file_sha256(disk_log),
        "fs_usage_verified_at_uptime": disk_monitor_verified_at,
        "fs_usage_covered_until_uptime": disk_monitor_covered_until,
        "task_power_report_file": report_path.name,
        "task_power_report": report,
        "runtime_start": report["startContext"],
        "runtime_end": report["endContext"],
        "power_observations": power_observations,
        "violations": violations,
    }
    path = output_dir / f"{scenario}-run-{index}.json"
    path.write_text(json.dumps(result, indent=2), encoding="utf-8")
    return result


def run_scenario(scenario: str) -> int:
    if not EXECUTABLE.is_file():
        print(f"Release executable not found: {EXECUTABLE}", file=sys.stderr)
        return 2
    host_power = validate_host_for_scenario(scenario)
    commit, output_dir = repository_identity()
    output_dir.mkdir(parents=True, exist_ok=True)
    identity = measurement_identity(commit)
    size_kib = current_app_size_kib()
    launch = load_result(output_dir / "launch.json", "launch")
    validate_result_identity(launch, identity, "launch")
    validate_launch_integrity(launch)
    if not launch.get("passed"):
        raise RuntimeError("launch result did not pass")
    if scenario == "low-power":
        standard = load_result(output_dir / "standard-summary.json", "standard")
        validate_result_identity(standard, identity, "standard")
        validate_scenario_integrity(standard, "standard", output_dir, size_kib)
        if not standard.get("passed"):
            raise RuntimeError("standard result did not pass")
    runs_count = STANDARD_RUNS if scenario == "standard" else LOW_POWER_RUNS
    runs = [run_once(output_dir, scenario, index + 1) for index in range(runs_count)]
    host_power_at_end = validate_host_for_scenario(scenario)
    wakeup_limit = 1.2 if scenario == "standard" else 0.25
    summary = {
        "version": PROTOCOL_VERSION,
        "scenario": scenario,
        "identity": identity,
        "host_power_at_start": host_power,
        "host_power_at_end": host_power_at_end,
        "runs": runs,
        "median_cpu_percent": statistics.median(run["average_cpu_percent"] for run in runs),
        "maximum_cpu_percent": max(run["average_cpu_percent"] for run in runs),
        "median_rss_kib": statistics.median(run["median_rss_kib"] for run in runs),
        "maximum_rss_kib": max(run["maximum_rss_kib"] for run in runs),
        "median_wakeups_per_second": statistics.median(
            run["wakeups_per_second"] for run in runs
        ),
        "wakeup_limit": wakeup_limit,
        "app_size_kib": size_kib,
    }
    summary["passed"] = (
        (scenario != "standard" or summary["median_cpu_percent"] <= 0.3)
        and (scenario != "standard" or summary["maximum_cpu_percent"] <= 0.5)
        and summary["median_rss_kib"] <= 25 * 1024
        and summary["maximum_rss_kib"] <= 40 * 1024
        and summary["median_wakeups_per_second"] <= wakeup_limit
        and summary["app_size_kib"] <= 10_240
        and all(not run["violations"] for run in runs)
    )
    validate_scenario_integrity(summary, scenario, output_dir, size_kib)
    path = output_dir / f"{scenario}-summary.json"
    path.write_text(json.dumps(summary, indent=2), encoding="utf-8")
    print(json.dumps(summary, indent=2))
    return 0 if summary["passed"] else 1


def finalize() -> int:
    commit, output_dir = repository_identity()
    identity = measurement_identity(commit)
    required = {
        "launch": output_dir / "launch.json",
        "standard": output_dir / "standard-summary.json",
        "low_power": output_dir / "low-power-summary.json",
    }
    missing = [name for name, path in required.items() if not path.is_file()]
    if missing:
        raise RuntimeError(f"missing performance result(s): {', '.join(missing)}")
    results = {
        name: json.loads(path.read_text(encoding="utf-8"))
        for name, path in required.items()
    }
    for name, result in results.items():
        validate_result_identity(result, identity, name)
    validate_launch_integrity(results["launch"])
    if results["standard"].get("scenario") != "standard":
        raise RuntimeError("standard result has the wrong scenario")
    if results["low_power"].get("scenario") != "low-power":
        raise RuntimeError("low-power result has the wrong scenario")
    size_kib = current_app_size_kib()
    validate_scenario_integrity(
        results["standard"],
        "standard",
        output_dir,
        size_kib,
    )
    validate_scenario_integrity(
        results["low_power"],
        "low-power",
        output_dir,
        size_kib,
    )
    summary = {
        "version": PROTOCOL_VERSION,
        "identity": identity,
        "launch": results["launch"],
        "standard": results["standard"],
        "low_power": results["low_power"],
    }
    summary["passed"] = all(result.get("passed") is True for result in results.values())
    (output_dir / "summary.json").write_text(
        json.dumps(summary, indent=2), encoding="utf-8"
    )
    print(json.dumps(summary, indent=2))
    return 0 if summary["passed"] else 1


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=["standard", "low-power", "finalize"])
    arguments = parser.parse_args()
    if arguments.action == "finalize":
        return finalize()
    return run_scenario(arguments.action)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (RuntimeError, subprocess.CalledProcessError) as error:
        print(f"performance infrastructure error: {error}", file=sys.stderr)
        raise SystemExit(2)
