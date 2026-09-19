# A Bloody Simple Markdown Viewer
#
# The rendering engine is a plain SwiftPM package, so `swift build` and
# `swift test` work with no Xcode project involved. The app and its extensions
# need Xcode's build system, and that project is generated from project.yml by
# XcodeGen rather than committed, because a .pbxproj is unreadable in review.

APP        := Markdown
PROJECT    := BloodySimpleMarkdownViewer.xcodeproj
SCHEME     := Markdown
DERIVED    := build
DEBUG_APP  := $(DERIVED)/Build/Products/Debug/$(APP).app
RELEASE_APP:= $(DERIVED)/Build/Products/Release/$(APP).app
INSTALL_TO := /Applications/$(APP).app

.PHONY: all test build release install uninstall run clean project reregister help

help:
	@echo "make test        Run the engine's unit tests (no Xcode needed)"
	@echo "make build       Build the app (Debug)"
	@echo "make release     Build the app (Release, Developer ID signed)"
	@echo "make install     Build Release and install to /Applications"
	@echo "make run         Build and launch with the example document"
	@echo "make uninstall   Remove the installed app and deregister it"
	@echo "make clean       Remove build output and the generated project"

all: test build

test:
	swift test

project: $(PROJECT)

$(PROJECT): project.yml
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

# Launch Services caches bundles by path. A copy left in DerivedData or the
# Trash can keep answering for the .md type, so re-register explicitly.
reregister:
	@/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
		-f "$(INSTALL_TO)" 2>/dev/null || true

uninstall:
	@/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
		-u "$(INSTALL_TO)" 2>/dev/null || true
	@rm -rf "$(INSTALL_TO)"
	@echo "Removed $(INSTALL_TO)."

run: build
	open -a "$(PWD)/$(DEBUG_APP)" Examples/Showcase.md

clean:
	rm -rf $(DERIVED) .build $(PROJECT)
