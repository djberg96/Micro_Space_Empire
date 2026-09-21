#!/bin/sh
set -eu

project_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
task_work=$(mktemp -d "${TMPDIR:-/tmp}/mse-card-assets.XXXXXX")
trap 'rm -rf "$task_work"' EXIT INT TERM

for command in pdftoppm magick; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "$command is required to regenerate the card assets." >&2
    exit 1
  fi
done

pdftoppm -png -r 300 "$project_root/Images/MSE_decks_v92.pdf" "$task_work/base"
pdftoppm -png -r 300 "$project_root/Images/MSE-5-new-cards.pdf" "$task_work/expansion"
pdftoppm -png -r 300 -singlefile "$project_root/Images/Back_page_1.pdf" "$task_work/system-back"
pdftoppm -png -r 300 -singlefile "$project_root/Images/Back_page_2.pdf" "$task_work/event-back"

crop_card() {
  source_file=$1
  geometry=$2
  kind=$3
  card_id=$4
  destination="$project_root/public/assets/cards/$kind/$card_id"
  mkdir -p "$destination"
  magick "$source_file" -crop "$geometry" +repage -resize '600x840!' -quality 88 "$destination/front.webp"
}

# The original v92 base deck: nine system fronts on page 1, two on page 2,
# and eight event fronts on page 3.
crop_card "$task_work/base-1.png" '750x1048+58+92' systems home-world
crop_card "$task_work/base-1.png" '750x1048+864+92' systems wolf-359
crop_card "$task_work/base-1.png" '750x1048+1668+92' systems proxima
crop_card "$task_work/base-1.png" '750x1048+58+1234' systems epsilon-eridani
crop_card "$task_work/base-1.png" '750x1048+864+1234' systems cygnus
crop_card "$task_work/base-1.png" '750x1048+1668+1234' systems tau-ceti
crop_card "$task_work/base-1.png" '750x1048+58+2372' systems procyon
crop_card "$task_work/base-1.png" '750x1048+864+2372' systems canopus
crop_card "$task_work/base-1.png" '750x1048+1668+2372' systems polaris
crop_card "$task_work/base-2.png" '750x1048+58+92' systems galaxys-edge
crop_card "$task_work/base-2.png" '750x1048+864+92' systems sirius

crop_card "$task_work/base-3.png" '750x1048+58+92' events asteroid
crop_card "$task_work/base-3.png" '750x1048+864+92' events strike
crop_card "$task_work/base-3.png" '750x1048+1668+92' events derelict-ship
crop_card "$task_work/base-3.png" '750x1048+58+1234' events revolt-major
crop_card "$task_work/base-3.png" '750x1048+864+1234' events small-invasion
crop_card "$task_work/base-3.png" '750x1048+1668+1234' events peace-and-quiet
crop_card "$task_work/base-3.png" '750x1048+58+2372' events large-invasion
crop_card "$task_work/base-3.png" '750x1048+864+2372' events revolt-minor

# The five-card optional expansion uses a different sheet arrangement.
crop_card "$task_work/expansion-1.png" '730x1014+504+552' systems aquila
crop_card "$task_work/expansion-1.png" '730x1014+1336+552' systems queloz
crop_card "$task_work/expansion-1.png" '732x1016+120+1710' events meteor-storms
crop_card "$task_work/expansion-1.png" '732x1016+896+1710' events pandemic
crop_card "$task_work/expansion-1.png" '732x1016+1662+1710' events alien-mission

magick "$task_work/system-back.png" -crop '774x1080+45+81' +repage -resize '600x840!' -quality 88 "$task_work/system-back.webp"
magick "$task_work/event-back.png" -crop '774x1080+45+81' +repage -resize '600x840!' -quality 88 "$task_work/event-back.webp"

for card_dir in "$project_root"/public/assets/cards/systems/*; do
  cp "$task_work/system-back.webp" "$card_dir/back.webp"
done
for card_dir in "$project_root"/public/assets/cards/events/*; do
  cp "$task_work/event-back.webp" "$card_dir/back.webp"
done

echo "Extracted 13 systems and 11 events into public/assets/cards."
