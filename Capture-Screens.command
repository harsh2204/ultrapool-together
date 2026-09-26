#!/bin/bash
set -euo pipefail
source_root="$(cd -- "$(dirname -- "$0")" && pwd -P)"
exec python3 "$source_root/Capture-Screens.py" "$@"
