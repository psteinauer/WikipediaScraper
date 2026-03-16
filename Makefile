# ─────────────────────────────────────────────────────────────────────────────
# WikipediaScraper — Makefile
#
# GUI targets (macOS app, iPadOS app) go through WikipediaScraper.xcworkspace
# so that Share Extensions are correctly built and embedded alongside the apps.
# The CLI tool can be built with Swift Package Manager alone.
#
# Output for Xcode builds lands in $(BUILD_DIR) (./build by default) so it
# stays out of DerivedData and in a predictable location.
# ─────────────────────────────────────────────────────────────────────────────

WORKSPACE        = WikipediaScraper.xcworkspace
MAC_SCHEME       = Wikipedia to GEDCOM (macOS)
IPAD_SCHEME      = Wikipedia to GEDCOM (iPadOS)
CLI_SCHEME       = WikipediaScraper CLI
BUILD_ALL_SCHEME = Build All

CLI_BINARY       = WikipediaScraper
IPAD_BUNDLE_ID   = com.psteinauer.WikipediaToGEDCOM.iPad
IPAD_SIM_NAME   ?= iPad Pro 13-inch (M5)
INSTALL_PREFIX  ?= /usr/local/bin

BUILD_DIR        = ./build

.PHONY: all build release install app app-release ipad ipad-sim ipad-sim-reset \
        icons clean xcode test

# ── All targets ───────────────────────────────────────────────────────────────

## Build every target (macOS app + extensions + CLI + iPadOS app) — Debug
all:
	xcrun xcodebuild \
	    -workspace "$(WORKSPACE)" \
	    -scheme "$(BUILD_ALL_SCHEME)" \
	    -configuration Debug \
	    -derivedDataPath "$(BUILD_DIR)" \
	    build

# ── CLI ───────────────────────────────────────────────────────────────────────

## Build CLI debug binary via SPM  →  .build/debug/WikipediaScraper
build:
	swift build --product $(CLI_BINARY)

## Build CLI optimised release binary via SPM  →  .build/release/WikipediaScraper
release:
	swift build -c release --product $(CLI_BINARY)

## Build CLI release binary and install to $(INSTALL_PREFIX)
install: release
	install -d "$(INSTALL_PREFIX)"
	install -m 755 .build/release/$(CLI_BINARY) "$(INSTALL_PREFIX)/$(CLI_BINARY)"
	@echo "Installed to $(INSTALL_PREFIX)/$(CLI_BINARY)"

# ── macOS app ─────────────────────────────────────────────────────────────────

## Build macOS app + Share Extension (Debug) via Xcode
##   Output: $(BUILD_DIR)/Build/Products/Debug/WikipediaScraperApp.app
app:
	@echo "→ Building '$(MAC_SCHEME)' (Debug)…"
	xcrun xcodebuild \
	    -workspace "$(WORKSPACE)" \
	    -scheme "$(MAC_SCHEME)" \
	    -configuration Debug \
	    -derivedDataPath "$(BUILD_DIR)" \
	    build 2>&1 | xcpretty 2>/dev/null || \
	xcrun xcodebuild \
	    -workspace "$(WORKSPACE)" \
	    -scheme "$(MAC_SCHEME)" \
	    -configuration Debug \
	    -derivedDataPath "$(BUILD_DIR)" \
	    build
	@echo ""
	@echo "✓  $(BUILD_DIR)/Build/Products/Debug/WikipediaScraperApp.app"
	@echo "   To launch: open '$(BUILD_DIR)/Build/Products/Debug/WikipediaScraperApp.app'"

## Build macOS app + Share Extension (Release) via Xcode
##   Output: $(BUILD_DIR)/Build/Products/Release/WikipediaScraperApp.app
app-release:
	@echo "→ Building '$(MAC_SCHEME)' (Release)…"
	xcrun xcodebuild \
	    -workspace "$(WORKSPACE)" \
	    -scheme "$(MAC_SCHEME)" \
	    -configuration Release \
	    -derivedDataPath "$(BUILD_DIR)" \
	    build 2>&1 | xcpretty 2>/dev/null || \
	xcrun xcodebuild \
	    -workspace "$(WORKSPACE)" \
	    -scheme "$(MAC_SCHEME)" \
	    -configuration Release \
	    -derivedDataPath "$(BUILD_DIR)" \
	    build
	@echo ""
	@echo "✓  $(BUILD_DIR)/Build/Products/Release/WikipediaScraperApp.app"
	@echo "   To install: cp -r '$(BUILD_DIR)/Build/Products/Release/WikipediaScraperApp.app' /Applications/"

