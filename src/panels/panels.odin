package panels

import "base:runtime"
import "core:mem"
import "core:path/filepath"
import "core:fmt"
import "core:strings"
import "core:log"

import "vendor:sdl2"

import "../core"
import "../input"
import "../util"
import "../ui"

foreign import grep_lib "../pkg/grep_lib/target/debug/libgrep.a"
@(default_calling_convention = "c")
foreign grep_lib {
	grep :: proc (pattern: cstring, directory: cstring) -> RS_GrepResults ---
    free_grep_results :: proc(results: RS_GrepResults) ---
}

RS_GrepResults :: struct {
    results: [^]RS_GrepResult,
    len: u32,
}
RS_GrepResult :: struct {
    line_number: u64,
    column: u64,

    text_len: u32,
    path_len: u32,

    text: [^]u8,
    path: [^]u8,
}

@(private)
rs_grep_as_results :: proc(results: ^RS_GrepResults, allocator := context.allocator) -> []core.GrepQueryResult {
    context.allocator = allocator

    query_results := make([]core.GrepQueryResult, results.len)

    for i in 0..<results.len {
        r := results.results[i]

        query_results[i] = core.GrepQueryResult {
            file_context = strings.clone_from_ptr(r.text, int(r.text_len)) or_continue,
            file_path = strings.clone_from_ptr(r.path, int(r.path_len)) or_continue,
            line = int(r.line_number) - 1,
            col = int(r.column) - 1,
        }
    }

    return query_results
}

// NOTE: odd that this is here, but I don't feel like thinking of a better dep-tree to fix it
register_default_leader_actions :: proc(input_map: ^core.InputActions) {
    core.register_key_action(input_map, .Q, proc(state: ^core.State) {
        core.reset_input_map(state)
    }, "close this help");

    core.register_key_action(input_map, .R, proc(state: ^core.State) {
        open(state, make_grep_panel(state))
    }, "Grep Workspace")
}

register_default_panel_actions :: proc(input_map: ^core.InputActions) {
    core.register_key_action(input_map, .H, proc(state: ^core.State) {
        if current_panel, ok := state.current_panel.?; ok {
            if prev, ok := util.get_prev(&state.panels, current_panel).?; ok {
                state.current_panel = prev
            }
        }

        core.reset_input_map(state)
    }, "focus panel to the left");
    core.register_key_action(input_map, .L, proc(state: ^core.State) {
        if state.current_buffer < len(state.buffers)-1  {
            state.current_buffer += 1
        }

        if current_panel, ok := state.current_panel.?; ok {
            if next, ok := util.get_next(&state.panels, current_panel).?; ok {
                state.current_panel = next
            }
        }

        core.reset_input_map(state)
    }, "focus panel to the right");

    core.register_key_action(input_map, .Q, proc(state: ^core.State) {
        if current_panel, ok := state.current_panel.?; ok {
            close(state, current_panel) 
        }
    }, "close panel")
}


open :: proc(state: ^core.State, panel: core.Panel, make_active: bool = true) -> (panel_id: int, ok: bool) {
    if panel_id, ok := util.append_static_list(&state.panels, panel).?; ok && make_active {
        state.current_panel = panel_id

        core.reset_input_map(state)

        return panel_id, true
    }

    return -1, false
}

close :: proc(state: ^core.State, panel_id: int) {
    if panel, ok := util.get(&state.panels, panel_id).?; ok {
        if panel.drop != nil {
            panel.drop(state, &panel.panel_state)
        }

        util.delete(&state.panels, panel_id)

        // TODO: keep track of the last active panel instead of focusing back to the first one
        if first_active, ok := util.get_first_active_index(&state.panels).?; ok {
            state.current_panel = first_active
        }

        core.reset_input_map(state)
    }
}

open_file_buffer_in_new_panel :: proc(state: ^core.State, file_path: string, line, col: int) -> (panel_id, buffer_index: int, ok: bool) {
    buffer, err := core.new_file_buffer(context.allocator, file_path, state.directory);
    if err.type != .None {
        log.error("Failed to create file buffer:", err);
        return;
    }

    buffer.cursor.line = line
    buffer.cursor.col = col
    core.update_file_buffer_index_from_cursor(&buffer)
    core.update_file_buffer_scroll(&buffer)

    buffer_index = len(state.buffers)
    runtime.append(&state.buffers, buffer);

    if panel_id, ok := open(state, make_file_buffer_panel(buffer_index)); ok {
        return panel_id, buffer_index, true
    }

    return -1, -1, false
}

