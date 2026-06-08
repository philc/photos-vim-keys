BIN := photosvim
SRC := photosvim.swift

.PHONY: build run clean

build: $(BIN)

$(BIN): $(SRC)
	swiftc -O $(SRC) -o $(BIN) -framework Cocoa -framework Carbon

run: build
	./$(BIN)

clean:
	rm -f $(BIN)
