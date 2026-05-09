package core

import emu "../../third_party/riscv-emu/src/emu_core"
import p "../../plugins/bindings/odin/plugins"

PLUGIN_MEM :: 1024 * 512

Plugin :: struct {
    emu: emu.Emu64,
    info: p.PluginInfo,
}

plugin_load :: proc(path: string) -> (plugin: Plugin, ok: bool) {
    plugin.emu = emu.emu_make(PLUGIN_MEM)

    emu.emu_load_elf(&plugin.emu, "bin/stdlib.elf")
    emu.emu_load_elf(&plugin.emu, path)
    emu.emu_run_function(&plugin.emu, "_start")

    plugin.info = plugin_get_info(&plugin.emu) or_return

    return plugin, true
}

plugin_get_info :: proc(e: ^emu.Emu64) -> (info: p.PluginInfo, ok: bool) {
    emu.emu_run_function(e, "plugin_info")

    info.name = emu.emu_comm_stack_pop_string(e) or_return
    info.identifier = emu.emu_comm_stack_pop_string(e) or_return
    info.version.major = emu.emu_comm_stack_pop_u32(e) or_return
    info.version.minor = emu.emu_comm_stack_pop_u32(e) or_return

    return info, true
}
