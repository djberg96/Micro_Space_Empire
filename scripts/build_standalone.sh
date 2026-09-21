#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
dist_dir="$project_root/dist"
server_output="$dist_dir/micro-space-empire-server"
app_bundle="$dist_dir/Micro Space Empire.app"
app_macos="$app_bundle/Contents/MacOS"
app_resources="$app_bundle/Contents/Resources"
archive_dir=$(mktemp -d "${TMPDIR:-/tmp}/mse-static-libs.XXXXXX")
trap 'rm -rf "$archive_dir"' EXIT HUP INT TERM

if [ "$(uname -s)" != "Darwin" ]; then
  echo "The standalone builder currently supports macOS only." >&2
  exit 1
fi

if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew is required to locate the static native libraries." >&2
  exit 1
fi

copy_archive() {
  formula=$1
  archive=$2
  prefix=$(brew --prefix "$formula")
  source_path="$prefix/lib/$archive"
  if [ ! -f "$source_path" ]; then
    echo "Missing $source_path; install or reinstall $formula." >&2
    exit 1
  fi
  cp "$source_path" "$archive_dir/$archive"
}

copy_archive sqlite libsqlite3.a
copy_archive openssl@3 libssl.a
copy_archive openssl@3 libcrypto.a
copy_archive pcre2 libpcre2-8.a
copy_archive bdw-gc libgc.a

mkdir -p "$dist_dir"
cd "$project_root"
CRYSTAL_LIBRARY_PATH="$archive_dir${CRYSTAL_LIBRARY_PATH:+:$CRYSTAL_LIBRARY_PATH}" \
  crystal build --release --no-debug -D standalone src/micro_space_empire.cr -o "$server_output"

if otool -L "$server_output" | grep -E '/(opt|usr/local)/' >/dev/null; then
  echo "Standalone verification failed: $server_output still refers to package-manager libraries." >&2
  otool -L "$server_output" >&2
  exit 1
fi

rm -rf "$app_bundle"
mkdir -p "$app_macos" "$app_resources"
cp src/macos/Info.plist "$app_bundle/Contents/Info.plist"
cp "$server_output" "$app_resources/micro-space-empire-server"
swiftc -O -swift-version 5 -framework Cocoa -framework WebKit \
  src/macos/MicroSpaceEmpireApp.swift -o "$app_macos/Micro Space Empire"
codesign --force --deep --sign - "$app_bundle" >/dev/null
codesign --verify --deep --strict "$app_bundle"

echo "Built $app_bundle"
echo "Headless server: $server_output"
otool -L "$server_output"
