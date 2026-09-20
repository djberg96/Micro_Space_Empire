.PHONY: setup assets dev test build clean

setup:
	shards install
	sh scripts/extract_card_assets.sh

assets:
	sh scripts/extract_card_assets.sh

dev:
	crystal run src/micro_space_empire.cr

test:
	crystal spec

build:
	mkdir -p bin
	crystal build --release src/micro_space_empire.cr -o bin/micro_space_empire

clean:
	rm -f bin/micro_space_empire