# ── iPadOS app ────────────────────────────────────────────────────────────────

## Build iPadOS app + Share Extension for a connected device (Release)
ipad:
	@echo "→ Building '$(IPAD_SCHEME)' for device (Release)…"
	xcrun xcodebuild \
	    -workspace "$(WORKSPACE)" \
	    -scheme "$(IPAD_SCHEME)" \
	    -destination "generic/platform=iOS" \
	    -configuration Release \
	    build

## Build iPadOS app + Share Extension for the simulator (Debug), then install and launch
##   Set IPAD_SIM_NAME=<name> to target a different simulator device
ipad-sim:
	@echo "→ Building '$(IPAD_SCHEME)' for simulator '$(IPAD_SIM_NAME)'…"
	xcrun xcodebuild \
	    -workspace "$(WORKSPACE)" \
	    -scheme "$(IPAD_SCHEME)" \
	    -destination "platform=iOS Simulator,name=$(IPAD_SIM_NAME)" \
	    -configuration Debug \
	    -derivedDataPath "$(BUILD_DIR)" \
	    build 2>&1 | xcpretty 2>/dev/null || \
	xcrun xcodebuild \
	    -workspace "$(WORKSPACE)" \
	    -scheme "$(IPAD_SCHEME)" \
	    -destination "platform=iOS Simulator,name=$(IPAD_SIM_NAME)" \
	    -configuration Debug \
	    -derivedDataPath "$(BUILD_DIR)" \
	    build
	@SIM_ID=$$(xcrun simctl list devices available | grep "$(IPAD_SIM_NAME)" | grep Booted | grep -Eo '[A-F0-9-]{36}' | head -1); \
	 APP=$$(find "$(BUILD_DIR)/Build/Products" -name "WikipediaScraperIPad.app" -maxdepth 4 | head -1); \
	 if [ -n "$$SIM_ID" ] && [ -n "$$APP" ]; then \
	   echo "→ Installing on simulator $$SIM_ID…"; \
	   xcrun simctl install "$$SIM_ID" "$$APP"; \
	   echo "→ Launching…"; \
	   xcrun simctl launch "$$SIM_ID" "$(IPAD_BUNDLE_ID)"; \
	 else \
	   echo "  (no booted '$(IPAD_SIM_NAME)' simulator — boot one first, or use: make xcode)"; \
	 fi

## Erase and reboot the iPad simulator (fixes stale-state crashes)
ipad-sim-reset:
	@SIM_ID=$$(xcrun simctl list devices available | grep "$(IPAD_SIM_NAME)" | grep -Eo '[A-F0-9-]{36}' | head -1); \
	 echo "→ Resetting simulator $$SIM_ID…"; \
	 xcrun simctl shutdown "$$SIM_ID" 2>/dev/null; sleep 2; \
	 xcrun simctl erase "$$SIM_ID"; \
	 xcrun simctl boot "$$SIM_ID"; \
	 echo "✓  Simulator reset. Run 'make ipad-sim' to reinstall."

# ── Utilities ─────────────────────────────────────────────────────────────────

## Regenerate all app icon PNGs (macOS + iPadOS) from make_icon.swift
icons:
	swift make_icon.swift

## Open WikipediaScraper.xcworkspace in Xcode
xcode:
	open "$(WORKSPACE)"

## Remove local build artefacts (does not touch Xcode DerivedData)
clean:
	swift package clean
	rm -rf "$(BUILD_DIR)"

## Smoke-test the CLI against the George Washington Wikipedia article (requires network)
test:
	@echo "→ Testing CLI: George Washington…"
	swift build --product $(CLI_BINARY)
	.build/debug/$(CLI_BINARY) --verbose \
	    "https://en.wikipedia.org/wiki/George_Washington" \
	    --output /tmp/washington_test.ged
	@echo ""
	@echo "Output: /tmp/washington_test.ged"
	@wc -l /tmp/washington_test.ged
