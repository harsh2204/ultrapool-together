#!/usr/bin/env python3
"""Build the same Windows/macOS source-only installation ZIP on either platform."""

from pathlib import Path
import tempfile
import zipfile


PACKAGE_FILES = (
    "mod", "docs", "Install.ps1", "Install.cmd", "Uninstall.ps1", "Launch.cmd",
    "Install.command", "Launch.command", "Uninstall.command", "MacOS.py", "README.md",
)


def build_package(root):
    files = []
    for name in PACKAGE_FILES:
        path = root / name
        if not path.exists():
            raise ValueError("Package file is missing: " + name)
        files.extend(sorted(path.rglob("*")) if path.is_dir() else [path])
    output = root / "dist"
    output.mkdir(exist_ok=True)
    with tempfile.NamedTemporaryFile(suffix=".zip", dir=output, delete=False) as handle:
        temporary = Path(handle.name)
    try:
        with zipfile.ZipFile(temporary, "w", compression=zipfile.ZIP_DEFLATED) as archive:
            for path in files:
                if path.is_symlink():
                    raise ValueError("Package contains a symbolic link: " + str(path))
                if not path.is_file():
                    continue
                relative = path.relative_to(root).as_posix()
                entry = zipfile.ZipInfo.from_file(path, relative)
                entry.create_system = 3
                entry.external_attr = (0o100755 if relative.endswith(".command") else 0o100644) << 16
                archive.writestr(entry, path.read_bytes(), compress_type=zipfile.ZIP_DEFLATED)
        archive_path = output / "UltrapoolTogether.zip"
        temporary.replace(archive_path)
        return archive_path
    finally:
        temporary.unlink(missing_ok=True)


if __name__ == "__main__":
    print("Created " + str(build_package(Path(__file__).resolve().parent)))
    print("This archive contains mod code and installers. Each player supplies their own installed game.")
