# Micro Space Empire

A local, solitaire web adaptation of Robert Bartelli's **Micro Space Empire v.93**, built with Crystal, Kemal, and SQLite.

## Run it

Requirements: Crystal 1.21+, SQLite 3, Poppler, and ImageMagick (the latter two are only needed to regenerate card assets).

```sh
make setup
make test
make dev
```

Open <http://127.0.0.1:3000>. New games begin unnamed; choose **Menu → Save Game** when you want to keep one. Named games are written to `var/micro_space_empire.db` and every subsequent action is autosaved. Set `MSE_DATABASE_PATH`, `MSE_HOST`, or `MSE_PORT` to override the local defaults.

Use the theme picker on the main menu or in the in-game menu to choose Starfield, Nebula, Tactical Blue, or the light Command Deck theme. The choice is kept in the browser and applies to every screen.

For an optimized binary:

```sh
make build
./bin/micro_space_empire
```

## Standalone macOS app

Build a self-contained desktop app containing the local server, rules manifests, interface assets, and all card artwork:

```sh
make standalone
open "dist/Micro Space Empire.app"
```

The app presents the game in a native macOS window with no browser chrome. Its private server starts and stops with the app, chooses an available local port automatically, and cannot accept remote connections. Saves live in `~/Library/Application Support/Micro Space Empire/`.

The standalone builder also produces `dist/micro-space-empire-server` for headless or automated use. Set `MSE_OPEN_BROWSER=true` if that server should open the default browser.

SQLite, OpenSSL, PCRE2, and the Boehm garbage collector are linked into the packaged server. The finished app therefore needs neither Crystal nor Homebrew on the destination Mac; only standard macOS frameworks and system libraries remain dynamic.

The generated executable targets the macOS version and architecture of the build Mac. Build on the oldest Mac you intend to support, and build once on each architecture if you need both Apple Silicon and Intel executables.

## Fedora standalone executable and Windows server executable

The native window under `src/macos/` is macOS-specific. The Crystal server itself is portable and already embeds the manifests, CSS, JavaScript, and card artwork. Linux and Windows builds therefore need only the resulting executable plus any native libraries described below. They run headlessly by default; set `MSE_OPEN_BROWSER=true` to open the game in the platform's default browser.

Build on the target operating system or in a matching CI/container runner. Crystal's [basic cross-compilation mode](https://crystal-lang.org/reference/latest/syntax_and_semantics/cross-compilation.html) emits an object file that must still be linked against the target system's libraries, so invoking it directly from macOS does not produce a finished Linux or Windows executable.

### Fedora Linux: native standalone executable

Build directly on Fedora—no Docker or Alpine image is needed. The desktop executable contains the private local server, native GTK/WebKit shell, rules manifests, interface assets, and card artwork, so it is the only application file you need to keep:

```sh
sudo dnf install crystal shards gcc binutils sqlite-devel openssl-devel pcre2-devel zlib-devel gtk4 webkitgtk6.0
shards install --production
make test
make standalone
```

The builder names the desktop app for the build machine's architecture, for example `dist/micro-space-empire-fedora-x86_64` or `dist/micro-space-empire-fedora-aarch64`. Launch it directly:

```sh
./dist/micro-space-empire-fedora-$(uname -m)
```

The app opens in its own window with no browser chrome. It starts its embedded server on an available loopback port, stops it when the window closes, and stores saves in `${XDG_DATA_HOME:-~/.local/share}/micro-space-empire/`. The build also leaves `dist/micro-space-empire-server-fedora-$(uname -m)` for command-line/headless use; set `MSE_OPEN_BROWSER=true` when running that server if it should open your default browser.

The executables are Fedora-native and dynamically use Fedora's standard GTK, WebKitGTK, SQLite, OpenSSL, zlib, PCRE2, C, and math runtime libraries; Crystal, Shards, the source tree, and the build toolchain are not needed to run them. Build on the oldest Fedora release you intend to support and build once per architecture.

### Windows: x86-64 executable and DLLs

Crystal's Windows support is still officially marked preview. The most straightforward build environment is the MSYS2 UCRT64 shell. Install Crystal, Shards, and SQLite there:

```sh
pacman -Sy --needed \
  mingw-w64-ucrt-x86_64-crystal \
  mingw-w64-ucrt-x86_64-shards \
  mingw-w64-ucrt-x86_64-sqlite3
```

From the repository in that same UCRT64 shell:

```sh
shards install --production
mkdir -p dist/windows
crystal build --release --no-debug -D standalone \
  src/micro_space_empire.cr \
  -o dist/windows/micro-space-empire.exe
```

Inspect the runtime dependencies with `ldd dist/windows/micro-space-empire.exe`. Copy every DLL reported from `/ucrt64/bin` into `dist/windows/` beside the executable; Windows system DLLs do not need to be copied. Distribute the entire `dist/windows/` directory, not the `.exe` alone. To launch it and open the browser from an MSYS2 shell:

```sh
MSE_OPEN_BROWSER=true ./dist/windows/micro-space-empire.exe
```

The official [Windows installation guide](https://crystal-lang.org/install/on_windows/) also describes the MSVC toolchain, but the MSYS2/MinGW route above makes the SQLite and runtime DLL dependencies easier to assemble. A browser-free Windows desktop shell would require a separate WebView2 launcher equivalent to the current macOS WebKit wrapper; that launcher is not yet included.

## Content and artwork

Rules and source PDFs remain in `Documents/` and `Images/`. Versioned card and technology data lives in `data/`. Each card has an independently replaceable `front.webp` and `back.webp` under `public/assets/cards/`; rerun `make assets` to regenerate them from the supplied PDFs.

The general game flow follows the supplied v.93 rules. Card-specific values use the original v.92 card sheet and the supplied five-card expansion. System graphics are credited in the original rules as NASA public-domain imagery; the player-mat graphics are credited there to Todd Sanders. The supplied documents and artwork retain their original rights and attribution.

## Expansion rulings

- Seven of nine near systems are selected; all three distant systems remain in play.
- Seven enabled events are selected for Year 1 and six are selected after reshuffling for Year 2.
- Meteor Storms suppress only the targeted system's production for two collection phases.
- Expansion events use the normal Home World protections and current Military cap.
