.PHONY: build app dmg validate run install uninstall check-permissions print-config clean

build:
	swift build -c release

app:
	./scripts/build-app.sh

run:
	swift run bitpaste

dmg:
	./scripts/package-dmg.sh

validate:
	./scripts/validate.sh

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
