all: editor

editor: src/**/*.odin
	mkdir -p bin
	odin build src/ -out:bin/editor -debug