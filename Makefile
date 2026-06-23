.PHONY: build run install uninstall check-permissions print-config clean

build:
	swift build -c release

run:
	swift run bitpaste

install:
	./scripts/install.sh

uninstall:
	./scripts/uninstall.sh

check-permissions:
	swift run bitpaste --check-permissions

print-config:
	swift run bitpaste --print-config

clean:
	swift package clean
