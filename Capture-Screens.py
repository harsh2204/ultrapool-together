#!/usr/bin/env python3
"""Run the shared render fixtures once in a muted, private macOS app copy."""

import argparse
from contextlib import contextmanager
import datetime
import fcntl
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import uuid


ROOT = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("capture_mac_installer", ROOT / "MacOS.py")
MAC = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MAC)
FIXTURES = (
    "mod/main.gd", "tests/render_bootstrap.gd", "tests/render_talo.gd",
    "tests/render_settings.gd", "tests/render_ui_fixtures.gd", "tests/spectator_fixtures.gd",
    "tests/round_flow_fixtures.gd", "tests/shop_input_fixture.gd", "tests/render_probe.gd",
    "tests/render_gallery.html", "tests/team_vote_probe.gd", "tests/lobby_probe.gd",
    "tests/presence_probe.gd", "tests/router_probe.gd", "tests/controller_probe.gd",
    "tests/shop_layout_probe.gd", "tests/snapshot_probe.gd", "tests/transport_budget_probe.gd",
)
ERROR_PATTERN = re.compile(r"SCRIPT ERROR:|Parse Error:|Compile Error:|RENDER_PROBE_FAIL")
BUNDLE_ID = "org.ultrapooltogether.render-test"


def timestamp():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def tree_hashes(root):
    return {path.relative_to(root).as_posix(): MAC.sha256(path) for path in MAC.files_under(root)}


def progress_hashes(user_data):
    hashes = {}
    for relative in ("Godot/app_userdata/Ultrapool", "UltrapoolTogether"):
        profile = user_data / relative
        MAC.plain_path(profile)
        if profile.exists():
            # Include backups/settings and nested progression data, not only save.tres.
            hashes.update({str(path): MAC.sha256(path) for path in MAC.files_under(profile)})
    return hashes


@contextmanager
def capture_lock(path=None):
    # A per-user advisory lock also excludes harnesses in other source checkouts.
    target = Path(path or Path(tempfile.gettempdir()) / ("ultrapool-together-capture-%d.lock" % os.getuid()))
    descriptor = os.open(target, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    try:
        try:
            fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise ValueError("Another screenshot harness is running.") from error
        yield
    finally:
        os.close(descriptor)


@contextmanager
def interrupt_cleanup():
    def interrupted(signum, _frame):
        raise InterruptedError("Capture interrupted by signal %d." % signum)

    previous = {signum: signal.signal(signum, interrupted) for signum in (signal.SIGTERM, signal.SIGINT)}
    try:
        yield
    finally:
        for signum, handler in previous.items():
            signal.signal(signum, handler)


def prepare_app(source, runtime, source_root, profile_name):
    copied = runtime / MAC.APP_NAME
    shutil.copytree(source, copied)
    plist_path = copied / "Contents/Info.plist"
    with plist_path.open("rb") as handle:
        info = plistlib.load(handle)
    # Keep AppKit activation prohibited. A matching bundle environment and non-TTY
    # streams also avoid Godot's terminal-launch foreground-activation workaround.
    info["CFBundleIdentifier"] = BUNDLE_ID
    info["CFBundleName"] = "Ultrapool Together Render Test"
    info["LSBackgroundOnly"] = True
    info.pop("LSUIElement", None)
    plist_path.write_bytes(plistlib.dumps(info))
    autoloads = {
        "Log": "tests/render_bootstrap.gd", "Talo": "tests/render_talo.gd",
        "SettingsManager": "tests/render_settings.gd", "UltrapoolTogether": "mod/main.gd",
        "RenderProbe": "tests/render_probe.gd",
    }
    override = (
        '[application]\nconfig/name="Ultrapool Together Render Test"\n'
        'config/use_custom_user_dir=true\nconfig/custom_user_dir_name=' + json.dumps(profile_name) + '\n'
        'run/max_fps=30\n\n[display]\nwindow/size/window_width_override=1280\n'
        'window/size/window_height_override=720\nwindow/size/mode=1\nwindow/size/no_focus=true\n'
        '\n[audio]\ndriver/driver="Dummy"\n\n[steam]\ninitialization/initialize_on_startup=false\n'
        '\n[render_test]\nbackground=true\n\n[autoload]\n'
    )
    override += "".join(name + "=" + json.dumps("*" + str(source_root / relative), ensure_ascii=False) + "\n"
                        for name, relative in autoloads.items())
    executable_dir = copied / "Contents/MacOS"
    (executable_dir / "override.cfg").write_text(override, encoding="utf-8")
    (executable_dir / "steam_appid.txt").write_text("4195110\n", encoding="ascii")
    MAC.sign_bundle(copied)
    return copied


def command_for(app, output):
    return [str(app / MAC.EXECUTABLE), "--resolution", "1280x720", "--single-window",
            "--rendering-method", "gl_compatibility", "--audio-driver", "Dummy",
            "--max-fps", "30", "--disable-vsync", "--", "--output", str(output)]


def native_environment(output):
    """Read actual engine state separately from the runner's requested settings."""
    log = output / "stdout.log"
    if not log.is_file():
        return None
    prefix = "RENDER_CAPTURE_ENV "
    for line in log.read_text(errors="replace").splitlines():
        if not line.startswith(prefix):
            continue
        try:
            environment = json.loads(line[len(prefix):])
        except json.JSONDecodeError:
            continue
        if isinstance(environment, dict):
            return environment
    return None


def stop_process(process):
    if process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=3)
    return process.poll() is not None


