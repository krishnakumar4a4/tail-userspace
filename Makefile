.PHONY: all build release app clean test dist

all: build

build:
	swift build

release:
	swift build -c release

app: release
	@echo "Bundling TailUserspace.app..."
	@rm -rf TailUserspace.app
	@mkdir -p TailUserspace.app/Contents/MacOS
	@mkdir -p TailUserspace.app/Contents/Resources
	@cp .build/release/TailUserspaceApp TailUserspace.app/Contents/MacOS/
	@cp packaging/Info.plist TailUserspace.app/Contents/
	@echo "Ad-hoc signing TailUserspace.app..."
	@codesign --force --deep --sign - TailUserspace.app
	@codesign --verify --deep --strict TailUserspace.app
	@echo "✓ TailUserspace.app successfully packaged and verified."

dist: app
	@echo "Creating distribution archive..."
	@ditto -c -k --sequesterRsrc --keepParent TailUserspace.app TailUserspace-macOS.zip
	@cp .build/release/tail-userspace ./tail-userspace-cli
	@echo "✓ Distribution zip created: TailUserspace-macOS.zip"

clean:
	swift package clean
	rm -rf .build TailUserspace.app TailUserspace-macOS.zip tail-userspace-cli

test:
	swift run TailUserspaceTests
