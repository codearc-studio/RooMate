#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
feed=${1:-"$repo_root/appcast.xml"}

if [ "$#" -ge 2 ]; then
    exec python3 "$repo_root/Scripts/validate_appcast.py" \
        "$feed" "$2" --info-plist "$repo_root/RooMate/Info.plist"
fi

exec python3 "$repo_root/Scripts/validate_appcast.py" \
    "$feed" --info-plist "$repo_root/RooMate/Info.plist"
