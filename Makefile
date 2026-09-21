.PHONY: setup assets dev test build standalone clean

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

standalone:
	sh scripts/build_standalone.sh

clean:
	rm -f bin/micro_space_empire dist/micro-space-empire-server
	rm -rf "dist/Micro Space Empire.app"
