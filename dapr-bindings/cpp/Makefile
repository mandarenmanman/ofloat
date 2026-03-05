WASI_SDK ?= /opt/wasi-sdk
CXX = $(WASI_SDK)/bin/clang++
SYSROOT = $(WASI_SDK)/share/wasi-sysroot
CXXFLAGS = --sysroot=$(SYSROOT) -std=c++17 -O2

TARGET = build/bindings.wasm

.PHONY: all clean

all: $(TARGET)

$(TARGET): main.cpp
	@mkdir -p build
	$(CXX) $(CXXFLAGS) -o $@ $<

clean:
	rm -rf build
