
SRCS = src/*.py

BIN = build/shared_vim_server

.PHONY: build

build: $(BIN)

$(BIN): $(SRCS) setup.py
	python3 setup.py build

