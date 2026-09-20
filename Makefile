# A Bloody Simple Markdown Viewer
#
# The rendering engine is a plain SwiftPM package, so `swift build` and
# `swift test` work with no Xcode project involved. The app and its extensions
# need Xcode's build system, and that project is generated from project.yml by
# XcodeGen rather than committed, because a .pbxproj is unreadable in review.

APP        := Markdown
# Left empty on purpose: install-cli picks the first writable directory.
CLI_PREFIX ?=
PROJECT    := BloodySimpleMarkdownViewer.xcodeproj
SCHEME     := Markdown
DERIVED    := build
DEBUG_APP  := $(DERIVED)/Build/Products/Debug/$(APP).app
RELEASE_APP:= $(DERIVED)/Build/Products/Release/$(APP).app
INSTALL_TO := /Applications/$(APP).app

.PHONY: all test build release install uninstall run clean project reregister icon cli install-cli uninstall-cli help

help:
	@echo "make test        Run the engine's unit tests (no Xcode needed)"
	@echo "make build       Build the app (Debug)"
	@echo "make release     Build the app (Release, Developer ID signed)"
	@echo "make install     Build Release and install to /Applications"
	@echo "make run         Build and launch with the example document"
	@echo "make uninstall   Remove the installed app and deregister it"
	@echo "make cli         Build the mdv command line tool"
	@echo "make install-cli Install the mdv tool (override with CLI_PREFIX=...)"
	@echo "make icon        Rebuild the app icon from Design/icon-source.png"
	@echo "make clean       Remove build output and the generated project"

all: test build

test:
	swift test

project: $(PROJECT)

# Directories are listed as well as files: adding or deleting a source changes
# the containing directory's timestamp, and without that a new file builds fine
# for whoever wrote it and is missing for everybody else.
SOURCES := $(shell find App QuickLookExtension Sources -name '*.swift' -o -type d)

$(PROJECT): project.yml $(SOURCES)
	@command -v xcodegen >/dev/null || { echo "XcodeGen is required: brew install xcodegen"; exit 1; }
	xcodegen generate

build: project
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug \
		-derivedDataPath $(DERIVED) build | grep -E "error:|warning:|BUILD" || true

release: project
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release \
		-derivedDataPath $(DERIVED) build | grep -E "error:|BUILD" || true

install: release
	@rm -rf "$(INSTALL_TO)"
	@cp -R "$(RELEASE_APP)" "$(INSTALL_TO)"
	@$(MAKE) reregister
	@echo "Installed to $(INSTALL_TO)."
	@echo "Open a .md file, then use Markdown > Make Default Markdown App."
	@echo "Press space on a .md file in Finder for the rendered preview."

# Launch Services caches bundles by path. A copy left in DerivedData or the
# Trash can keep answering for the .md type, so re-register explicitly.
reregister:
	@/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
		-f "$(INSTALL_TO)" 2>/dev/null || true
	@# PlugInKit caches the extension by path too, so point it at the installed
	@# copy and enable it; a build-folder copy would otherwise keep answering.
	@pluginkit -r "$(PWD)/$(RELEASE_APP)/Contents/PlugIns/MarkdownQuickLook.appex" 2>/dev/null || true
	@pluginkit -a "$(INSTALL_TO)/Contents/PlugIns/MarkdownQuickLook.appex" 2>/dev/null || true
	@pluginkit -e use -i ch.sala.BloodySimpleMarkdownViewer.QuickLook 2>/dev/null || true

# The icon is committed, so a plain build needs no extra tools. Regenerate it
# after changing the artwork; zopflipng is optional and only shrinks the result.
icon: Design/icon-source.png Tools/makeicon.swift
	@rm -rf $(DERIVED)/Markdown.iconset
	@mkdir -p $(DERIVED)
	@xcrun swiftc -sdk $$(xcrun --show-sdk-path --sdk macosx) \
		-o $(DERIVED)/makeicon Tools/makeicon.swift
	@$(DERIVED)/makeicon Design/icon-source.png $(DERIVED)/Markdown.iconset
	@command -v zopflipng >/dev/null && \
		for f in $(DERIVED)/Markdown.iconset/*.png; do \
			zopflipng -y --lossy_transparent "$$f" "$$f.out" >/dev/null 2>&1 && mv "$$f.out" "$$f"; \
		done || echo "zopflipng not installed; icons are uncompressed"
	@iconutil -c icns $(DERIVED)/Markdown.iconset -o App/Resources/Markdown.icns
	@echo "Wrote App/Resources/Markdown.icns"

# The command line is a plain SwiftPM executable, so it builds without Xcode.
cli:
	swift build -c release --product mdv
	@echo "Built .build/release/mdv"

# /usr/local/bin needs root on a stock machine, and Homebrew's own bin does
# not. Preferring whichever is writable means the common case takes no sudo,
# and the uncommon case says what to do rather than failing on a temp file.
install-cli: cli
	@PREFIX="$(CLI_PREFIX)"; \
	if [ -z "$$PREFIX" ]; then \
		for candidate in /opt/homebrew/bin /usr/local/bin "$$HOME/.local/bin"; do \
			if [ -w "$$candidate" ]; then PREFIX="$$candidate"; break; fi; \
		done; \
	fi; \
	PREFIX="$${PREFIX:-/usr/local/bin}"; \
	if [ ! -d "$$PREFIX" ] && ! mkdir -p "$$PREFIX" 2>/dev/null; then \
		echo "Cannot create $$PREFIX. Try: sudo make install-cli CLI_PREFIX=$$PREFIX"; exit 1; \
	fi; \
	if [ ! -w "$$PREFIX" ]; then \
		echo "$$PREFIX is not writable. Try:"; \
		echo "  sudo make install-cli CLI_PREFIX=$$PREFIX"; \
		echo "or pick somewhere on your PATH that is, for example:"; \
		echo "  make install-cli CLI_PREFIX=\$$HOME/.local/bin"; exit 1; \
	fi; \
	install -m 0755 .build/release/mdv "$$PREFIX/mdv"; \
	echo "Installed $$PREFIX/mdv"

uninstall-cli:
	@rm -f "$(CLI_PREFIX)/mdv"
	@echo "Removed $(CLI_PREFIX)/mdv"

uninstall:
	@/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
		-u "$(INSTALL_TO)" 2>/dev/null || true
	@rm -rf "$(INSTALL_TO)"
	@echo "Removed $(INSTALL_TO)."

run: build
	open -a "$(PWD)/$(DEBUG_APP)" Examples/Showcase.md

clean:
	rm -rf $(DERIVED) .build $(PROJECT)
