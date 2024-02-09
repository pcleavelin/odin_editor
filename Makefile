all: editor

editor: src/*.odin grep odin_highlighter
	odin build src/ -out:bin/editor -lld

odin_highlighter:
	odin build plugins/highlighter/src/ -build-mode:dll -no-entry-point -out:bin/highlighter

grep:
	nightly-cargo b --manifest-path=plugins/grep/Cargo.toml
	cp plugins/grep/target/debug/libgrep_plugin.dylib bin/
