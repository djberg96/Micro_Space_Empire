# Micro Space Empire

A local, solitaire web adaptation of Robert Bartelli's **Micro Space Empire v.93**, built with Crystal, Kemal, and SQLite.

## Run it

Requirements: Crystal 1.21+, SQLite 3, Poppler, and ImageMagick (the latter two are only needed to regenerate card assets).

```sh
make setup
make test
make dev
```

Open <http://127.0.0.1:3000>. Saves are written to `var/micro_space_empire.db` and every completed action is autosaved. Set `MSE_DATABASE_PATH`, `MSE_HOST`, or `MSE_PORT` to override the local defaults.

For an optimized binary:

```sh
make build
./bin/micro_space_empire
```

## Content and artwork

Rules and source PDFs remain in `Documents/` and `Images/`. Versioned card and technology data lives in `data/`. Each card has an independently replaceable `front.webp` and `back.webp` under `public/assets/cards/`; rerun `make assets` to regenerate them from the supplied PDFs.

The general game flow follows the supplied v.93 rules. Card-specific values use the original v.92 card sheet and the supplied five-card expansion. System graphics are credited in the original rules as NASA public-domain imagery; the player-mat graphics are credited there to Todd Sanders. The supplied documents and artwork retain their original rights and attribution.

## Expansion rulings

- Seven of nine near systems are selected; all three distant systems remain in play.
- Seven enabled events are selected for Year 1 and six are selected after reshuffling for Year 2.
- Meteor Storms suppress only the targeted system's production for two collection phases.
- Expansion events use the normal Home World protections and current Military cap.
