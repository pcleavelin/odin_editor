all: editor

editor: src/*.odin grep odin_highlighter buffer_search
	odin build src/ -out:bin/editor -lld

buffer_search:
	odin build plugins/buffer_search/ -build-mode:dll -no-entry-point -out:bin/buffer_search
odin_highlighter:
	odin build plugins/highlighter/src/ -build-mode:dll -no-entry-point -out:bin/highlighter

grep:
	cargo b --manifest-path=plugins/grep/Cargo.toml
	cp plugins/grep/target/debug/libgrep_plugin.dylib bin/