render_file_buffer :: proc(state: ^core.State, s: ^ui.State, buffer: ^core.FileBuffer) {
    draw_func := proc(state: ^core.State, e: ui.UI_Element, user_data: rawptr) {
        buffer := transmute(^core.FileBuffer)user_data;
        if buffer != nil {
            buffer.glyphs.width = e.layout.size.x / state.source_font_width;
            buffer.glyphs.height = e.layout.size.y / state.source_font_height + 1;

            core.draw_file_buffer(state, buffer, e.layout.pos.x, e.layout.pos.y);
        }
    };

    relative_file_path, _ := filepath.rel(state.directory, buffer.file_path, context.temp_allocator)

    ui.open_element(s, nil, {
        dir = .TopToBottom,
        kind = {ui.Grow{}, ui.Grow{}},
    })
    {
        ui.open_element(s, ui.UI_Element_Kind_Custom{fn = draw_func, user_data = transmute(rawptr)buffer}, {
            kind = {ui.Grow{}, ui.Grow{}}
        })
        ui.close_element(s)

        ui.open_element(s, nil, {
            kind = {ui.Grow{}, ui.Exact(state.source_font_height)}
        })
        {
            ui.open_element(s, fmt.tprintf("%s", state.mode), {})
            ui.close_element(s)

            ui.open_element(s, nil, { kind = {ui.Grow{}, ui.Grow{}}})
            ui.close_element(s)

            it := core.new_file_buffer_iter_with_cursor(buffer, buffer.cursor)
            ui.open_element(
                s,
                fmt.tprintf(
                    "%v:%v - Slice %v:%v - Char: %v",
                    buffer.cursor.line + 1,
                    buffer.cursor.col + 1,
                    buffer.cursor.index.slice_index,
                    buffer.cursor.index.content_index,
                    core.get_character_at_iter(it)
                ),
                {}
            )
            ui.close_element(s)
        }
        ui.close_element(s)
    }
    ui.close_element(s)
}

render_raw_buffer :: proc(state: ^core.State, s: ^ui.State, buffer: ^core.FileBuffer) {
    draw_func := proc(state: ^core.State, e: ui.UI_Element, user_data: rawptr) {
        buffer := transmute(^core.FileBuffer)user_data;
        if buffer != nil {
            buffer.glyphs.width = e.layout.size.x / state.source_font_width;
            buffer.glyphs.height = e.layout.size.y / state.source_font_height + 1;

            core.draw_file_buffer(state, buffer, e.layout.pos.x, e.layout.pos.y, false);
        }
    };

    ui.open_element(s, ui.UI_Element_Kind_Custom{fn = draw_func, user_data = transmute(rawptr)buffer}, {
        kind = {ui.Grow{}, ui.Grow{}}
    })
    ui.close_element(s)
    
}

render_glyph_buffer :: proc(state: ^core.State, s: ^ui.State, glyphs: ^core.GlyphBuffer) {
    draw_func := proc(state: ^core.State, e: ui.UI_Element, user_data: rawptr) {
        glyphs := transmute(^core.GlyphBuffer)user_data;
        if glyphs != nil {
            glyphs.width = e.layout.size.x / state.source_font_width;
            glyphs.height = e.layout.size.y / state.source_font_height + 1;

            core.draw_glyph_buffer(state, glyphs, e.layout.pos.x, e.layout.pos.y, 0, true);
        }
    };

    ui.open_element(s, ui.UI_Element_Kind_Custom{fn = draw_func, user_data = transmute(rawptr)glyphs}, {
        kind = {ui.Grow{}, ui.Grow{}}
    })
    ui.close_element(s)
    
}

