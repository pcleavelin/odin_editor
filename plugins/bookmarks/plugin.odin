package bookmarks

import emu "../../third_party/riscv-emu/bindings/odin"

import p "../bindings/odin/plugins"
import editor "../bindings/odin"

@(export)
plugin_info :: proc() {
    context = emu.EMU_CONTEXT

    editor.push_plugin_info(p.PluginInfo {
        name = "Bookmarks (Builtin)",
        identifier = "nl.spacegirl.Bookmarks",
        version = p.PluginVersion {
            major = 0,
            minor = 1,
        },
    })

    emu.emu_out_push_u32(0)
}

@(export)
plugin_init :: proc() {
    context = emu.EMU_CONTEXT

    // TODO

    emu.emu_out_push_u32(0)
}
