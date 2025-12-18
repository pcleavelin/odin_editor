package panels

import "base:runtime"
import "core:mem"
import "core:fmt"
import "core:strings"
import "core:log"

import "vendor:sdl2"

import ts "../tree_sitter"
import "../core"
import "../util"
import "../ui"

register_default_leader_actions :: proc(input_map: ^core.InputActions) {
    core.register_key_action(input_map, .Q, proc(state: ^core.State, user_data: rawptr) {
        core.reset_input_map(state)
    }, "close this help");

    core.register_key_action(input_map, .R, proc(state: ^core.State, user_data: rawptr) {
        open_grep_panel(state)
    }, "Grep Workspace")

    core.register_key_action(input_map, .P, proc(state: ^core.State, user_data: rawptr) {
        open(state, make_cmd_palette_panel())
    }, "Command Palette")

    core.register_key_action(input_map, .COMMA, proc(state: ^core.State, user_data: rawptr) {
        current_panel := state.current_panel

        open(state, make_debug_panel())

        state.current_panel = current_panel

        core.reset_input_map(state)
    }, "DEBUG WINDOW")
}

register_default_panel_actions :: proc(input_map: ^core.InputActions) {
    core.register_key_action(input_map, .H, proc(state: ^core.State, user_data: rawptr) {
        if current_panel, ok := state.current_panel.?; ok {
            if prev, ok := util.get_prev(&state.panels, current_panel).?; ok {
                core.switch_to_panel(state, prev)
            }
        }

        core.reset_input_map(state)
    }, "focus panel to the left");
    core.register_key_action(input_map, .L, proc(state: ^core.State, user_data: rawptr) {
        if current_panel, ok := state.current_panel.?; ok {
            if next, ok := util.get_next(&state.panels, current_panel).?; ok {
                core.switch_to_panel(state, next)
            }
        }

        core.reset_input_map(state)
    }, "focus panel to the right");

    core.register_key_action(input_map, .V, proc(state: ^core.State, user_data: rawptr) {
        open(state, make_file_buffer_panel())

        core.reset_input_map(state)
    }, "Split Panel");

    core.register_key_action(input_map, .Q, proc(state: ^core.State, user_data: rawptr) {
        if current_panel, ok := state.current_panel.?; ok {
            close(state, current_panel) 
        }
    }, "close panel")
}


open :: proc(state: ^core.State, panel: core.Panel, data: rawptr = nil, make_active: bool = true) -> (panel_id: int, ok: bool) {
    if panel_id, panel, ok := util.append_static_list(&state.panels, panel); ok && make_active {
        panel.id = panel_id

        arena_bytes, err := make([]u8, 1024*1024*64)
        if err != nil {
            log.errorf("failed to allocate memory for panel: '%v'", err)
            util.delete(&state.panels, panel_id)
            return 
        }

        mem.arena_init(&panel.arena, arena_bytes)
        panel.allocator = mem.arena_allocator(&panel.arena)

        if panel.name == nil {
            panel.name = proc(panel: ^core.Panel) -> string { return "Unknown Panel" }
        }

        panel->create(state, data)

        core.switch_to_panel(state, panel_id)
        core.reset_input_map(state)

        return panel_id, true
    }

    return -1, false
}

close :: proc(state: ^core.State, panel_id: int) {
    if panel, ok := util.get(&state.panels, panel_id).?; ok {
        if panel.drop != nil {
            panel->drop(state)
        }

        mem.free(raw_data(panel.arena.data))

        util.delete(&state.panels, panel_id)

        if last_panel, ok := state.last_panel.?; ok {
            core.switch_to_panel(state, last_panel)
        } else if first_active, ok := util.get_first_active_index(&state.panels).?; ok {
            state.current_panel = first_active
        } else {
            // TODO: open panel
        }

        core.reset_input_map(state)
    }
}