make_file_buffer_panel :: proc(buffer_index: int) -> core.Panel {
    input_map := core.new_input_map()

    leader_actions := core.new_input_actions()
    register_default_leader_actions(&leader_actions);
    core.register_key_action(&input_map.mode[.Normal], .SPACE, leader_actions, "leader commands");

    core.register_ctrl_key_action(&input_map.mode[.Normal], .W, core.new_input_actions(), "Panel Navigation") 
    register_default_panel_actions(&(&input_map.mode[.Normal].ctrl_key_actions[.W]).action.(core.InputActions))


    input.register_default_input_actions(&input_map.mode[.Normal]);
    input.register_default_visual_actions(&input_map.mode[.Visual]);
    input.register_default_text_input_actions(&input_map.mode[.Normal]);

    return core.Panel {
        panel_state = core.FileBufferPanel { buffer_index = buffer_index },
        input_map = input_map,
        buffer_proc = proc(state: ^core.State, panel_state: ^core.PanelState) -> (buffer: ^core.FileBuffer, ok: bool) {
            panel_state := panel_state.(core.FileBufferPanel) or_return;

            return &state.buffers[panel_state.buffer_index], true
        },
        render_proc = proc(state: ^core.State, panel_state: ^core.PanelState) -> (ok: bool) {
            panel_state := panel_state.(core.FileBufferPanel) or_return;
            s := transmute(^ui.State)state.ui
            buffer := &state.buffers[panel_state.buffer_index]

            render_file_buffer(state, s, buffer)

            return true
        }
    }
}

