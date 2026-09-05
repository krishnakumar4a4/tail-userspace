.PHONY: all build release app clean test

all: build

build:
	swift build

release:
	swift build -c release

app: release
	@echo "Bundling TailUserspace.app..."
	@mkdir -p TailUserspace.app/Contents/MacOS
	@mkdir -p TailUserspace.app/Contents/Resources
	@cp .build/release/TailUserspaceApp TailUserspace.app/Contents/MacOS/
	@cp packaging/Info.plist TailUserspace.app/Contents/
	@echo "✓ TailUserspace.app successfully packaged."

clean:
	swift package clean
	rm -rf .build TailUserspace.app

test:
	swift run TailUserspaceTests
