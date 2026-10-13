#!/bin/bash
# macOS: çift tıklayın (ya da Terminal'de: bash kurulum.sh). Ayrıntılar setup/bootstrap.sh içinde.
cd "$(dirname "$0")" || exit 1
xattr -cr . 2>/dev/null   # internetten inen dosyalardaki "karantina" işaretini kaldırır
bash kurulum.sh "$@"
code=$?
if [ "$code" -ne 0 ]; then
    read -r -p "Kapatmak için Enter'a bas…" _
fi
exit "$code"
