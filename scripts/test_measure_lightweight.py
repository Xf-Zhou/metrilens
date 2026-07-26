#!/usr/bin/env python3
import json
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock, patch

from measure_launch import ensure_no_existing_instance as ensure_no_existing_launch
from measure_lightweight import (
    DISK_MONITOR_DURATION_SECONDS,
    DISK_MONITOR_STARTUP_WAIT_SECONDS,
    MEASUREMENT_SECONDS,
    capture_power_observation,
    ensure_no_existing_instance,
    file_sha256,
    inspect_child_processes,
    inspect_network_activity,
    monitor_at_fixed_interval,
    parse_power_environment,
    save_raw_task_power_report,
    start_disk_monitor,
    validate_launch_power,
    validate_run_integrity,
    validate_summary_power,
    verify_disk_monitor_coverage,
)


CUSTOM_OUTPUT = """Battery Power:
 lidwake              1
 lowpowermode         1
AC Power:
 lidwake              1
 lowpowermode         0
"""
AC_STANDARD = {
    "power_source": "AC Power",
    "low_power_mode_enabled": False,
}
BATTERY_STANDARD = {
    "power_source": "Battery Power",
    "low_power_mode_enabled": False,
}
STANDARD_RUNTIME = {
    "primaryMetric": "cpu",
    "configuredInterval": 1,
    "effectiveInterval": 1,
    "lowPowerModeEnabled": False,
    "powerSource": "AC Power",
}


class PowerEnvironmentParserTests(unittest.TestCase):
    def test_ac_profile_uses_ac_low_power_value(self) -> None:
        result = parse_power_environment(
            "Now drawing from 'AC Power'\n",
            CUSTOM_OUTPUT,
        )
        self.assertEqual(
            result,
            {"power_source": "AC Power", "low_power_mode_enabled": False},
        )

    def test_battery_profile_uses_battery_low_power_value(self) -> None:
        result = parse_power_environment(
            "Now drawing from 'Battery Power'\n",
            CUSTOM_OUTPUT,
        )
        self.assertEqual(
            result,
            {"power_source": "Battery Power", "low_power_mode_enabled": True},
        )

    def test_missing_active_profile_is_an_infrastructure_error(self) -> None:
        with self.assertRaisesRegex(RuntimeError, "low-power mode"):
            parse_power_environment(
                "Now drawing from 'AC Power'\n",
                "Battery Power:\n lowpowermode 1\n",
            )

    def test_summary_rejects_battery_power_in_either_scenario(self) -> None:
        summary = {
            "host_power_at_start": {
                "power_source": "AC Power",
                "low_power_mode_enabled": True,
            },
            "host_power_at_end": {
                "power_source": "Battery Power",
                "low_power_mode_enabled": True,
            },
            "runs": [],
        }
        with self.assertRaisesRegex(RuntimeError, "AC Power"):
            validate_summary_power(summary, "low-power")

    def test_launch_rejects_battery_power(self) -> None:
        with self.assertRaisesRegex(RuntimeError, "AC Power"):
            validate_launch_power(
                {
                    "runs": 1,
                    "host_power_at_start": {
                        "power_source": "Battery Power",
                        "low_power_mode_enabled": False,
                    },
                    "host_power_at_end": {
                        "power_source": "AC Power",
                        "low_power_mode_enabled": False,
                    },
                    "power_observations": [],
                }
            )

    def test_intermediate_battery_observation_cannot_be_hidden_by_ac_endpoints(self) -> None:
        provider = Mock(
            side_effect=[
                AC_STANDARD,
                BATTERY_STANDARD,
                AC_STANDARD,
            ]
        )
        capture_power_observation("standard", "start", 0, provider)
        with self.assertRaisesRegex(RuntimeError, "AC Power"):
            capture_power_observation("standard", "middle", 5, provider)
        capture_power_observation("standard", "end", 10, provider)

    def test_persisted_standard_summary_rejects_intermediate_battery_power(self) -> None:
        phases = [
            "before-launch",
            "after-warmup",
            "measurement-sample",
            "after-measurement",
        ]
        runs = []
        for index in range(3):
            observations = [
                {"phase": phase, "elapsed_seconds": offset, **AC_STANDARD}
                for offset, phase in enumerate(phases)
            ]
            if index == 1:
                observations[2] = {
                    "phase": "measurement-sample",
                    "elapsed_seconds": 5,
                    **BATTERY_STANDARD,
                }
            runs.append(
                {
                    "run": index + 1,
                    "runtime_start": STANDARD_RUNTIME,
                    "runtime_end": STANDARD_RUNTIME,
                    "power_observations": observations,
                }
            )
        with self.assertRaisesRegex(RuntimeError, "AC Power"):
            validate_summary_power(
                {
                    "host_power_at_start": AC_STANDARD,
                    "host_power_at_end": AC_STANDARD,
                    "runs": runs,
                },
                "standard",
            )

    def test_persisted_launch_summary_rejects_intermediate_battery_power(self) -> None:
        with self.assertRaisesRegex(RuntimeError, "AC Power"):
            validate_launch_power(
                {
                    "runs": 1,
                    "host_power_at_start": AC_STANDARD,
                    "host_power_at_end": AC_STANDARD,
                    "power_observations": [
                        {"phase": "run-1-before", "elapsed_seconds": 0, **AC_STANDARD},
                        {"phase": "run-1-after", "elapsed_seconds": 1, **BATTERY_STANDARD},
                    ],
                }
            )


