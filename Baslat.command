#!/bin/bash
# macOS: çift tıklayın (ya da Terminal'de: bash baslat.sh). Kapatmak için bu pencerede Ctrl+C.
cd "$(dirname "$0")" || exit 1
xattr -cr . 2>/dev/null
bash baslat.sh "$@"