def capture(game_path=None, output_path=None, timeout_seconds=180, *, source_root=ROOT, user_data_root=None):
    if not 30 <= timeout_seconds <= 300:
        raise ValueError("Timeout must be between 30 and 300 seconds.")
    app = MAC.inspect_game(game_path or MAC.find_game())
    source_root = MAC.full_path(source_root)
    for name in FIXTURES:
        path = source_root / name
        MAC.plain_path(path)
        if not path.is_file():
            raise ValueError("Missing %s. Run from a complete source checkout." % name)
    run_id = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ-") + uuid.uuid4().hex[:8]
    output = MAC.full_path(output_path or source_root / ".local/screenshots" / run_id)
    user_data = MAC.full_path(user_data_root or Path.home() / "Library/Application Support")
    MAC.plain_path(output)
    if output.exists():
        raise ValueError("Output path must be a new directory so earlier captures are preserved.")
    for protected in (app, user_data / "Godot/app_userdata/Ultrapool", user_data / "UltrapoolTogether"):
        if output == protected or MAC.inside(output, protected) or MAC.inside(protected, output):
            raise ValueError("Output path must be separate from the game app and normal save profiles.")
    profile_name = "UltrapoolTogetherRenderTest-" + run_id
    report = {
        "started_at": timestamp(), "status": "running", "platform": "macos",
        "renderer": "gl_compatibility", "resolution": "1280x720", "max_fps": 30,
        "audio_driver": "Dummy", "background": True, "requested_window_mode": "minimized_no_focus",
        "native_environment": None,
        "timeout_seconds": timeout_seconds, "isolated_profile": str(user_data / profile_name),
        "process_id": None, "exit_code": None, "timed_out": False, "process_stopped": False,
        "probe_passed": False, "script_errors": [], "saves_unchanged": False,
        "game_files_unchanged": False, "runtime_removed": False,
    }
    process = None
    failure = None
    runtime = None
    with capture_lock(), interrupt_cleanup():
        MAC.assert_game_closed()
        report["source_sha256"] = tree_hashes(app)
        report["save_sha256_before"] = progress_hashes(user_data)
        output.mkdir(parents=True)
        try:
            # Documents/file-provider folders can reintroduce forbidden FinderInfo
            # while codesign runs. Keep the executable copy in the OS temporary
            # directory; captures still go to the chosen output. Canonicalize macOS
            # /var's system symlink before the private-app path-safety checks.
            runtime = Path(tempfile.mkdtemp(prefix="UltrapoolTogetherRenderTest-")).resolve()
            report["runtime_directory"] = str(runtime)
            copied = prepare_app(app, runtime, source_root, profile_name)
            arguments = command_for(copied, output)
            report["arguments"] = arguments[1:]
            environment = dict(os.environ, __CFBundleIdentifier=BUNDLE_ID)
            MAC.assert_game_closed()
            with (output / "stdout.log").open("wb") as stdout, (output / "stderr.log").open("wb") as stderr:
                process = subprocess.Popen(arguments, cwd=copied / "Contents/MacOS", env=environment,
                                           stdin=subprocess.DEVNULL, stdout=stdout, stderr=stderr,
                                           start_new_session=True)
                report["process_id"] = process.pid
                MAC.write_json(output / "runner.json", report)
                print("Capturing with one muted background game process (PID %d)." % process.pid, flush=True)
                print("Output: " + str(output), flush=True)
                deadline = time.monotonic() + timeout_seconds
                while process.poll() is None:
                    errors = [line for line in (output / "stderr.log").read_text(errors="replace").splitlines()
                              if ERROR_PATTERN.search(line)]
                    if errors:
                        report["script_errors"] = errors
                        raise ValueError("The render probe reported a script error. Inspect stderr.log.")
                    if time.monotonic() >= deadline:
                        report["timed_out"] = True
                        raise TimeoutError("Capture exceeded its %d second watchdog." % timeout_seconds)
                    time.sleep(0.25)
            report["exit_code"] = process.returncode
            log = "\n".join((output / name).read_text(errors="replace") for name in ("stdout.log", "stderr.log"))
            report["probe_passed"] = bool(re.search(r"^RENDER_PROBE_PASS\b", log, re.MULTILINE))
            report["script_errors"] = [line for line in log.splitlines() if ERROR_PATTERN.search(line)]
            if process.returncode != 0 or not report["probe_passed"] or report["script_errors"]:
                raise ValueError("The render probe failed. Inspect stdout.log and stderr.log.")
            if not (output / "index.html").is_file() or not any(output.glob("*.png")):
                raise ValueError("The render probe did not produce its screenshot gallery and images.")
        except (Exception, KeyboardInterrupt) as error:
            failure = str(error) or type(error).__name__
        finally:
            if process is not None:
                try:
                    report["process_stopped"] = stop_process(process)
                    report["exit_code"] = process.returncode
                except (OSError, subprocess.SubprocessError) as error:
                    failure = (failure + "; " if failure else "") + "Could not stop capture process: " + str(error)
            try:
                report["native_environment"] = native_environment(output)
                report["save_sha256_after"] = progress_hashes(user_data)
                report["saves_unchanged"] = report["save_sha256_after"] == report["save_sha256_before"]
                report["game_files_unchanged"] = tree_hashes(app) == report["source_sha256"]
                if not report["saves_unchanged"] or not report["game_files_unchanged"]:
                    failure = (failure + "; " if failure else "") + "A game file or normal save changed during capture."
            except (OSError, ValueError) as error:
                failure = (failure + "; " if failure else "") + "Preservation verification failed: " + str(error)
            if runtime is not None and (process is None or report["process_stopped"]):
                try:
                    shutil.rmtree(runtime)
                    report["runtime_removed"] = True
                except OSError as error:
                    failure = (failure + "; " if failure else "") + "Private runtime cleanup failed: " + str(error)
            report["status"] = "failed" if failure else "passed"
            report["finished_at"] = timestamp()
            if failure:
                report["error"] = failure
            MAC.write_json(output / "runner.json", report)
    if failure:
        raise ValueError(failure + " Report: " + str(output / "runner.json"))
    print("Render checks passed. Open " + str(output / "index.html"))
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--game-path", help="Steam game directory or Ultrapool.app")
    parser.add_argument("--output-path", help="New directory for screenshots, gallery and runner.json")
    parser.add_argument("--timeout-seconds", type=int, default=180, help="Watchdog, 30–300 seconds (default: 180)")
    options = vars(parser.parse_args())
    if sys.platform != "darwin":
        parser.error("This harness requires macOS. Use Capture-Screens.cmd on Windows.")
    try:
        capture(**options)
    except (OSError, ValueError, subprocess.SubprocessError, plistlib.InvalidFileException) as error:
        print("Ultrapool Together: " + str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
