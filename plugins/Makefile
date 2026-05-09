all: bookmarks-plugin

bookmarks-plugin: bookmarks/plugin.odin
	mkdir -p bin
	cd bookmarks && $(MAKE)
	cp bookmarks/bin/plugin.elf bin/bookmarks.elf
