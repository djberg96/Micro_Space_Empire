#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
architecture=$(uname -m)
dist_dir="$project_root/dist"
output="$dist_dir/micro-space-empire-fedora-$architecture"
link_dir=$(mktemp -d "${TMPDIR:-/tmp}/mse-link-libs.XXXXXX")
cache_dir=$(mktemp -d "${TMPDIR:-/tmp}/mse-crystal-cache.XXXXXX")
trap 'rm -rf "$link_dir" "$cache_dir"' EXIT HUP INT TERM

if [ "$(uname -s)" != "Linux" ]; then
  echo "The Linux standalone builder must run on Linux." >&2
  exit 1
fi

if ! command -v crystal >/dev/null 2>&1; then
  echo "Crystal is required to build the executable." >&2
  exit 1
fi

if [ ! -d "$project_root/lib/kemal" ] || [ ! -d "$project_root/lib/sqlite3" ]; then
  if ! command -v shards >/dev/null 2>&1; then
    echo "Shards is required to install the locked dependencies." >&2
    exit 1
  fi
  (cd "$project_root" && shards install --production)
fi

# Fedora's sqlite-libs package intentionally provides only the versioned runtime
# library. Give the linker its conventional name without requiring sqlite-devel.
sqlite_library=$(ldconfig -p 2>/dev/null | awk '$1 == "libsqlite3.so.0" { print $NF; exit }')
if [ -z "$sqlite_library" ] || [ ! -f "$sqlite_library" ]; then
  echo "Could not find libsqlite3.so.0; install Fedora's sqlite-libs package." >&2
  exit 1
fi
ln -s "$sqlite_library" "$link_dir/libsqlite3.so"

crystal_library_path=$(crystal env | sed -n 's/^CRYSTAL_LIBRARY_PATH=//p')
if [ -n "${CRYSTAL_LIBRARY_PATH:-}" ]; then
  crystal_library_path="$crystal_library_path:$CRYSTAL_LIBRARY_PATH"
fi

mkdir -p "$dist_dir"
cd "$project_root"
CRYSTAL_CACHE_DIR="$cache_dir" \
CRYSTAL_LIBRARY_PATH="$link_dir:$crystal_library_path" \
  crystal build --release --no-debug -D standalone \
    src/micro_space_empire.cr -o "$output"

if command -v strip >/dev/null 2>&1; then
  strip --strip-unneeded "$output"
fi

echo "Built $output"
file "$output"
ldd "$output"
