CLI_BINARY    = WikipediaScraper
APP_BINARY    = WikipediaScraperApp
APP_BUNDLE    = WikipediaScraper.app
IPAD_BINARY   = WikipediaScraperIPad
IPAD_SCHEME   = WikipediaScraperIPad
INSTALL_PREFIX ?= /usr/local/bin

.PHONY: build release install app app-release ipad ipad-sim icons clean xcode test

## Build debug binaries
build:
	swift build

## Build optimised release binaries
release:
	swift build -c release

## Install CLI release binary to $(INSTALL_PREFIX)
install: release
	install -d "$(INSTALL_PREFIX)"
	install -m 755 .build/release/$(CLI_BINARY) "$(INSTALL_PREFIX)/$(CLI_BINARY)"
	@echo "Installed to $(INSTALL_PREFIX)/$(CLI_BINARY)"

## Build a double-clickable macOS .app bundle (release)
app: app-release
	@echo "→ Packaging $(APP_BUNDLE)…"
	@rm -rf "$(APP_BUNDLE)"
	@mkdir -p "$(APP_BUNDLE)/Contents/MacOS"
	@mkdir -p "$(APP_BUNDLE)/Contents/Resources"
	# Binary
	@cp .build/release/$(APP_BINARY) "$(APP_BUNDLE)/Contents/MacOS/$(APP_BINARY)"
	# Bundle metadata
	@cp Sources/WikipediaScraperApp/Info.plist "$(APP_BUNDLE)/Contents/"
	# Compile asset catalogue (app icon) – silently skip if actool is unavailable
	@xcrun actool Sources/WikipediaScraperApp/Assets.xcassets \
	    --compile "$(APP_BUNDLE)/Contents/Resources" \
	    --platform macosx \
	    --minimum-deployment-target 13.0 \
	    --output-format human-readable-text \
	    --app-icon AppIcon \
	    --output-partial-info-plist /tmp/WikipediaToGEDCOM-partial.plist \
	    2>/dev/null || true
	# Ad-hoc code signature so Gatekeeper lets it open
	@codesign --sign - --force --deep "$(APP_BUNDLE)" 2>/dev/null && \
	    echo "✓ Ad-hoc signed" || echo "  (codesign unavailable – unsigned bundle)"
	@echo ""
	@echo "✓  Built $(APP_BUNDLE)"
	@echo "   To launch:  open $(APP_BUNDLE)"
	@echo "   To install: cp -r $(APP_BUNDLE) /Applications/"

app-release:
	swift build -c release --product $(APP_BINARY)

## Build and run the iPadOS app in the iPad simulator (requires Xcode)
ipad-sim:
	@echo "→ Building $(IPAD_SCHEME) for iPad simulator…"
	xcrun xcodebuild \
	    -scheme "$(IPAD_SCHEME)" \
	    -destination "platform=iOS Simulator,name=iPad Pro 13-inch (M4)" \
	    -configuration Debug \
	    build | xcpretty 2>/dev/null || \
	xcrun xcodebuild \
	    -scheme "$(IPAD_SCHEME)" \
	    -destination "platform=iOS Simulator,name=iPad Pro 13-inch (M4)" \
	    -configuration Debug \
	    build

## Build the iPadOS app in release (archive — no install)
ipad:
	@echo "→ Building $(IPAD_SCHEME) release for iOS…"
	xcrun xcodebuild \
	    -scheme "$(IPAD_SCHEME)" \
	    -destination "generic/platform=iOS" \
	    -configuration Release \
	    build

## Regenerate all app icons (macOS + iPadOS) from make_icon.swift
icons:
	swift make_icon.swift

## Open the package in Xcode
xcode:
	xed .

## Remove build artefacts and any built .app
clean:
	swift package clean
	rm -rf "$(APP_BUNDLE)"

## Quick smoke-test (requires network)
test:
	@echo "Testing George Washington…"
	.build/debug/$(CLI_BINARY) --verbose \
	    "https://en.wikipedia.org/wiki/George_Washington" \
	    --output /tmp/washington_test.ged
	@echo "Output: /tmp/washington_test.ged"
	@wc -l /tmp/washington_test.ged
