"""Isolated runner lifecycle tests. No game or engine process is launched."""

import importlib.util
import json
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("mac_capture", ROOT / "Capture-Screens.py")
CAPTURE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CAPTURE)


class FakeProcess:
    pid = 12345

    def __init__(self, running=False):
        self.returncode = None if running else 0
        self.terminated = False

    def poll(self):
        return self.returncode

    def terminate(self):
        self.terminated = True
        self.returncode = -15

    def wait(self, timeout=None):
        return self.returncode


class MacCaptureTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="ultrapool-capture-fixtures-")
        # macOS /var is a symlink; use its canonical path for path-safety checks.
        self.root = Path(self.temporary.name).resolve()
        self.source = self.root / 'source "quoted"'
        for relative in CAPTURE.FIXTURES:
            target = self.source / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text("fixture\n")
        self.app = self.root / "steam/Ultrapool.app"
        for relative in (CAPTURE.MAC.EXECUTABLE, "Contents/Resources/Ultrapool.pck",
                         "Contents/Frameworks/libsteam_api.dylib",
                         "Contents/Frameworks/libgodotsteam.macos.template_release.dylib"):
            target = self.app / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text("inert fixture; never executed\n")
        (self.app / CAPTURE.MAC.EXECUTABLE).chmod(0o755)
        (self.app / "Contents/Info.plist").write_bytes(plistlib.dumps({
            "CFBundleExecutable": "Ultrapool", "CFBundleShortVersionString": CAPTURE.MAC.GAME_VERSION,
        }))
        self.user_data = self.root / "Application Support"
        self.save = self.user_data / "Godot/app_userdata/Ultrapool/save.tres"
        self.save.parent.mkdir(parents=True)
        self.save.write_text("original save")
        self.output = self.root / "captures"
        self.before = CAPTURE.tree_hashes(self.app)
        self.process = FakeProcess()
        self.closed = patch.object(CAPTURE.MAC, "assert_game_closed")
        self.signer = patch.object(CAPTURE.MAC, "sign_bundle")
        self.spawner = patch.object(CAPTURE.subprocess, "Popen", side_effect=self.spawn)
        self.closed.start()
        self.signer.start()
        self.popen = self.spawner.start()
        self.addCleanup(self.temporary.cleanup)
        self.addCleanup(self.closed.stop)
        self.addCleanup(self.signer.stop)
        self.addCleanup(self.spawner.stop)

    def spawn(self, args, **options):
        self.assertEqual(options["stdin"], CAPTURE.subprocess.DEVNULL)
        plist_path = Path(args[0]).parents[1] / "Info.plist"
        copied_info = plistlib.loads(plist_path.read_bytes())
        self.assertTrue(copied_info["LSBackgroundOnly"])
        self.assertEqual(copied_info["CFBundleIdentifier"], options["env"]["__CFBundleIdentifier"])
        override = (Path(args[0]).parent / "override.cfg").read_text()
        self.assertIn("UltrapoolTogetherRenderTest-", override)
        self.assertIn(json.dumps("*" + str(self.source / "tests/render_probe.gd")), override)
        self.assertEqual(args[args.index("--audio-driver") + 1], "Dummy")
        options["stdout"].write(b'RENDER_CAPTURE_ENV {"window_mode":0,"unfocusable":true,"mouse_passthrough":true,"max_fps":30}\n')
        options["stdout"].write(b"RENDER_PROBE_PASS []\n")
        options["stdout"].flush()
        self.output.joinpath("index.html").write_text("<html>fixture</html>")
        self.output.joinpath("fixture.png").write_bytes(b"fixture image")
        return self.process

    def run_capture(self, **options):
        return CAPTURE.capture(game_path=self.app, output_path=self.output,
                               source_root=self.source, user_data_root=self.user_data, **options)

    def report(self):
        return json.loads((self.output / "runner.json").read_text())

    def test_success_runs_once_isolated_and_cleans_private_runtime(self):
        self.run_capture()
        self.assertEqual(self.popen.call_count, 1)
        report = self.report()
        self.assertEqual(report["status"], "passed")
        self.assertTrue(report["probe_passed"])
        self.assertTrue(report["process_stopped"])
        self.assertTrue(report["runtime_removed"])
        self.assertTrue(report["saves_unchanged"])
        self.assertTrue(report["game_files_unchanged"])
        # Native AppKit can refuse minimization for a background-only app. Do not
        # report the requested mode as though it were measured native state.
        self.assertEqual(report["requested_window_mode"], "minimized_no_focus")
        self.assertEqual(report["native_environment"]["window_mode"], 0)
        self.assertTrue(report["native_environment"]["unfocusable"])
        self.assertTrue(report["native_environment"]["mouse_passthrough"])
        runtime = Path(report["runtime_directory"])
        self.assertEqual(runtime.parent, Path(tempfile.gettempdir()).resolve())
        self.assertFalse(runtime.exists())
        self.assertNotIn(self.output, runtime.parents)
        self.assertEqual(CAPTURE.tree_hashes(self.app), self.before)
        self.assertEqual(self.save.read_text(), "original save")
        self.assertFalse(list(self.output.glob(".runtime-*")))

    def test_timeout_stops_its_process_and_keeps_failure_report(self):
        self.process = FakeProcess(running=True)
        with patch.object(CAPTURE.time, "monotonic", side_effect=[0, 31]):
            with self.assertRaisesRegex(ValueError, "watchdog"):
                self.run_capture(timeout_seconds=30)
        self.assertTrue(self.process.terminated)
        self.assertTrue(self.report()["timed_out"])
        self.assertTrue(self.report()["process_stopped"])
        self.assertTrue(self.report()["runtime_removed"])
        self.assertEqual(self.report()["status"], "failed")

    def test_nonzero_exit_cannot_pass_with_success_marker(self):
        self.process.returncode = 7
        with self.assertRaisesRegex(ValueError, "probe failed"):
            self.run_capture()
        self.assertEqual(self.report()["exit_code"], 7)
        self.assertEqual(self.report()["status"], "failed")

    def test_script_error_stops_running_process(self):
        self.process = FakeProcess(running=True)
        original = self.spawn

        def erroneous(args, **options):
            process = original(args, **options)
            options["stderr"].write(b"SCRIPT ERROR: fixture error\n")
            options["stderr"].flush()
            return process

        self.popen.side_effect = erroneous
        with self.assertRaisesRegex(ValueError, "script error"):
            self.run_capture()
        self.assertTrue(self.process.terminated)
        self.assertEqual(len(self.report()["script_errors"]), 1)

    def test_changed_save_cannot_pass(self):
        original = self.spawn

        def changed(args, **options):
            process = original(args, **options)
            self.save.write_text("unexpected change")
            return process

        self.popen.side_effect = changed
        with self.assertRaisesRegex(ValueError, "normal save changed"):
            self.run_capture()
        self.assertFalse(self.report()["saves_unchanged"])

    def test_preserves_existing_output_and_rejects_protected_locations(self):
        self.output.mkdir()
        (self.output / "old.png").write_text("previous capture")
        with self.assertRaisesRegex(ValueError, "new directory"):
            self.run_capture()
        self.assertEqual((self.output / "old.png").read_text(), "previous capture")
        self.output = self.app / "captures"
        with self.assertRaisesRegex(ValueError, "separate"):
            self.run_capture()
        self.popen.assert_not_called()

    def test_sign_failure_never_launches_and_cleans_runtime(self):
        with patch.object(CAPTURE.MAC, "sign_bundle", side_effect=ValueError("sign failure")):
            with self.assertRaisesRegex(ValueError, "sign failure"):
                self.run_capture()
        self.popen.assert_not_called()
        self.assertTrue(self.report()["runtime_removed"])
        self.assertTrue(self.report()["game_files_unchanged"])
        self.assertIsNone(self.report()["native_environment"])

    def test_other_capture_lock_rejects_concurrent_harness(self):
        lock = self.root / "capture.lock"
        with CAPTURE.capture_lock(lock):
            with self.assertRaisesRegex(ValueError, "Another screenshot"):
                with CAPTURE.capture_lock(lock):
                    self.fail("Acquired an occupied lock")


if __name__ == "__main__":
    unittest.main()
