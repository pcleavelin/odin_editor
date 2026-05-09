all: plugin

plugin: plugin_obj
	riscv64-none-elf-ld -T../../third_party/riscv-emu/examples/link.ld bin/*.o --just-symbols ../../bin/stdlib.elf -o bin/plugin.elf

plugin_obj: *.odin
	mkdir -p bin
	-rm bin/*.o
	odin build . -target:freestanding_riscv64 -build-mode:object -default-to-nil-allocator -no-thread-local -no-rpath -no-crt -o:none -out:bin/plugin.o

