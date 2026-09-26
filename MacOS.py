#!/usr/bin/env python3
"""Install a private macOS game copy. This helper never launches the game."""

import argparse
import datetime
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import uuid


MOD_ID = "UltrapoolTogether"
MANIFEST = "ultrapool-together-install.json"
IMPORT_MARKER = "ultrapool-together-progress-import.json"
APP_NAME = "Ultrapool.app"
EXECUTABLE = "Contents/MacOS/Ultrapool"
GAME_VERSION = "0.15.7"
STEAM_BUILD = "25298901"


def full_path(value):
    # Do not resolve links before checking them; that would hide unsafe paths.
    return Path(os.path.abspath(os.path.expanduser(str(value))))


def plain_path(path):
    for current in (path, *path.parents):
        if current.is_symlink():
            raise ValueError("Symbolic links are not supported for installation paths: " + str(current))


def inside(path, root):
    return path != root and root in path.parents


def files_under(root):
    plain_path(root)
    result = []
    for path in sorted(root.rglob("*")):
        plain_path(path)
        if path.is_file():
            result.append(path)
        elif not path.is_dir():
            raise ValueError("Unsupported special file: " + str(path))
    return result


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def write_json(path, data):
    temporary = path.with_name(path.name + "." + uuid.uuid4().hex + ".tmp")
    try:
        temporary.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)


def find_game(steam_root=None):
    steam_root = full_path(steam_root or Path.home() / "Library/Application Support/Steam")
    libraries = [steam_root]
    library_file = steam_root / "steamapps/libraryfolders.vdf"
    if library_file.is_file():
        libraries.extend(full_path(value.replace("\\\\", "\\")) for value in
                         re.findall(r'"path"\s+"([^"]+)"', library_file.read_text(encoding="utf-8")))
    for library in dict.fromkeys(libraries):
        manifest = library / "steamapps/appmanifest_4195110.acf"
        if not manifest.is_file():
            continue
        match = re.search(r'"installdir"\s+"([^"]+)"', manifest.read_text(encoding="utf-8"))
        if match:
            candidate = library / "steamapps/common" / match.group(1) / APP_NAME
            if (candidate / EXECUTABLE).is_file():
                return candidate
    raise ValueError("Ultrapool was not found in Steam. Pass --game-path '/path/to/Ultrapool.app'.")


def inspect_game(game_path):
    app = full_path(game_path)
    if app.suffix != ".app":
        app = app / APP_NAME
    plain_path(app)
    required = ("Contents/Info.plist", EXECUTABLE, "Contents/Resources/Ultrapool.pck",
                "Contents/Frameworks/libsteam_api.dylib",
                "Contents/Frameworks/libgodotsteam.macos.template_release.dylib")
    for relative in required:
        source = app / relative
        plain_path(source)
        if not source.is_file():
            raise ValueError("Missing native macOS game file: " + str(source))
    with (app / "Contents/Info.plist").open("rb") as source:
        info = plistlib.load(source)
    if info.get("CFBundleExecutable") != "Ultrapool":
        raise ValueError("Unsupported Ultrapool app executable.")
    if info.get("CFBundleShortVersionString") != GAME_VERSION:
        raise ValueError("This mod supports Ultrapool " + GAME_VERSION + "; install a compatible mod release.")
    if not os.access(app / EXECUTABLE, os.X_OK):
        raise ValueError("The native Ultrapool executable is not executable. Repair the game in Steam.")
    for relative in ("Contents/MacOS/override.cfg", "Contents/MacOS/steam_appid.txt"):
        if (app / relative).exists():
            raise ValueError("The source app has a local override; use an unmodified Steam copy: " + relative)
    return app


def validate_marker(root):
    marker = root / MANIFEST
    plain_path(marker)
    if not marker.is_file():
        raise ValueError("No Ultrapool Together installation marker at " + str(root))
    data = json.loads(marker.read_text(encoding="utf-8"))
    if (data.get("schema") != 1 or data.get("mod_id") != MOD_ID or data.get("platform") != "macos"
            or full_path(data.get("install_root", "")) != root):
        raise ValueError("The existing installation marker does not match this destination.")
    game = full_path(data.get("game_root", ""))
    if root == Path(root.anchor) or root == game or inside(game, root):
        raise ValueError("The installation marker points at the original game or an unsafe root.")
    files = data.get("files")
    if not isinstance(files, list) or any(not isinstance(name, str) for name in files):
        raise ValueError("Invalid owned-file list in the installation marker.")
    for name in files:
        relative = Path(name)
        if not name or relative.is_absolute() or ".." in relative.parts or name == MANIFEST:
            raise ValueError("Invalid owned path in the installation marker: " + name)
        target = full_path(root / relative)
        if not inside(target, root):
            raise ValueError("Owned path escapes the mod directory: " + name)
        plain_path(target)
        if target.exists() and not target.is_file():
            raise ValueError("An expected installed file is now a directory: " + str(target))
    return data


