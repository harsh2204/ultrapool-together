"""Installer checks using fake app bundles; never launches Ultrapool or Godot."""

import importlib.util
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


REPO = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("mac_installer", REPO / "MacOS.py")
MAC = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MAC)


class MacInstallationTests(unittest.TestCase):
    def setUp(self):
        parent = REPO / ".local/installer-tests"
        parent.mkdir(parents=True, exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(prefix="mac-", dir=parent)
        self.root = Path(self.temp.name)
        self.package = self.root / 'package [test] "quoted"'
        self.game = self.root / "game [test]"
        self.app = self.game / "Ultrapool.app"
        self.install_root = self.game / 'UltrapoolTogether "quoted"'
        self.user_data = self.root / "user data [test]"
        self.vanilla = self.user_data / "Godot/app_userdata/Ultrapool"
        self.profile = self.user_data / "UltrapoolTogether"
        (self.package / "mod").mkdir(parents=True)
        (self.package / "mod/main.gd").write_text("extends Node\n")
        for name in ("MacOS.py", "Install.command", "Launch.command", "Uninstall.command"):
            shutil.copy2(REPO / name, self.package / name)
        contents = self.app / "Contents"
        for directory in ("MacOS", "Resources", "Frameworks", "_CodeSignature"):
            (contents / directory).mkdir(parents=True)
        with (contents / "Info.plist").open("wb") as target:
            plistlib.dump({"CFBundleExecutable": "Ultrapool", "CFBundleShortVersionString": "0.15.7"}, target)
        # This file is an inert fixture, never a real engine executable.
        (self.app / MAC.EXECUTABLE).write_text("native executable fixture\n")
        (self.app / MAC.EXECUTABLE).chmod(0o755)
        for relative in ("Resources/Ultrapool.pck", "Frameworks/libsteam_api.dylib",
                         "Frameworks/libgodotsteam.macos.template_release.dylib", "_CodeSignature/CodeResources"):
            (contents / relative).write_text("fixture " + relative)
        self.write_save(self.vanilla / "save.tres", "Steam progress")
        self.write_save(self.vanilla / "save.bak.tres", "Steam backup")
        (self.vanilla / "run_data.tres").write_text("unfinished solo run")
        self.original = self.snapshot(self.game)
        self.original_saves = self.snapshot(self.vanilla)
        self.closed = patch.object(MAC, "assert_game_closed")
        self.signer = patch.object(MAC, "sign_bundle")
        self.closed.start()
        self.sign = self.signer.start()

    def tearDown(self):
        self.signer.stop()
        self.closed.stop()
        self.temp.cleanup()

    @staticmethod
    def write_save(path, tag):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text('[gd_resource type="Resource" script_class="SaveData" format=3]\n; ' + tag)

    @staticmethod
    def snapshot(root):
        return {str(path.relative_to(root)): path.read_bytes() for path in root.rglob("*") if path.is_file()}

    def install(self, **options):
        defaults = dict(game_path=self.app, destination=self.install_root,
                        user_data_root=self.user_data, package_root=self.package)
        defaults.update(options)
        return MAC.install(**defaults)

    def test_install_update_and_uninstall_preserve_vanilla_and_saves(self):
        self.write_save(self.profile / "save.tres", "old mod save")
        self.write_save(self.profile / "save.bak.tres", "old mod backup")
        old_progress = self.snapshot(self.profile)
        self.install(dry_run=True)
        self.assertFalse(self.install_root.exists())
        self.assertEqual(self.snapshot(self.profile), old_progress)
        self.sign.assert_not_called()
        self.install()
        self.sign.assert_called_once_with(self.install_root / "Ultrapool.app")
        self.assertEqual(self.snapshot(self.app), {name.removeprefix("Ultrapool.app/"): data for name, data in self.original.items()})
        self.assertEqual(self.snapshot(self.vanilla), self.original_saves)
        for name in ("save.tres", "save.bak.tres"):
            self.assertEqual((self.profile / name).read_bytes(), self.original_saves["save.tres"])
        self.assertFalse((self.profile / "run_data.tres").exists())
        import_marker = json.loads((self.profile / MAC.IMPORT_MARKER).read_text())
        self.assertEqual(self.snapshot(Path(import_marker["previous_mod_progress"])), old_progress)
        runtime = self.install_root / "Ultrapool.app/Contents/MacOS"
        override = (runtime / "override.cfg").read_text()
        self.assertIn('config/custom_user_dir_name="UltrapoolTogether"', override)
        self.assertIn(json.dumps("*" + str(self.install_root / "mod/main.gd")), override)
        self.assertEqual((runtime / "steam_appid.txt").read_text(), "4195110\n")
        self.assertTrue(os.access(self.install_root / "Launch.command", os.X_OK))
        self.write_save(self.profile / "save.tres", "mod progress after playing")
        before_update = self.snapshot(self.profile)
        (self.install_root / "user-note.txt").write_text("preserve me")
        self.install()
        self.assertEqual(self.snapshot(self.profile), before_update)
        self.assertEqual((self.install_root / "user-note.txt").read_text(), "preserve me")
        MAC.uninstall(self.install_root, dry_run=True)
        self.assertTrue(runtime.is_dir())
        MAC.uninstall(self.install_root)
        self.assertEqual(self.snapshot(self.install_root), {"user-note.txt": b"preserve me"})
        self.assertEqual(self.snapshot(self.app), {name.removeprefix("Ultrapool.app/"): data for name, data in self.original.items()})
        self.assertEqual(self.snapshot(self.vanilla), self.original_saves)
        self.assertEqual(self.snapshot(self.profile), before_update)

    def test_missing_or_invalid_saves(self):
        (self.vanilla / "save.tres").write_text("not a save")
        with self.assertRaisesRegex(ValueError, "unrecognized"):
            self.install()
        self.assertFalse(self.install_root.exists())
        (self.vanilla / "save.tres").unlink()
        self.install()
        self.assertFalse(self.profile.exists())

    def test_upgrade_removes_only_obsolete_owned_files(self):
        obsolete = self.package / "mod/retired.gd"
        obsolete.write_text("extends Node # previous version\n")
        self.install()
        retired = self.install_root / "mod/retired.gd"
        unowned = self.install_root / "mod/personal.txt"
        unowned.write_text("preserve this nested file")
        (self.profile / "run_data.tres").write_text("unfinished mod run")
        saves = self.snapshot(self.profile)
        obsolete.unlink()
        marker = self.install_root / MAC.MANIFEST
        record = json.loads(marker.read_text())
        # Equivalent spelling must not turn a retained file into a stale target.
        record["files"].remove("mod/main.gd")
        record["files"].append("mod/./main.gd")
        marker.write_text(json.dumps(record))
        before = self.snapshot(self.install_root)
        self.install(dry_run=True)
        self.assertEqual(self.snapshot(self.install_root), before)
        self.install()
        self.assertFalse(retired.exists())
        self.assertEqual(unowned.read_text(), "preserve this nested file")
        self.assertEqual((self.install_root / "mod/main.gd").read_text(), "extends Node\n")
        self.assertNotIn("mod/retired.gd", json.loads(marker.read_text())["files"])
        self.assertEqual(self.snapshot(self.profile), saves)
        self.assertEqual(self.snapshot(self.vanilla), self.original_saves)
        self.install()
        self.assertEqual(self.snapshot(self.profile), saves)

    def test_failed_stale_cleanup_remains_retryable(self):
        obsolete = self.package / "mod/retired.gd"
        obsolete.write_text("previous version")
        self.install()
        obsolete.unlink()
        retired = self.install_root / "mod/retired.gd"
        marker = self.install_root / MAC.MANIFEST
        native_unlink = Path.unlink

        def fail_retired(path, *args, **kwargs):
            if path == retired:
                raise PermissionError("fixture cannot remove retired file")
            return native_unlink(path, *args, **kwargs)

        self.sign.reset_mock()
        with patch.object(Path, "unlink", fail_retired), self.assertRaises(PermissionError):
            self.install()
        failed = json.loads(marker.read_text())
        self.assertEqual(failed["state"], "installing")
        self.assertIn("mod/retired.gd", failed["files"])
        self.assertTrue(retired.is_file())
        self.sign.assert_not_called()
        self.install()
        self.assertFalse(retired.exists())
        self.assertEqual(json.loads(marker.read_text())["state"], "installed")

    def test_stale_link_rejected_before_upgrade(self):
        obsolete = self.package / "mod/retired.gd"
        obsolete.write_text("previous version")
        self.install()
        obsolete.unlink()
        retired = self.install_root / "mod/retired.gd"
        retired.unlink()
        outside = self.root / "personal.txt"
        outside.write_text("must survive")
        retired.symlink_to(outside)
        marker = self.install_root / MAC.MANIFEST
        before = marker.read_bytes()
        (self.package / "mod/main.gd").write_text("updated source")
        with self.assertRaisesRegex(ValueError, "Symbolic links"):
            self.install()
        self.assertTrue(retired.is_symlink())
        self.assertEqual(outside.read_text(), "must survive")
        self.assertEqual(marker.read_bytes(), before)
        self.assertEqual((self.install_root / "mod/main.gd").read_text(), "extends Node\n")

    def test_discovery_in_external_steam_library(self):
        steam = self.root / "steam"
        library = self.root / "external library"
        (steam / "steamapps").mkdir(parents=True)
        (library / "steamapps/common/Ultrapool").mkdir(parents=True)
        (steam / "steamapps/libraryfolders.vdf").write_text('"path" "' + str(library) + '"')
        (library / "steamapps/appmanifest_4195110.acf").write_text('"installdir" "Ultrapool"')
        shutil.copytree(self.app, library / "steamapps/common/Ultrapool/Ultrapool.app")
        self.assertEqual(MAC.find_game(steam), library / "steamapps/common/Ultrapool/Ultrapool.app")

    def test_reject_unsafe_destinations_and_unowned_files(self):
        for destination in (self.game, self.app, self.app / "mod", self.package, self.package / "mod-copy", self.root):
            with self.subTest(destination=destination), self.assertRaises(ValueError):
                self.install(destination=destination)
        self.install_root.mkdir()
        (self.install_root / "notes.txt").write_text("unowned")
        with self.assertRaises(ValueError):
            self.install()
        shutil.rmtree(self.install_root)
        self.install()
        (self.package / "mod/new.gd").write_text("extends Node")
        (self.install_root / "mod/new.gd").write_text("owned by user")
        with self.assertRaisesRegex(ValueError, "unowned"):
            self.install()
        self.assertEqual((self.install_root / "mod/new.gd").read_text(), "owned by user")

    def test_links_rejected_before_any_write(self):
        target = self.root / "unrelated"
        target.mkdir()
        (target / "save.tres").write_text("must survive")
        self.profile.parent.mkdir(parents=True, exist_ok=True)
        self.profile.symlink_to(target, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, "Symbolic links"):
            self.install()
        self.assertFalse(self.install_root.exists())
        self.profile.unlink()
        (self.package / "mod/linked").symlink_to(target, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, "Symbolic links"):
            self.install()
        self.assertFalse(self.install_root.exists())
        self.assertEqual(self.snapshot(target), {"save.tres": b"must survive"})

    def test_manifest_escape_and_replaced_directory_rejected(self):
        self.install()
        marker = self.install_root / MAC.MANIFEST
        record = json.loads(marker.read_text())
        for invalid in ("../../outside.txt", "/tmp/outside", ".", MAC.MANIFEST):
            changed = dict(record, files=record["files"] + [invalid])
            marker.write_text(json.dumps(changed))
            before = self.snapshot(self.install_root)
            with self.subTest(invalid=invalid), self.assertRaises(ValueError):
                self.install()
            self.assertEqual(self.snapshot(self.install_root), before)
            with self.subTest(invalid=invalid), self.assertRaises(ValueError):
                MAC.uninstall(self.install_root)
            self.assertTrue((self.install_root / "mod/main.gd").exists())
        marker.write_text(json.dumps(record))
        script = self.install_root / "mod/main.gd"
        script.unlink()
        script.mkdir()
        with self.assertRaisesRegex(ValueError, "directory"):
            self.install()
        with self.assertRaisesRegex(ValueError, "directory"):
            MAC.uninstall(self.install_root)

    def test_failed_signing_marks_partial_install_and_does_not_import(self):
        self.sign.side_effect = subprocess.CalledProcessError(1, "codesign")
        with self.assertRaises(subprocess.CalledProcessError):
            self.install()
        self.assertEqual(json.loads((self.install_root / MAC.MANIFEST).read_text())["state"], "installing")
        self.assertFalse(self.profile.exists())
        self.assertEqual(self.snapshot(self.vanilla), self.original_saves)
        self.sign.side_effect = None
        self.install()
        self.assertEqual(json.loads((self.install_root / MAC.MANIFEST).read_text())["state"], "installed")

    def test_native_game_validation(self):
        info_path = self.app / "Contents/Info.plist"
        original = info_path.read_bytes()
        info_path.write_bytes(plistlib.dumps({"CFBundleExecutable": "Ultrapool", "CFBundleShortVersionString": "9.0"}))
        with self.assertRaisesRegex(ValueError, "supports Ultrapool"):
            self.install()
        info_path.write_bytes(original)
        override = self.app / "Contents/MacOS/override.cfg"
        override.write_text("unrelated mod")
        with self.assertRaisesRegex(ValueError, "local override"):
            self.install()

    def test_signing_preserves_native_entitlements(self):
        self.signer.stop()
        try:
            with patch.object(MAC, "strip_bundle_finder_metadata"), patch.object(MAC.subprocess, "run") as run:
                MAC.sign_bundle(self.app)
            self.assertEqual(run.call_count, 2)
            self.assertIn("--preserve-metadata=entitlements,flags,runtime", run.call_args_list[0].args[0])
            self.assertIn("--verify", run.call_args_list[1].args[0])
            self.assertEqual(run.call_args_list[0].args[0][-1], str(self.app))
        finally:
            self.sign = self.signer.start()

    @unittest.skipUnless(sys.platform == "darwin", "macOS codesign fixture")
    def test_real_codesign_on_inert_system_binary_copy(self):
        # A disposable copy of /usr/bin/true supplies Mach-O bytes for codesign.
        # It is never executed; no game binary or user profile is involved.
        app = self.root / "SignatureFixture.app"
        (app / "Contents/MacOS").mkdir(parents=True)
        binary = app / "Contents/MacOS/Fixture"
        shutil.copyfile("/usr/bin/true", binary)
        binary.chmod(0o755)
        (app / "Contents/Info.plist").write_bytes(plistlib.dumps({
            "CFBundleExecutable": "Fixture", "CFBundleIdentifier": "local.ultrapool.installer.fixture",
            "CFBundlePackageType": "APPL",
        }))
        (app / "Contents/MacOS/override.cfg").write_text('[application]\nconfig/name="Fixture"\n')
        (app / "Contents/MacOS/steam_appid.txt").write_text("4195110\n")
        # Simulate a Steam/Finder copy carrying metadata that codesign rejects.
        original = self.root / "original-resource.dat"
        original.write_bytes(b"original resource")
        finder_info = b"TEST" + bytes(28)
        def set_attribute(path, name, data):
            subprocess.run(["/usr/bin/xattr", "-wx", name, data.hex(), str(path)], check=True)

        def get_attribute(path, name):
            result = subprocess.run(["/usr/bin/xattr", "-px", name, str(path)], check=True,
                                    capture_output=True, text=True)
            return bytes.fromhex(result.stdout)

        set_attribute(original, "com.apple.FinderInfo", finder_info)
        set_attribute(original, "com.apple.ResourceFork", b"fixture fork")
        set_attribute(original, "org.ultrapool.fixture", b"preserve metadata")
        resource = app / "Contents/resource.dat"
        shutil.copy2(original, resource)
        # Python builds vary in copied xattr support; seed the private copy too.
        set_attribute(resource, "com.apple.FinderInfo", finder_info)
        set_attribute(resource, "com.apple.ResourceFork", b"fixture fork")
        set_attribute(resource, "org.ultrapool.fixture", b"preserve metadata")
        set_attribute(app, "com.apple.FinderInfo", finder_info)
        self.signer.stop()
        try:
            MAC.sign_bundle(app)
        finally:
            self.sign = self.signer.start()
        self.assertTrue((app / "Contents/_CodeSignature/CodeResources").is_file())
        for path in (app, resource):
            attributes = subprocess.run(["/usr/bin/xattr", str(path)], check=True,
                                        capture_output=True, text=True).stdout.splitlines()
            self.assertNotIn("com.apple.FinderInfo", attributes)
            self.assertNotIn("com.apple.ResourceFork", attributes)
        self.assertEqual(get_attribute(resource, "org.ultrapool.fixture"), b"preserve metadata")
        self.assertEqual(get_attribute(original, "com.apple.FinderInfo"), finder_info)
        self.assertEqual(get_attribute(original, "com.apple.ResourceFork"), b"fixture fork")


if __name__ == "__main__":
    unittest.main()
