export RUSTFLAGS=-C target-feature=-avx2

all: bin/libtree-sitter.a editor

editor: grep src/**/*.odin
	mkdir -p bin
	odin build src/ -out:bin/editor -debug

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

bin/libtree-sitter.a: $(TS_OBJ)
	$(AR) $(TS_ARFLAGS) $@ $^ --output bin/
