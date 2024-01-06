all: editor

editor: src/*.odin rg odin_highlighter buffer_search
	odin build src/ -out:bin/editor -lld

buffer_search:
	odin build plugins/buffer_search/ -build-mode:dll -no-entry-point -out:bin/buffer_search
odin_highlighter:
	odin build plugins/highlighter/src/ -build-mode:dll -no-entry-point -out:bin/highlighter

rg:
	cargo b --manifest-path=lib-rg/Cargo.toml
