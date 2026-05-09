package editor_bindings

import p "./plugins"
import emu "../../../third_party/riscv-emu/bindings/odin"

push_plugin_info :: proc(info: p.PluginInfo) {
    emu.emu_out_push_u32(info.version.minor)
    emu.emu_out_push_u32(info.version.major)
    emu.push_string(info.identifier)
    emu.push_string(info.name)
}