class ProcessMonitorTests(unittest.TestCase):
    def test_existing_instance_probe_rejects_pgrep_failure(self) -> None:
        with patch(
            "measure_lightweight.subprocess.run",
            return_value=subprocess.CompletedProcess([], 2),
        ):
            with self.assertRaisesRegex(RuntimeError, "pgrep failed"):
                ensure_no_existing_instance()

    def test_launch_probe_rejects_pgrep_failure(self) -> None:
        with patch(
            "measure_launch.subprocess.run",
            return_value=subprocess.CompletedProcess([], 2),
        ):
            with self.assertRaisesRegex(RuntimeError, "pgrep failed"):
                ensure_no_existing_launch()

    def test_pgrep_failure_is_an_infrastructure_error(self) -> None:
        runner = Mock(
            return_value=subprocess.CompletedProcess([], 2, stdout="", stderr="failed")
        )
        violation, error = inspect_child_processes(123, runner=runner)
        self.assertIsNone(violation)
        self.assertIn("pgrep failed", error)

    def test_lsof_failure_is_an_infrastructure_error(self) -> None:
        runner = Mock(
            return_value=subprocess.CompletedProcess([], 1, stdout="", stderr="failed")
        )
        violation, error = inspect_network_activity(123, runner=runner)
        self.assertIsNone(violation)
        self.assertIn("lsof failed", error)

    def test_fixed_monitor_waits_only_until_the_next_100ms_deadline(self) -> None:
        stop = Mock()
        stop.is_set.return_value = False
        stop.wait.return_value = True
        check = Mock(return_value=(None, None))
        clock = Mock(side_effect=[10.0, 10.0, 10.03])
        monitor_at_fixed_interval(
            "test",
            check,
            stop,
            [],
            [],
            interval=0.1,
            target_interval=0.1,
            clock=clock,
        )
        stop.wait.assert_called_once()
        self.assertAlmostEqual(stop.wait.call_args.args[0], 0.07)

    def test_fixed_monitor_rejects_a_late_next_start_before_checking(self) -> None:
        stop = Mock()
        stop.is_set.return_value = False
        stop.wait.return_value = False
        check = Mock(return_value=(None, None))
        errors = []
        clock = Mock(side_effect=[10.0, 10.0, 10.03, 10.15])
        monitor_at_fixed_interval(
            "test",
            check,
            stop,
            [],
            errors,
            interval=0.1,
            target_interval=0.1,
            clock=clock,
        )
        self.assertEqual(check.call_count, 1)
        self.assertIn("exceeded", errors[0])

    def test_disk_monitor_duration_covers_startup_and_measurement(self) -> None:
        self.assertGreater(
            DISK_MONITOR_DURATION_SECONDS,
            MEASUREMENT_SECONDS + DISK_MONITOR_STARTUP_WAIT_SECONDS,
        )

    def test_disk_monitor_rejects_early_successful_exit(self) -> None:
        process = Mock()
        process.poll.return_value = 0
        with tempfile.TemporaryDirectory() as directory:
            with patch("measure_lightweight.subprocess.Popen", return_value=process):
                with patch("measure_lightweight.time.sleep"):
                    with self.assertRaisesRegex(RuntimeError, "exited before"):
                        start_disk_monitor(42, Path(directory) / "fs_usage.txt")

    def test_disk_monitor_must_still_be_running_at_measurement_end(self) -> None:
        process = Mock()
        process.poll.return_value = 0
        with self.assertRaisesRegex(RuntimeError, "window ended"):
            verify_disk_monitor_coverage(process, required_end=700, clock=lambda: 700)


