all: editor

editor: src/*.odin rg odin_highlighter
	odin build src/ -out:bin/editor -lld

odin_highlighter:
	odin build plugins/highlighter/src/ -build-mode:dll -no-entry-point -out:bin/highlighter

rg:
	cargo b --manifest-path=lib-rg/Cargo.toml
