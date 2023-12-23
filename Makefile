all: editor

editor: src/*.odin
	odin build src/ -out:bin/editor -lld