def assert_game_closed():
    result = subprocess.run(["/bin/ps", "-axo", "comm="], check=True, capture_output=True, text=True)
    if any(Path(line.strip()).name == "Ultrapool" for line in result.stdout.splitlines()):
        raise ValueError("Close Ultrapool and Ultrapool Together before installing or uninstalling.")


def plan_import(user_data_root):
    source = user_data_root / "Godot/app_userdata/Ultrapool/save.tres"
    profile = user_data_root / MOD_ID
    marker = profile / IMPORT_MARKER
    for path in (source, profile, marker, profile / "save-import-backups",
                 profile / "save.tres", profile / "save.bak.tres"):
        plain_path(path)
        if path.exists() and path in (source, marker, profile / "save.tres", profile / "save.bak.tres") and not path.is_file():
            raise ValueError("An expected save file is a directory: " + str(path))
    if marker.exists() or not source.is_file():
        return None
    # Read once so both recovery files receive the same snapshot even if the source changes.
    contents = source.read_bytes()
    first_line = contents.decode("utf-8-sig").splitlines()[0] if contents else ""
    if not first_line.startswith("[gd_resource ") or 'script_class="SaveData"' not in first_line:
        raise ValueError("The Steam progression save is empty or unrecognized. Existing saves were not changed.")
    return source, profile, contents


def import_progress(plan):
    if plan is None:
        return
    source, profile, contents = plan
    backup = profile / "save-import-backups" / (datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ-") + uuid.uuid4().hex)
    backup.mkdir(parents=True)
    for name in ("save.tres", "save.bak.tres"):
        target = profile / name
        if target.is_file():
            shutil.copy2(target, backup / name)
    for name in ("save.bak.tres", "save.tres"):
        target = profile / name
        temporary = profile / (name + "." + uuid.uuid4().hex + ".tmp")
        try:
            temporary.write_bytes(contents)
            temporary.replace(target)
        finally:
            temporary.unlink(missing_ok=True)
    write_json(profile / IMPORT_MARKER, {
        "schema": 1, "imported_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "source": str(source), "source_sha256": hashlib.sha256(contents).hexdigest(),
        "previous_mod_progress": str(backup),
    })
    print("Imported Steam progression once. Previous mod progress backup: " + str(backup))


def strip_bundle_finder_metadata(app):
    # Finder metadata can be inherited by copy2/copytree and is forbidden in a
    # signed bundle. Strip only those two attributes, retaining quarantine and
    # all other metadata. Validate before traversing so links cannot escape it.
    files_under(app)
    for path in (app, *app.rglob("*")):
        attributes = subprocess.run(["/usr/bin/xattr", str(path)], check=True,
                                    capture_output=True, text=True).stdout.splitlines()
        for attribute in ("com.apple.FinderInfo", "com.apple.ResourceFork"):
            if attribute in attributes:
                subprocess.run(["/usr/bin/xattr", "-d", attribute, str(path)], check=True)


def sign_bundle(app):
    # Added Godot configuration changes the copied app's resource seal. Only this
    # private copy is signed; neither Steam's app nor system security is changed.
    strip_bundle_finder_metadata(app)
    subprocess.run(["/usr/bin/codesign", "--force", "--deep", "--sign", "-",
                    "--preserve-metadata=entitlements,flags,runtime", str(app)], check=True)
    subprocess.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(app)], check=True)


