APP := photos-vim-keys.app
BIN := $(APP)/Contents/MacOS/photos-vim-keys
SRC := main.swift MenuBar.swift
# Sign with the first real code-signing identity in the keychain, if any. An
# ad-hoc signature ("-") changes on every build, so macOS forgets the app's
# Accessibility permission each time; a real identity keeps it across builds.
SIGN_ID ?= $(or $(shell security find-identity -p codesigning -v | awk -F'"' 'NR==1 {print $$2}'),-)

.PHONY: build run clean

# SIGN_ID is "-" when no certificate was found above: "-" is codesign's name
# for an ad-hoc signature, which needs no certificate.
build: $(BIN)
	@if [ "$(SIGN_ID)" = "-" ]; then \
	  echo "warning: no code-signing certificate found; signing ad-hoc." >&2; \
	  echo "  macOS will forget photos-vim-keys' Accessibility permission on every rebuild." >&2; \
	  echo "  To avoid that, sign into Xcode (Settings > Accounts) with any Apple ID (free)" >&2; \
	  echo "  and create an Apple Development certificate (Manage Certificates > +)." >&2; \
	  echo "  This build detects that certificate automatically and uses it for signing." >&2; \
	fi
	codesign --sign "$(SIGN_ID)" --force $(APP)

$(BIN): $(SRC) Info.plist
	mkdir -p $(APP)/Contents/MacOS
	cp Info.plist $(APP)/Contents/
	swiftc -O $(SRC) -o $(BIN) -framework Cocoa -framework Carbon

run: build
	$(BIN)

clean:
	rm -rf $(APP)
