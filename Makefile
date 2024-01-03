all: editor

editor: src/*.odin rg
	odin build src/ -out:bin/editor -lld

rg:
	cargo b --manifest-path=lib-rg/Cargo.toml
