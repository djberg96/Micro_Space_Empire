.PHONY: setup assets dev test build standalone standalone-linux electron-server electron electron-package clean

setup:
	shards install

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

standalone-linux:
	sh scripts/build_standalone_linux.sh

electron-server:
	sh scripts/build_electron_server.sh

electron: electron-server
	cd electron && npm start

electron-package: electron-server
	cd electron && npm run package

clean:
	rm -f bin/micro_space_empire dist/micro-space-empire-server dist/micro-space-empire-fedora-* dist/micro-space-empire-server-fedora-*
	rm -f dist/micro-space-empire-electron-server
	rm -rf "dist/Micro Space Empire.app" dist/electron dist/micro-space-empire-electron-libs
