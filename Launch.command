#!/bin/bash
set -euo pipefail
install_root="$(cd -- "$(dirname -- "$0")" && pwd -P)"
manifest="$install_root/ultrapool-together-install.json"
if [[ ! -f "$manifest" ]] || [[ "$(/usr/bin/plutil -extract state raw -o - "$manifest" 2>/dev/null || true)" != installed ]]; then
    echo 'Run Install.command first, then use Launch.command inside the installed UltrapoolTogether folder.' >&2
    exit 1
fi
if [[ "$(/usr/bin/plutil -extract install_root raw -o - "$manifest")" != "$install_root" ]]; then
    echo 'The installation has moved. Move it back to its installed location, or install into a new empty folder.' >&2
    exit 1
fi
cd -- "$install_root/Ultrapool.app/Contents/MacOS"
exec ./Ultrapool "$@"