make_grep_panel :: proc(state: ^core.State) -> core.Panel {
    query_arena: mem.Arena
    mem.arena_init(&query_arena, make([]u8, 1024*1024*2, state.ctx.allocator))

    glyphs := core.make_glyph_buffer(256,256, allocator = mem.arena_allocator(&query_arena))

    input_map := core.new_input_map()
    grep_input_buffer := core.new_virtual_file_buffer(context.allocator)
    runtime.append(&state.buffers, grep_input_buffer)

    run_query :: proc(panel_state: ^core.GrepPanel, query: string, directory: string) {
        if panel_state.query_region.arena != nil {
            mem.end_arena_temp_memory(panel_state.query_region)
        }
        panel_state.query_region = mem.begin_arena_temp_memory(&panel_state.query_arena)

        context.allocator = mem.arena_allocator(&panel_state.query_arena)

        rs_results := grep(
            strings.clone_to_cstring(query, allocator = context.temp_allocator),
            strings.clone_to_cstring(directory, allocator = context.temp_allocator)
        );

        panel_state.query_results = rs_grep_as_results(&rs_results)
        free_grep_results(rs_results)

        panel_state.selected_result = 0
        core.update_glyph_buffer_from_bytes(
            &panel_state.glyphs,
            transmute([]u8)panel_state.query_results[panel_state.selected_result].file_context,
            panel_state.query_results[panel_state.selected_result].line,
        )
    }

    core.register_key_action(&input_map.mode[.Normal], .ENTER, proc(state: ^core.State) {
        if current_panel, ok := util.get(&state.panels, state.current_panel.? or_else -1).?; ok {
            this_panel := state.current_panel.?

            if panel_state, ok := &current_panel.panel_state.(core.GrepPanel); ok {
                if panel_state.query_results != nil {
                    selected_result := &panel_state.query_results[panel_state.selected_result]

                    if panel_id, buffer, ok := open_file_buffer_in_new_panel(state, selected_result.file_path, selected_result.line, selected_result.col); ok {
                        close(state, this_panel)

                        state.current_panel = panel_id
                        state.current_buffer = buffer
                    } else {
                        log.error("failed to open file buffer in new panel")
                    }
                }
            }
        }
    }, "Open File");
    core.register_key_action(&input_map.mode[.Normal], .I, proc(state: ^core.State) {
        state.mode = .Insert;
        sdl2.StartTextInput();
    }, "enter insert mode");
    core.register_key_action(&input_map.mode[.Normal], .K, proc(state: ^core.State) {
        // NOTE: this is really jank, should probably update the input
        // action stuff to allow panels to be passed into these handlers
        if current_panel, ok := util.get(&state.panels, state.current_panel.? or_else -1).?; ok {
            if panel_state, ok := &current_panel.panel_state.(core.GrepPanel); ok {
                // TODO: bounds checking
                panel_state.selected_result -= 1

                core.update_glyph_buffer_from_bytes(
                    &panel_state.glyphs,
                    transmute([]u8)panel_state.query_results[panel_state.selected_result].file_context,
                    panel_state.query_results[panel_state.selected_result].line,
                )
            }
        }
    }, "move selection up");
    core.register_key_action(&input_map.mode[.Normal], .J, proc(state: ^core.State) {
        // NOTE: this is really jank, should probably update the input
        // action stuff to allow panels to be passed into these handlers
        if current_panel, ok := util.get(&state.panels, state.current_panel.? or_else -1).?; ok {
            if panel_state, ok := &current_panel.panel_state.(core.GrepPanel); ok {
                // TODO: bounds checking
                panel_state.selected_result += 1

                core.update_glyph_buffer_from_bytes(
                    &panel_state.glyphs,
                    transmute([]u8)panel_state.query_results[panel_state.selected_result].file_context,
                    panel_state.query_results[panel_state.selected_result].line,
                )
            }
        }
    }, "move selection down");

    core.register_key_action(&input_map.mode[.Insert], .ESCAPE, proc(state: ^core.State) {
        state.mode = .Normal;
        sdl2.StopTextInput();
    }, "exit insert mode");
    core.register_key_action(&input_map.mode[.Normal], .ESCAPE, proc(state: ^core.State) {
        if state.current_panel != nil {
            close(state, state.current_panel.?)
        }
    }, "close panel");


    return core.Panel {
        panel_state = core.GrepPanel {
            query_arena = query_arena,
            buffer = len(state.buffers)-1,
            query_results = nil,
            glyphs = glyphs,
        },
        input_map = input_map,
        buffer_proc = proc(state: ^core.State, panel_state: ^core.PanelState) -> (buffer: ^core.FileBuffer, ok: bool) {
            panel_state := panel_state.(core.GrepPanel) or_return;

            return &state.buffers[panel_state.buffer], true
        },
        on_buffer_input_proc = proc(state: ^core.State, panel_state: ^core.PanelState) {
            if panel_state, ok := &panel_state.(core.GrepPanel); ok {
                buffer := &state.buffers[panel_state.buffer]
                run_query(panel_state, string(buffer.input_buffer[:]), state.directory)
            }
        },
        drop = proc(state: ^core.State, panel_state: ^core.PanelState) {
            if panel_state, ok := &panel_state.(core.GrepPanel); ok {
                delete(panel_state.query_arena.data, state.ctx.allocator)
            }
        },
        render_proc = proc(state: ^core.State, panel_state: ^core.PanelState) -> (ok: bool) {
            if panel_state, ok := &panel_state.(core.GrepPanel); ok {
                s := transmute(^ui.State)state.ui

                ui.open_element(s, nil, {
                    dir = .TopToBottom,
                    kind = {ui.Grow{}, ui.Grow{}}
                })
                {
                    // query results and file contents side-by-side
                    ui.open_element(s, nil, {
                        dir = .LeftToRight,
                        kind = {ui.Grow{}, ui.Grow{}}
                    })
                    {
                        if panel_state.query_results != nil {
                            // query results
                            ui.open_element(s, nil, {
                                dir = .TopToBottom,
                                kind = {ui.Grow{}, ui.Grow{}}
                            })
                            {
                                for result, i in panel_state.query_results {
                                    ui.open_element(s, nil, {
                                        dir = .LeftToRight,
                                        kind = {ui.Fit{}, ui.Fit{}},
                                    })
                                    {
                                        defer ui.close_element(s)

                                        ui.open_element(s, fmt.tprintf("%v:%v: ", result.line, result.col), {})
                                        ui.close_element(s)

                                        // TODO: when styling is implemented, make this look better
                                        if panel_state.selected_result == i {
                                            ui.open_element(s, fmt.tprintf("%s <--", result.file_path), {})
                                            ui.close_element(s)
                                        } else {
                                            ui.open_element(s, result.file_path, {})
                                            ui.close_element(s)
                                        }
                                    }
                                }
                            }
                            ui.close_element(s)

                            // file contents
                            selected_result := &panel_state.query_results[panel_state.selected_result]
                            render_glyph_buffer(state, s, &panel_state.glyphs)
                        }
                    }
                    ui.close_element(s)

                    // text input
                    ui.open_element(s, nil, {
                        kind = {ui.Grow{}, ui.Exact(state.source_font_height)}
                    })
                    { 
                        defer ui.close_element(s)

                        render_raw_buffer(state, s, &state.buffers[panel_state.buffer])
                    }
                }
                ui.close_element(s)

                return true
            }

            return false
        }
    }
}