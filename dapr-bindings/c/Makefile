WASI_SDK ?= /opt/wasi-sdk
CC = $(WASI_SDK)/bin/clang
SYSROOT = $(WASI_SDK)/share/wasi-sysroot
CFLAGS = --sysroot=$(SYSROOT) -O2

TARGET = build/bindings.wasm

.PHONY: all clean

all: $(TARGET)

$(TARGET): main.c
	@mkdir -p build
	$(CC) $(CFLAGS) -o $@ $<

clean:
	rm -rf build
