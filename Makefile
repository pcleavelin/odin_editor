all: editor

editor: src/**/*.odin plugins
	mkdir -p bin
	odin build src/ -out:bin/editor

plugins: emu
	mkdir -p bin
	cd plugins && $(MAKE)
	cp plugins/bin/*.elf bin/

emu:
	mkdir -p bin
	cd third_party/riscv-emu && $(MAKE)
	cp third_party/riscv-emu/bin/stdlib.elf bin/stdlib.elf

grep:
	cargo fmt --manifest-path "src/pkg/grep_lib/Cargo.toml"
	cargo build --manifest-path "src/pkg/grep_lib/Cargo.toml"

test: src/**/*.odin
	odin test src/tests/ -all-packages -debug -out:bin/test_runner

TS_DIR := third_party/tree-sitter/lib
TS_SRC := $(wildcard $(TS_DIR)/src/*.c)
TS_OBJ := $(TS_SRC:.c=.o)

TS_ARFLAGS := rcs
CFLAGS ?= -O3 -Wall -Wextra -Wshadow -Wpedantic -Werror=incompatible-pointer-types
override CFLAGS += -std=c11 -fPIC -fvisibility=hidden
override CFLAGS += -D_POSIX_C_SOURCE=200112L -D_DEFAULT_SOURCE
override CFLAGS += -I$(TS_DIR)/src -I$(TS_DIR)/src/wasm -I$(TS_DIR)/include
override CFLAGS += -o bin/

libtree-sitter.a: $(TS_OBJ)
	$(AR) $(TS_ARFLAGS) $@ $^
