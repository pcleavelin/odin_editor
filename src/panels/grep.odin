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

open_grep_panel :: proc(state: ^core.State) {
    open(state, make_grep_panel())

    state.mode = .Insert
    sdl2.StartTextInput()
}

make_grep_panel :: proc() -> core.Panel {
    run_query :: proc(panel_state: ^core.GrepPanel, query: string, directory: string) {
        if panel_state.query_region.arena != nil {
            mem.end_arena_temp_memory(panel_state.query_region)
        }
        panel_state.query_region = mem.begin_arena_temp_memory(&panel_state.query_arena)

        context.allocator = mem.arena_allocator(&panel_state.query_arena)

        rs_results := grep(
            strings.clone_to_cstring(query),
            strings.clone_to_cstring(directory)
        );

        panel_state.query_results = rs_grep_as_results(&rs_results)

        panel_state.selected_result = 0
        if len(panel_state.query_results) > 0 {
            core.update_glyph_buffer_from_bytes(
                &panel_state.glyphs,
                transmute([]u8)panel_state.query_results[panel_state.selected_result].file_context,
                panel_state.query_results[panel_state.selected_result].line,
            )
        }
    }

    return core.Panel {
        type = core.GrepPanel {},
        is_floating = true,
        drop = proc(panel: ^core.Panel, state: ^core.State) {
            panel_state := &panel.type.(core.GrepPanel)

            ts.delete_state(&panel_state.buffer.tree)
        },
        create = proc(panel: ^core.Panel, state: ^core.State) {
            context.allocator = panel.allocator

            panel_state := &panel.type.(core.GrepPanel)

            arena_bytes, err := make([]u8, 1024*1024*2)
            if err != nil {
                log.errorf("failed to allocate arena for grep panel: '%v'", err)
                return
            }
            mem.arena_init(&panel_state.query_arena, arena_bytes)

            panel.input_map = core.new_input_map(show_help = true)
            panel_state.glyphs = core.make_glyph_buffer(256,256)
            panel_state.buffer = core.new_virtual_file_buffer()

            panel_actions := core.new_input_actions(show_help = true)
            register_default_panel_actions(&panel_actions)
            core.register_ctrl_key_action(&panel.input_map.mode[.Normal], .W, panel_actions, "Panel Navigation") 

            core.register_key_action(&panel.input_map.mode[.Normal], .ENTER, proc(state: ^core.State, user_data: rawptr) {
                this_panel := transmute(^core.Panel)user_data

                if panel_state, ok := &this_panel.type.(core.GrepPanel); ok {
                    if panel_state.query_results != nil {
                        selected_result := &panel_state.query_results[panel_state.selected_result]

                        if panel_id, ok := open(state, make_file_buffer_panel(selected_result.file_path, selected_result.line, selected_result.col)); ok {
                            close(state, this_panel.id)

                            state.current_panel = panel_id
                        } else {
                            log.error("failed to open file buffer in new panel")
                        }
                    }
                }
            }, "Open File");
            core.register_key_action(&panel.input_map.mode[.Normal], .I, proc(state: ^core.State, user_data: rawptr) {
                state.mode = .Insert;
                sdl2.StartTextInput();
            }, "enter insert mode");
            core.register_key_action(&panel.input_map.mode[.Normal], .K, proc(state: ^core.State, user_data: rawptr) {
                this_panel := transmute(^core.Panel)user_data

                if panel_state, ok := &this_panel.type.(core.GrepPanel); ok {
                    // TODO: bounds checking
                    panel_state.selected_result -= 1

                    core.update_glyph_buffer_from_bytes(
                        &panel_state.glyphs,
                        transmute([]u8)panel_state.query_results[panel_state.selected_result].file_context,
                        panel_state.query_results[panel_state.selected_result].line,
                    )
                }
            }, "move selection up");
            core.register_key_action(&panel.input_map.mode[.Normal], .J, proc(state: ^core.State, user_data: rawptr) {
                this_panel := transmute(^core.Panel)user_data

                if panel_state, ok := &this_panel.type.(core.GrepPanel); ok {
                    // TODO: bounds checking
                    panel_state.selected_result += 1

                    core.update_glyph_buffer_from_bytes(
                        &panel_state.glyphs,
                        transmute([]u8)panel_state.query_results[panel_state.selected_result].file_context,
                        panel_state.query_results[panel_state.selected_result].line,
                    )
                }
            }, "move selection down");

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
            if panel_state, ok := &panel.type.(core.GrepPanel); ok {
                return &panel_state.buffer, true
            }

            return
        },
        on_buffer_input = proc(panel: ^core.Panel, state: ^core.State) {
            if panel_state, ok := &panel.type.(core.GrepPanel); ok {
                run_query(panel_state, string(panel_state.buffer.input_buffer[:]), state.directory)
            }
        },
        render = proc(panel: ^core.Panel, state: ^core.State) -> (ok: bool) {
            if panel_state, ok := &panel.type.(core.GrepPanel); ok {
                s := transmute(^ui.State)state.ui

                ui.open_element(s, nil,
                    {
                        dir = .TopToBottom,
                        kind = {ui.Grow{}, ui.Grow{}},
                        floating = true, 
                    },
                    style = {
                        background_color = .Background1,
                    },
                )
                {
                    // query results and file contents side-by-side
                    ui.open_element(s, nil, {
                        dir = .LeftToRight,
                        kind = {ui.Grow{}, ui.Grow{}}
                    })
                    {
                        if panel_state.query_results != nil {
                            // query results
                            query_result_container := ui.open_element(s, nil,
                                {
                                    dir = .TopToBottom,
                                    kind = {ui.Grow{}, ui.Grow{}}
                                },
                                style = {
                                    border = {.Right},
                                    border_color = .Background4
                                }
                            )
                            {
                                container_height := query_result_container.layout.size.y
                                max_results := container_height / 16

                                for result, i in panel_state.query_results {
                                    if i > max_results {
                                        break
                                    }

                                    ui.open_element(s, nil, {
                                        dir = .LeftToRight,
                                        kind = {ui.Fit{}, ui.Fit{}},
                                    })
                                    {
                                        defer ui.close_element(s)

                                        ui.open_element(s, fmt.tprintf("%v:%v: ", result.line, result.col), {})
                                        ui.close_element(s)


                                        style := ui.UI_Style{}

                                        if panel_state.selected_result == i {
                                            style.background_color = .Background2
                                        }

                                        ui.open_element(s, result.file_path[len(state.directory):], {}, style)
                                        ui.close_element(s)
                                    }
                                }
                            }
                            ui.close_element(s)

                            // file contents
                            selected_result := &panel_state.query_results[panel_state.selected_result]

                            core.update_glyph_buffer_from_bytes(
                                &panel_state.glyphs,
                                transmute([]u8)selected_result.file_context,
                                selected_result.line,
                            )
                            render_glyph_buffer(state, s, &panel_state.glyphs)
                        }
                    }
                    ui.close_element(s)

                    // text input
                    ui.open_element(s, nil,
                        {
                            kind = {ui.Grow{}, ui.Exact(state.source_font_height)}
                        },
                        style = {
                            background_color = .Background2
                        }
                    )
                    { 
                        defer ui.close_element(s)

                        render_raw_buffer(state, s, &panel_state.buffer)
                    }
                }
                ui.close_element(s)

                return true
            }

            return false
        }
    }
}

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

    free_grep_results(results^)
    return query_results
}

render_raw_buffer :: proc(state: ^core.State, s: ^ui.State, buffer: ^core.FileBuffer) {
    draw_func := proc(state: ^core.State, e: ui.UI_Element, user_data: rawptr) {
        buffer := transmute(^core.FileBuffer)user_data;
        if buffer != nil {
            core.draw_file_buffer(state, buffer, e.layout.pos.x, e.layout.pos.y, e.layout.size.x, e.layout.size.y, false);
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
