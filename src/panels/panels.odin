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
}

register_default_panel_actions :: proc(input_map: ^core.InputActions) {
    core.register_key_action(input_map, .H, proc(state: ^core.State, user_data: rawptr) {
        if current_panel, ok := state.current_panel.?; ok {
            if prev, ok := util.get_prev(&state.panels, current_panel).?; ok {
                state.current_panel = prev
            }
        }

        core.reset_input_map(state)
    }, "focus panel to the left");
    core.register_key_action(input_map, .L, proc(state: ^core.State, user_data: rawptr) {
        if current_panel, ok := state.current_panel.?; ok {
            if next, ok := util.get_next(&state.panels, current_panel).?; ok {
                state.current_panel = next
            }
        }

        core.reset_input_map(state)
    }, "focus panel to the right");

    core.register_key_action(input_map, .Q, proc(state: ^core.State, user_data: rawptr) {
        if current_panel, ok := state.current_panel.?; ok {
            close(state, current_panel) 
        }
    }, "close panel")
}


open :: proc(state: ^core.State, panel: core.Panel, make_active: bool = true) -> (panel_id: int, ok: bool) {
    if panel_id, panel, ok := util.append_static_list(&state.panels, panel); ok && make_active {
        panel.id = panel_id
        state.current_panel = panel_id

        arena_bytes, err := make([]u8, 1024*1024*8)
        if err != nil {
            log.errorf("failed to allocate memory for panel: '%v'", err)
            util.delete(&state.panels, panel_id)
            return 
        }

        mem.arena_init(&panel.arena, arena_bytes)
        panel.allocator = mem.arena_allocator(&panel.arena)

        panel->create(state)

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

        // TODO: keep track of the last active panel instead of focusing back to the first one
        if first_active, ok := util.get_first_active_index(&state.panels).?; ok {
            state.current_panel = first_active
        }

        core.reset_input_map(state)
    }
}
