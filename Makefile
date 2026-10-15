APP := photos-vim-keys.app
BIN := $(APP)/Contents/MacOS/photos-vim-keys
SRC := main.swift MenuBar.swift

.PHONY: build run clean

build: $(BIN)
	codesign --sign - --force $(APP)

$(BIN): $(SRC) Info.plist
	mkdir -p $(APP)/Contents/MacOS
	cp Info.plist $(APP)/Contents/
	swiftc -O $(SRC) -o $(BIN) -framework Cocoa -framework Carbon

run: build
	$(BIN)

clean:
	rm -rf $(APP)
