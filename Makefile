BINARY = WikipediaScraper
INSTALL_PREFIX ?= /usr/local/bin

.PHONY: build release install clean xcode test

## Build debug binary
build:
	swift build

## Build optimized release binary
release:
	swift build -c release

## Install release binary to $(INSTALL_PREFIX)
install: release
	install -d "$(INSTALL_PREFIX)"
	install -m 755 .build/release/$(BINARY) "$(INSTALL_PREFIX)/$(BINARY)"
	@echo "Installed to $(INSTALL_PREFIX)/$(BINARY)"

## Open the package in Xcode
xcode:
	xed .

## Remove build artifacts
clean:
	swift package clean

## Quick smoke-test (requires network)
test:
	@echo "Testing George Washington..."
	.build/debug/$(BINARY) --verbose \
	    "https://en.wikipedia.org/wiki/George_Washington" \
	    --output /tmp/washington_test.ged
	@echo "Output: /tmp/washington_test.ged"
	@wc -l /tmp/washington_test.ged
