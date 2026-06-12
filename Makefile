.PHONY: all build debug release test test-all package clean run help

all: build

help:
	@echo "GoldBar Makefile"
	@echo ""
	@echo "  make build      — debug build"
	@echo "  make release    — release build"
	@echo "  make run        — build + launch"
	@echo "  make test       — unit tests"
	@echo "  make test-all   — unit + integration tests"
	@echo "  make package    — release build + DMG"
	@echo "  make clean      — remove build artifacts"

build:
	./build.sh

release:
	./build.sh release

run:
	./build.sh run

test:
	./test.sh

test-all:
	./test.sh --all

package:
	./package.sh

clean:
	rm -rf build/*.app build/*.dmg build/dist
