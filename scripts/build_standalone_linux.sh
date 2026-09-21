#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
architecture=$(uname -m)
dist_dir="$project_root/dist"
output="$dist_dir/micro-space-empire-fedora-$architecture"
server_output="$dist_dir/micro-space-empire-server-fedora-$architecture"
link_dir=$(mktemp -d "${TMPDIR:-/tmp}/mse-link-libs.XXXXXX")
cache_dir=$(mktemp -d "${TMPDIR:-/tmp}/mse-crystal-cache.XXXXXX")
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/mse-linux-app.XXXXXX")
trap 'rm -rf "$link_dir" "$cache_dir" "$build_dir"' EXIT HUP INT TERM

if [ "$(uname -s)" != "Linux" ]; then
  echo "The Linux standalone builder must run on Linux." >&2
  exit 1
fi

if ! command -v crystal >/dev/null 2>&1; then
  echo "Crystal is required to build the executable." >&2
  exit 1
fi

for command in gcc ld ldconfig; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "$command is required to build the desktop executable." >&2
    exit 1
  fi
done

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
    src/micro_space_empire.cr -o "$server_output"

if command -v strip >/dev/null 2>&1; then
  strip --strip-unneeded "$server_output"
fi

cp "$server_output" "$build_dir/micro_space_empire_server"
(cd "$build_dir" && ld -r -b binary -o embedded_server.o micro_space_empire_server)

runtime_library() {
  library_name=$1
  library_path=$(ldconfig -p 2>/dev/null | awk -v name="$library_name" '$1 == name { print $NF; exit }')
  if [ -z "$library_path" ] || [ ! -f "$library_path" ]; then
    echo "Could not find $library_name. Install Fedora's gtk4 and webkitgtk6.0 packages." >&2
    exit 1
  fi
  printf '%s\n' "$library_path"
}

gtk_library=$(runtime_library libgtk-4.so.1)
webkit_library=$(runtime_library libwebkitgtk-6.0.so.4)
gio_library=$(runtime_library libgio-2.0.so.0)
gobject_library=$(runtime_library libgobject-2.0.so.0)
glib_library=$(runtime_library libglib-2.0.so.0)

gcc -O2 -Wall -Wextra -Werror -Wl,-z,noexecstack \
  src/linux/MicroSpaceEmpireApp.c "$build_dir/embedded_server.o" \
  "$webkit_library" "$gtk_library" "$gio_library" "$gobject_library" "$glib_library" \
  -o "$output"

if command -v strip >/dev/null 2>&1; then
  strip --strip-unneeded "$output"
fi

echo "Built desktop app: $output"
echo "Headless server: $server_output"
file "$output"
ldd "$output"
