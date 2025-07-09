export RUSTFLAGS=-C target-feature=-avx2

all: editor

editor: grep src/**/*.odin
	mkdir -p bin
	odin build src/ -out:bin/editor -debug

grep:
	cargo build --manifest-path "src/pkg/grep_lib/Cargo.toml"
