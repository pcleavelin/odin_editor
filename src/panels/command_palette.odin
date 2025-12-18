package panels

import "base:runtime"
import "core:mem"
import "core:fmt"
import "core:strings"
import "core:log"

import "vendor:sdl2"

import "../core"
import "../util"
import "../ui"

CommandPalettePanel :: struct {
    buffer: core.FileBuffer,
}

make_cmd_palette_panel :: proc() -> core.Panel {
    return core.Panel {
        is_floating = true,
        name = proc(panel: ^core.Panel) -> string {
            return "CommandPalettePanel"
        },
        drop = proc(panel: ^core.Panel, state: ^core.State) {
        },
        create = proc(panel: ^core.Panel, state: ^core.State, data: rawptr) {
            context.allocator = panel.allocator

            panel.state = transmute(core.PanelState)new(CommandPalettePanel)
            panel_state := transmute(^CommandPalettePanel)panel.state
            panel_state^ = CommandPalettePanel {}

            panel.input_map = core.new_input_map(show_help = true)
            panel_state.buffer = core.new_virtual_file_buffer()

            core.register_key_action(&panel.input_map.mode[.Insert], .ESCAPE, proc(state: ^core.State, user_data: rawptr) {
                state.mode = .Normal;
                sdl2.StopTextInput();
            }, "exit insert mode");
            core.register_key_action(&panel.input_map.mode[.Normal], .ESCAPE, proc(state: ^core.State, user_data: rawptr) {
                this_panel := transmute(^core.Panel)user_data
                close(state, this_panel.id)
            }, "close panel");
        },
        buffer = proc(panel: ^core.Panel, state: ^core.State) -> (buffer: ^core.FileBuffer, ok: bool) {
            panel_state := transmute(^CommandPalettePanel )panel.state

            return &panel_state.buffer, true
        },
        render = proc(panel: ^core.Panel, state: ^core.State) -> (ok: bool) {
            return true
        },
    }
}
