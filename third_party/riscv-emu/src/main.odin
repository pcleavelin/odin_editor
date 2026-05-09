package main

import "core:fmt"

import emu "./emu_core"

MAX_PHYS_MEM :: 1024 * 512 // 512KB

run_program :: proc(e: ^emu.Emu64, path: string) -> (ok: bool) {
    lib_addr := emu.emu_load_elf(e, "bin/stdlib.elf") or_return
    user_addr := emu.emu_load_elf(e, path) or_return

    emu.emu_set_break_point(e, 0x0)

    emu.emu_run_function(e, "_start")
    emu.emu_run_function(e, "plugin_start")

    return true
}

main :: proc() {
    e := emu.emu_make(MAX_PHYS_MEM)

    ok := run_program(&e, "examples/host_to_guest/out/prog.elf")
    if !ok do return
}
