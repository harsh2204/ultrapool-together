#!/bin/bash
set -euo pipefail
install_root="$(cd -- "$(dirname -- "$0")" && pwd -P)"
if ! command -v python3 >/dev/null 2>&1; then
    echo 'Python 3 is required to uninstall Ultrapool Together.' >&2
    exit 1
fi
exec python3 "$install_root/MacOS.py" uninstall --destination "$install_root" "$@"
