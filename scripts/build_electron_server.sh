#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
output="$project_root/dist/micro-space-empire-electron-server"
library_dir="$project_root/dist/micro-space-empire-electron-libs"
cache_dir=$(mktemp -d "${TMPDIR:-/tmp}/mse-electron-crystal.XXXXXX")
trap 'rm -rf "$cache_dir"' EXIT HUP INT TERM

if [ "$(uname -s)" != Linux ]; then
  echo 'The Electron prototype currently builds on Linux only.' >&2
  exit 1
fi
if [ ! -d "$project_root/lib/kemal" ] || [ ! -d "$project_root/lib/sqlite3" ]; then
  echo 'Install Crystal dependencies first with make setup.' >&2
  exit 1
fi

mkdir -p "$project_root/dist"
cd "$project_root"
CRYSTAL_CACHE_DIR="$cache_dir" crystal build --release --no-debug -D standalone \
  src/micro_space_empire.cr -o "$output"
if command -v strip >/dev/null 2>&1; then
  strip --strip-unneeded "$output"
fi
mkdir -p "$library_dir"
ldd "$output" | awk '$2 == "=>" && $3 ~ /^\// && $1 !~ /^(libc|libm|libgcc_s|libpthread|libdl|librt|libresolv)\.so/ { print $1, $3 }' |
  while read -r name source; do
    cp -L "$source" "$library_dir/$name"
  done
echo "Built $output"
