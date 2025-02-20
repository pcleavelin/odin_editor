all: editor

editor: src/*.odin  # grep odin_highlighter
	# odin build src/ -out:bin/editor.o -build-mode:obj -debug -lld
	# dsymutil bin/editor.o -o bin/editor.dSYM
	../Odin/odin build src/ -out:bin/editor -debug -lld -extra-linker-flags:"-L./"

odin_highlighter: plugins/highlighter/src/*.odin
	../Odin/odin build plugins/highlighter/src/ -build-mode:dll -no-entry-point -out:bin/highlighter

grep: plugins/grep/src/*.rs
	nightly-cargo b --manifest-path=plugins/grep/Cargo.toml
	cp plugins/grep/target/debug/libgrep_plugin.dylib bin/
