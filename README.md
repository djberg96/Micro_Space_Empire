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

## Linux and Windows server executables

The native window under `src/macos/` is macOS-specific. The Crystal server itself is portable and already embeds the manifests, CSS, JavaScript, and card artwork. Linux and Windows builds therefore need only the resulting executable plus any native libraries described below. They run headlessly by default; set `MSE_OPEN_BROWSER=true` to open the game in the platform's default browser.

Build on the target operating system or in a matching CI/container runner. Crystal's [basic cross-compilation mode](https://crystal-lang.org/reference/latest/syntax_and_semantics/cross-compilation.html) emits an object file that must still be linked against the target system's libraries, so invoking it directly from macOS does not produce a finished Linux or Windows executable.

### Linux: portable static executable

Crystal recommends Alpine Linux and musl for fully static Linux binaries. With Docker installed, this builds an x86-64 executable that runs on both musl- and glibc-based distributions:

```sh
mkdir -p dist
docker run --rm --platform linux/amd64 \
  -v "$PWD:/workspace" -w /workspace \
  crystallang/crystal:1.21.0-alpine sh -lc '
    apk add --no-cache sqlite-static
    shards install --production
    crystal build --release --no-debug --static -D standalone \
      src/micro_space_empire.cr \
      -o dist/micro-space-empire-linux-x86_64
  '
```

Use `--platform linux/arm64` and change the output name for an ARM64 build. Confirm that the result is static with `file dist/micro-space-empire-linux-x86_64` or `ldd`; then run it with:

```sh
MSE_OPEN_BROWSER=true ./dist/micro-space-empire-linux-x86_64
```

See Crystal's [static-linking guide](https://crystal-lang.org/reference/latest/guides/static_linking.html) for the musl rationale and library lookup details.

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