class TaskPowerReportPersistenceTests(unittest.TestCase):
    def test_raw_report_is_saved_without_reencoding(self) -> None:
        payload = b'{"interruptWakeupsPerSecond":0.25}\\n'
        with tempfile.TemporaryDirectory() as directory:
            path = save_raw_task_power_report(
                Path(directory),
                "standard",
                1,
                payload,
            )
            self.assertEqual(path.read_bytes(), payload)

    @staticmethod
    def make_run() -> dict:
        report = {
            "version": 3,
            "launchToken": "token",
            "processID": 42,
            "requestedStartUptime": 1_000.0,
            "startedAtUptime": 1_000.0,
            "endedAtUptime": 1_600.0,
            "startReadBeganAtUptime": 1_000.0,
            "startReadEndedAtUptime": 1_000.0,
            "endReadBeganAtUptime": 1_600.0,
            "endReadEndedAtUptime": 1_600.0,
            "start": {
                "interruptWakeups": 100,
                "platformIdleWakeups": 20,
                "timerWakeupsBin1": 30,
                "timerWakeupsBin2": 40,
            },
            "end": {
                "interruptWakeups": 160,
                "platformIdleWakeups": 25,
                "timerWakeupsBin1": 35,
                "timerWakeupsBin2": 45,
            },
            "startContext": STANDARD_RUNTIME,
            "endContext": STANDARD_RUNTIME,
            "interruptWakeupsPerSecond": 0.1,
        }
        return {
            "scenario": "standard",
            "run": 1,
            "process_id": 42,
            "samples": [],
            "requested_measurement_start_uptime": 1_000.0,
            "measurement_started_at_uptime": 1_000.0,
            "measurement_ended_at_uptime": 1_600.0,
            "measurement_elapsed_seconds": 600.0,
            "average_cpu_percent": 0.0,
            "maximum_rss_kib": 1,
            "median_rss_kib": 1,
            "wakeups_per_second": 0.1,
            "fs_usage_log_file": "standard-run-1-fs_usage.txt",
            "fs_usage_log_sha256": "",
            "fs_usage_verified_at_uptime": 999.5,
            "fs_usage_covered_until_uptime": 1_600.0,
            "task_power_report_file": "standard-run-1-task-power.json",
            "task_power_report": report,
            "runtime_start": STANDARD_RUNTIME,
            "runtime_end": STANDARD_RUNTIME,
            "power_observations": [],
            "violations": [],
        }

    def test_missing_raw_report_fails_integrity_validation(self) -> None:
        run = self.make_run()
        with tempfile.TemporaryDirectory() as directory:
            output_dir = Path(directory)
            disk_log = output_dir / "standard-run-1-fs_usage.txt"
            disk_log.write_text("", encoding="utf-8")
            run["fs_usage_log_sha256"] = file_sha256(disk_log)
            (output_dir / "standard-run-1.json").write_text(
                json.dumps(run),
                encoding="utf-8",
            )
            with self.assertRaisesRegex(RuntimeError, "missing raw task-power"):
                validate_run_integrity(run, "standard", 1, output_dir)

    def test_missing_fs_usage_log_fails_integrity_validation(self) -> None:
        run = self.make_run()
        with tempfile.TemporaryDirectory() as directory:
            output_dir = Path(directory)
            (output_dir / "standard-run-1.json").write_text(
                json.dumps(run),
                encoding="utf-8",
            )
            with self.assertRaisesRegex(RuntimeError, "missing fs_usage log"):
                validate_run_integrity(run, "standard", 1, output_dir)

    def test_truncated_resource_samples_fail_integrity_validation(self) -> None:
        run = self.make_run()
        with tempfile.TemporaryDirectory() as directory:
            output_dir = Path(directory)
            disk_log = output_dir / "standard-run-1-fs_usage.txt"
            disk_log.write_text("", encoding="utf-8")
            run["fs_usage_log_sha256"] = file_sha256(disk_log)
            (output_dir / "standard-run-1.json").write_text(
                json.dumps(run),
                encoding="utf-8",
            )
            (output_dir / "standard-run-1-task-power.json").write_text(
                json.dumps(run["task_power_report"]),
                encoding="utf-8",
            )
            with self.assertRaisesRegex(RuntimeError, "resource samples"):
                validate_run_integrity(run, "standard", 1, output_dir)

    def test_overlong_task_power_window_fails_integrity_validation(self) -> None:
        run = self.make_run()
        run["task_power_report"]["endedAtUptime"] = 1_609.0
        with tempfile.TemporaryDirectory() as directory:
            output_dir = Path(directory)
            disk_log = output_dir / "standard-run-1-fs_usage.txt"
            disk_log.write_text("", encoding="utf-8")
            run["fs_usage_log_sha256"] = file_sha256(disk_log)
            (output_dir / "standard-run-1.json").write_text(
                json.dumps(run),
                encoding="utf-8",
            )
            (output_dir / "standard-run-1-task-power.json").write_text(
                json.dumps(run["task_power_report"]),
                encoding="utf-8",
            )
            with self.assertRaisesRegex(RuntimeError, "duration is invalid"):
                validate_run_integrity(run, "standard", 1, output_dir)

    def test_equal_length_but_shifted_windows_fail_integrity_validation(self) -> None:
        run = self.make_run()
        run["measurement_started_at_uptime"] = 1_000.5
        run["measurement_ended_at_uptime"] = 1_600.5
        run["fs_usage_covered_until_uptime"] = 1_600.5
        with tempfile.TemporaryDirectory() as directory:
            output_dir = Path(directory)
            disk_log = output_dir / "standard-run-1-fs_usage.txt"
            disk_log.write_text("", encoding="utf-8")
            run["fs_usage_log_sha256"] = file_sha256(disk_log)
            (output_dir / "standard-run-1.json").write_text(
                json.dumps(run),
                encoding="utf-8",
            )
            (output_dir / "standard-run-1-task-power.json").write_text(
                json.dumps(run["task_power_report"]),
                encoding="utf-8",
            )
            with self.assertRaisesRegex(RuntimeError, "windows are not aligned"):
                validate_run_integrity(run, "standard", 1, output_dir)

    def test_snapshot_read_crossing_window_boundary_fails_validation(self) -> None:
        run = self.make_run()
        report = run["task_power_report"]
        report["endReadBeganAtUptime"] = 1_599.95
        report["endReadEndedAtUptime"] = 1_600.15
        report["endedAtUptime"] = 1_600.05
        with tempfile.TemporaryDirectory() as directory:
            output_dir = Path(directory)
            disk_log = output_dir / "standard-run-1-fs_usage.txt"
            disk_log.write_text("", encoding="utf-8")
            run["fs_usage_log_sha256"] = file_sha256(disk_log)
            (output_dir / "standard-run-1.json").write_text(
                json.dumps(run),
                encoding="utf-8",
            )
            (output_dir / "standard-run-1-task-power.json").write_text(
                json.dumps(report),
                encoding="utf-8",
            )
            with self.assertRaisesRegex(RuntimeError, "snapshot read interval"):
                validate_run_integrity(run, "standard", 1, output_dir)


if __name__ == "__main__":
    unittest.main()