def install(game_path=None, destination=None, user_data_root=None, dry_run=False, package_root=None):
    package = full_path(package_root or Path(__file__).parent)
    app = inspect_game(game_path or find_game())
    game_root = app.parent
    root = full_path(destination or game_root / MOD_ID)
    user_data = full_path(user_data_root or Path.home() / "Library/Application Support")
    if (root == Path(root.anchor) or root in (game_root, app, package)
            or inside(game_root, root) or inside(app, root) or inside(package, root)
            or inside(root, app) or inside(root, package)):
        raise ValueError("The destination must be a dedicated mod directory, separate from the game app and package.")
    plain_path(root)
    for name in ("mod/main.gd", "Launch.command", "Uninstall.command", "MacOS.py"):
        path = package / name
        plain_path(path)
        if not path.is_file():
            raise ValueError("Extract the complete package; missing file: " + name)
    previous = validate_marker(root) if root.exists() else None
    previous_files = {Path(name).as_posix() for name in previous["files"]} if previous else set()
    app_files = files_under(app)
    mod_files = files_under(package / "mod")
    copies = [(source, Path(APP_NAME) / source.relative_to(app)) for source in app_files]
    copies.extend((source, source.relative_to(package)) for source in mod_files)
    copies.extend((package / name, Path(name)) for name in ("Launch.command", "Uninstall.command", "MacOS.py"))
    generated = {APP_NAME + "/Contents/MacOS/override.cfg", APP_NAME + "/Contents/MacOS/steam_appid.txt",
                 APP_NAME + "/Contents/_CodeSignature/CodeResources"}
    owned = {relative.as_posix() for _, relative in copies} | generated
    for relative in owned:
        target = root / relative
        plain_path(target)
        if target.exists() and (relative not in previous_files or not target.is_file()):
            raise ValueError("Installation would replace an unowned file or directory: " + str(target))
    # Inspect all existing app paths before codesign recursively accesses the copy.
    if root.exists():
        files_under(root)
    assert_game_closed()
    progress = plan_import(user_data)
    if dry_run:
        print("Would install Ultrapool Together to " + str(root))
        return root
    root.mkdir(parents=True, exist_ok=True)
    record = {
        "schema": 1, "mod_id": MOD_ID, "platform": "macos", "install_root": str(root),
        "game_root": str(game_root), "installed_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "state": "installing", "source_exe_sha256": sha256(app / EXECUTABLE),
        "supported_game_version": GAME_VERSION, "supported_steam_build": STEAM_BUILD,
        "files": sorted(previous_files | owned),
    }
    write_json(root / MANIFEST, record)
    for source, relative in copies:
        target = root / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
    executable_dir = root / APP_NAME / "Contents/MacOS"
    # JSON string escaping is compatible with Godot config strings (quotes, slashes,
    # newlines); absolute paths are required for scripts outside the native PCK.
    autoload = json.dumps("*" + str(root / "mod/main.gd"), ensure_ascii=False)
    (executable_dir / "override.cfg").write_text(
        '[application]\nconfig/name="Ultrapool Together"\nconfig/use_custom_user_dir=true\n'
        'config/custom_user_dir_name="UltrapoolTogether"\n\n[autoload]\nUltrapoolTogether=' + autoload + "\n",
        encoding="utf-8")
    (executable_dir / "steam_appid.txt").write_text("4195110\n", encoding="ascii")
    for name in ("Launch.command", "Uninstall.command"):
        (root / name).chmod(0o755)
    # Keep the union in the in-progress manifest until every removal succeeds,
    # so an interrupted update remains retryable and uninstallable. Never recurse
    # through an obsolete directory or infer ownership from its parent folder.
    for relative in sorted(previous_files - owned):
        target = root / relative
        plain_path(target)
        target.unlink(missing_ok=True)
    sign_bundle(root / APP_NAME)
    import_progress(progress)
    record["files"] = sorted(owned)
    record["state"] = "installed"
    write_json(root / MANIFEST, record)
    print("Installed Ultrapool Together to " + str(root))
    print("Launch with " + str(root / "Launch.command"))
    return root


def uninstall(destination, dry_run=False):
    root = full_path(destination)
    plain_path(root)
    record = validate_marker(root)
    assert_game_closed()
    if dry_run:
        print("Would remove only recorded mod files from " + str(root))
        return
    directories = {root}
    for relative in record["files"]:
        target = root / relative
        target.unlink(missing_ok=True)
        directories.update(parent for parent in target.parents if parent == root or inside(parent, root))
    (root / MANIFEST).unlink()
    for directory in sorted(directories, key=lambda path: len(path.parts), reverse=True):
        if directory.is_dir() and not any(directory.iterdir()):
            directory.rmdir()
    print("Removed Ultrapool Together. Original game, saves, and unowned files are preserved.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    installer = commands.add_parser("install")
    installer.add_argument("--game-path", help="Steam game folder or Ultrapool.app")
    installer.add_argument("--destination", help="Dedicated mod folder")
    installer.add_argument("--user-data-root", help="Application Support root (primarily for isolated fixture tests)")
    installer.add_argument("--dry-run", action="store_true")
    uninstaller = commands.add_parser("uninstall")
    uninstaller.add_argument("--destination", default=str(Path(__file__).parent))
    uninstaller.add_argument("--dry-run", action="store_true")
    options = vars(parser.parse_args())
    command = options.pop("command")
    if sys.platform != "darwin":
        parser.error("These installers require macOS. Use Install.cmd on Windows.")
    try:
        (install if command == "install" else uninstall)(**options)
    except (OSError, ValueError, subprocess.SubprocessError, plistlib.InvalidFileException) as error:
        print("Ultrapool Together: " + str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
