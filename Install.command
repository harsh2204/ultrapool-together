#!/bin/bash
set -euo pipefail
package_root="$(cd -- "$(dirname -- "$0")" && pwd -P)"
if ! command -v python3 >/dev/null 2>&1; then
    echo 'Python 3 is required to install Ultrapool Together. Install it from https://www.python.org/downloads/macos/ and try again.' >&2
    exit 1
fi
exec python3 "$package_root/MacOS.py" install "$@"
