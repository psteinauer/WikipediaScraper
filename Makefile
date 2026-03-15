CLI_BINARY    = WikipediaScraper
APP_BINARY    = WikipediaScraperApp
APP_BUNDLE    = WikipediaScraper.app
IPAD_BINARY   = WikipediaScraperIPad
IPAD_SCHEME   = WikipediaScraperIPad
IPAD_PROJECT  = WikipediaScraperIPad.xcodeproj
INSTALL_PREFIX ?= /usr/local/bin

.PHONY: build release install app app-release ipad ipad-sim ipad-sim-reset icons clean xcode xcode-ipad test

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

## Build, install, and launch the iPadOS app in the iPad simulator (requires Xcode)
ipad-sim:
	@echo "→ Building $(IPAD_SCHEME) for iPad simulator…"
	xcrun xcodebuild \
	    -project "$(IPAD_PROJECT)" \
	    -scheme "$(IPAD_SCHEME)" \
	    -destination "platform=iOS Simulator,name=iPad Pro 13-inch (M5)" \
	    -configuration Debug \
	    build | xcpretty 2>/dev/null || \
	xcrun xcodebuild \
	    -project "$(IPAD_PROJECT)" \
	    -scheme "$(IPAD_SCHEME)" \
	    -destination "platform=iOS Simulator,name=iPad Pro 13-inch (M5)" \
	    -configuration Debug \
	    build
	@SIM_ID=$$(xcrun simctl list devices available | grep "iPad Pro 13-inch (M5)" | grep Booted | grep -Eo '[A-F0-9-]{36}' | head -1); \
	 APP=$$(find ~/Library/Developer/Xcode/DerivedData -path "*/Debug-iphonesimulator/$(IPAD_BINARY).app" -maxdepth 6 | head -1); \
	 if [ -n "$$SIM_ID" ] && [ -n "$$APP" ]; then \
	   echo "→ Installing on simulator $$SIM_ID…"; \
	   xcrun simctl install "$$SIM_ID" "$$APP"; \
	   echo "→ Launching…"; \
	   xcrun simctl launch "$$SIM_ID" com.psteinauer.WikipediaToGEDCOM.iPad; \
	 else \
	   echo "  (no booted iPad Pro 13-inch M5 found — boot a simulator and re-run, or use make xcode-ipad)"; \
	 fi

## Erase and reboot the iPad simulator (fixes stale-state crashes)
ipad-sim-reset:
	@SIM_ID=$$(xcrun simctl list devices available | grep "iPad Pro 13-inch (M5)" | grep -Eo '[A-F0-9-]{36}' | head -1); \
	 echo "→ Resetting simulator $$SIM_ID…"; \
	 xcrun simctl shutdown "$$SIM_ID" 2>/dev/null; sleep 2; \
	 xcrun simctl erase "$$SIM_ID"; \
	 xcrun simctl boot "$$SIM_ID"; \
	 echo "✓  Simulator reset. Run 'make ipad-sim' to reinstall."

## Build the iPadOS app in release (archive — no install)
ipad:
	@echo "→ Building $(IPAD_SCHEME) release for iOS…"
	xcrun xcodebuild \
	    -project "$(IPAD_PROJECT)" \
	    -scheme "$(IPAD_SCHEME)" \
	    -destination "generic/platform=iOS" \
	    -configuration Release \
	    build

## Regenerate all app icons (macOS + iPadOS) from make_icon.swift
icons:
	swift make_icon.swift

## Open the SPM package in Xcode (macOS targets)
xcode:
	xed .

## Open the iPad Xcode project in Xcode
xcode-ipad:
	open "$(IPAD_PROJECT)"

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
