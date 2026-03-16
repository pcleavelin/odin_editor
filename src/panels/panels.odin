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

    core.register_key_action(input_map, .F, proc(state: ^core.State, user_data: rawptr) {
        open_file_finder_panel(state)
    }, "Find File")

    core.register_key_action(input_map, .P, proc(state: ^core.State, user_data: rawptr) {
        open(state, make_cmd_palette_panel())

        state.mode = .Insert
        sdl2.StartTextInput()
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
            if neighbour := core.split_tree_navigate(&state.split_tree, current_panel, .Left); neighbour != -1 {
                core.switch_to_panel(state, neighbour)
            }
        }
        core.reset_input_map(state)
    }, "focus panel to the left")

    core.register_key_action(input_map, .L, proc(state: ^core.State, user_data: rawptr) {
        if current_panel, ok := state.current_panel.?; ok {
            if neighbour := core.split_tree_navigate(&state.split_tree, current_panel, .Right); neighbour != -1 {
                core.switch_to_panel(state, neighbour)
            }
        }
        core.reset_input_map(state)
    }, "focus panel to the right")

    core.register_key_action(input_map, .K, proc(state: ^core.State, user_data: rawptr) {
        if current_panel, ok := state.current_panel.?; ok {
            if neighbour := core.split_tree_navigate(&state.split_tree, current_panel, .Up); neighbour != -1 {
                core.switch_to_panel(state, neighbour)
            }
        }
        core.reset_input_map(state)
    }, "focus panel above")

    core.register_key_action(input_map, .J, proc(state: ^core.State, user_data: rawptr) {
        if current_panel, ok := state.current_panel.?; ok {
            if neighbour := core.split_tree_navigate(&state.split_tree, current_panel, .Down); neighbour != -1 {
                core.switch_to_panel(state, neighbour)
            }
        }
        core.reset_input_map(state)
    }, "focus panel below")

    core.register_key_action(input_map, .V, proc(state: ^core.State, user_data: rawptr) {
        open(state, make_file_buffer_panel(), .Vertical)
        core.reset_input_map(state)
    }, "split panel vertically")

    core.register_key_action(input_map, .S, proc(state: ^core.State, user_data: rawptr) {
        open(state, make_file_buffer_panel(), .Horizontal)
        core.reset_input_map(state)
    }, "split panel horizontally")

    core.register_key_action(input_map, .Q, proc(state: ^core.State, user_data: rawptr) {
        if current_panel, ok := state.current_panel.?; ok {
            close(state, current_panel)
        }
    }, "close panel")
}


open :: proc(state: ^core.State, panel: core.Panel, dir: core.SplitDir = .Vertical, data: rawptr = nil, make_active: bool = true) -> (panel_id: int, ok: bool) {
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

        // Maintain the split tree for non-floating panels
        if !panel.is_floating {
            if core.split_tree_is_empty(&state.split_tree) {
                core.split_tree_init(&state.split_tree, panel_id)
            } else if current, ok := state.current_panel.?; ok {
                core.split_tree_split(&state.split_tree, current, panel_id, dir)
            }
        }

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

        // Remove from the split tree before removing from the list
        survivor := -1
        if !panel.is_floating {
            survivor = core.split_tree_close(&state.split_tree, panel_id)
        }

        mem.free(raw_data(panel.arena.data))
        util.delete(&state.panels, panel_id)

        if survivor != -1 && util.static_list_elem_is_active(&state.panels, survivor) {
            core.switch_to_panel(state, survivor)
        } else if last_panel, ok := state.last_panel.?; ok && util.static_list_elem_is_active(&state.panels, last_panel) {
            core.switch_to_panel(state, last_panel)
        } else if first_active, ok := util.get_first_active_index(&state.panels).?; ok {
            state.current_panel = first_active
        } else {
            new_id, _ := open(state, make_file_buffer_panel())
            core.switch_to_panel(state, new_id)
        }

        core.reset_input_map(state)
    }
}
