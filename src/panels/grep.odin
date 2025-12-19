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
import "../jobs"

import ring "../util/ring_buffer"

MAX_GREP_RESULTS :: 2000

GrepPanel :: struct {
    buffer: core.FileBuffer,
    selected_result: int,
    results_start: int,
    search_query: string,
    glyphs: core.GlyphBuffer,

    query_arena: mem.Arena,
    query_results: []GrepQueryResult,

    query_queue: jobs.JobQueue,
}

GrepQueryResult :: struct {
    file_context: string,
    file_path: string,
    line: int,
    col: int,
}

open_grep_panel :: proc(state: ^core.State) {
    open(state, make_grep_panel())

    state.mode = .Insert
    sdl2.StartTextInput()
}

GrepQuery :: struct {
    search_query: string,
    directory: string
}

@(private)
query_handler :: proc(job: ^jobs.Job) {
    context.allocator = job.allocator

    input := transmute(^GrepQuery)job.input

    rs_results := grep(
        strings.clone_to_cstring(input.search_query),
        strings.clone_to_cstring(input.directory),
    );

    results_ptr, err := mem.alloc(size_of(RS_GrepResults), allocator = job.allocator)
    if err != .None {
        fmt.eprintln("failed to allocate grep results")
        job.output = nil
        return
    }
    mem.copy_non_overlapping(results_ptr, &rs_results, size_of(RS_GrepResults))

    job.output = results_ptr
}

@(private)
pop_job_results :: proc(panel_state: ^GrepPanel) {
    has_results := false
    for {
        job, did_pop := jobs.pop(&panel_state.query_queue);
        has_results = did_pop
        
        if !did_pop || job.output == nil  {
            break
        }

        panel_state.query_results = nil
        context.allocator = mem.arena_allocator(&panel_state.query_arena)

        mem.free_all()

        panel_state.query_results = rs_grep_as_results(transmute(^RS_GrepResults)job.output)

        jobs.destroy_job(&panel_state.query_queue, job)
    }

    if has_results && panel_state.query_results != nil {
        panel_state.selected_result = 0
        if len(panel_state.query_results) > 0 {
            core.update_glyph_buffer_from_bytes(
                &panel_state.glyphs,
                transmute([]u8)panel_state.query_results[panel_state.selected_result].file_context,
                panel_state.query_results[panel_state.selected_result].line,
            )
        }
    }
}

make_grep_panel :: proc() -> core.Panel {
    run_query :: proc(panel_state: ^GrepPanel, buffer: ^core.FileBuffer, directory: string) {
        search_query := core.buffer_to_string(buffer, allocator = context.temp_allocator)

        // NOTE: no reason to grep the whole workspace with a single character
        if len(search_query) > 1 {
            copy_grep_query :: proc(cursor: ^ring.WriteCursor, data: []u8, w: ring.WriteVTable) {
                query := transmute(^GrepQuery)&data[0]

                w.write_string(cursor, query.search_query)
                w.write_string(cursor, query.directory)
            }

            pop_grep_query :: proc(cursor: ^ring.ReadCursor, r: ring.ReadVTable, allocator: mem.Allocator) -> rawptr {
                search_query := r.read_string(cursor, allocator)
                directory := r.read_string(cursor, allocator)

                data, err := mem.alloc(size_of(GrepQuery), allocator = allocator)

                query := transmute(^GrepQuery)data
                query.search_query = search_query
                query.directory = directory

                return query
            }

            data := GrepQuery {
                search_query = search_query,
                directory = directory,
            }
            jobs.add(GrepQuery, &panel_state.query_queue, query_handler, data, copy_grep_query, pop_grep_query, name = "grep task")
        } else {
            panel_state.selected_result = 0
            panel_state.query_results = nil
        }
    }

    return core.Panel {
        is_floating = true,
        name = proc(panel: ^core.Panel) -> string {
            return "GrepPanel"
        },
        drop = proc(panel: ^core.Panel, state: ^core.State) {
            panel_state := transmute(^GrepPanel)panel.state

            jobs.destroy_job_queue(&panel_state.query_queue)
            ts.delete_state(&panel_state.buffer.tree)
        },
        create = proc(panel: ^core.Panel, state: ^core.State, data: rawptr) {
            context.allocator = panel.allocator

            panel.state = transmute(core.PanelState)new(GrepPanel)
            panel_state := transmute(^GrepPanel)panel.state
            panel_state^ = GrepPanel {}

            panel.input_map = core.new_input_map(show_help = true)
            panel_state.glyphs = core.make_glyph_buffer(256,256)
            panel_state.buffer = core.new_virtual_file_buffer()
            jobs.make_job_queue(panel.allocator, 2, &panel_state.query_queue)


            arena_bytes, err := make([]u8, MAX_GREP_RESULTS*512)
            if err != nil {
                log.errorf("failed to allocate arena for grep panel: '%v'", err)
                return
            }
            mem.arena_init(&panel_state.query_arena, arena_bytes)

            panel_actions := core.new_input_actions(show_help = true)
            register_default_panel_actions(&panel_actions)
            core.register_ctrl_key_action(&panel.input_map.mode[.Normal], .W, panel_actions, "Panel Navigation")

            core.register_key_action(&panel.input_map.mode[.Normal], .ENTER, proc(state: ^core.State, user_data: rawptr) {
                this_panel := transmute(^core.Panel)user_data
                panel_state := transmute(^GrepPanel)this_panel.state

                if panel_state.query_results != nil {
                    selected_result := &panel_state.query_results[panel_state.selected_result]

                    core.open_buffer_file(state, selected_result.file_path, selected_result.line, selected_result.col)
                    close(state, this_panel.id)
                }

            }, "Open File");
            core.register_key_action(&panel.input_map.mode[.Normal], .I, proc(state: ^core.State, user_data: rawptr) {
                state.mode = .Insert;
                sdl2.StartTextInput();
            }, "enter insert mode");
            core.register_key_action(&panel.input_map.mode[.Normal], .K, proc(state: ^core.State, user_data: rawptr) {
                this_panel := transmute(^core.Panel)user_data
                panel_state := transmute(^GrepPanel)this_panel.state

                if panel_state.selected_result > 0 {
                    panel_state.selected_result -= 1
                }

                core.update_glyph_buffer_from_bytes(
                    &panel_state.glyphs,
                    transmute([]u8)panel_state.query_results[panel_state.selected_result].file_context,
                    panel_state.query_results[panel_state.selected_result].line,
                )

            }, "move selection up");
            core.register_key_action(&panel.input_map.mode[.Normal], .J, proc(state: ^core.State, user_data: rawptr) {
                this_panel := transmute(^core.Panel)user_data
                panel_state := transmute(^GrepPanel)this_panel.state

                if panel_state.selected_result < len(panel_state.query_results)-1 {
                    panel_state.selected_result += 1
                }

                core.update_glyph_buffer_from_bytes(
                    &panel_state.glyphs,
                    transmute([]u8)panel_state.query_results[panel_state.selected_result].file_context,
                    panel_state.query_results[panel_state.selected_result].line,
                )

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
            panel_state := transmute(^GrepPanel)panel.state

            return &panel_state.buffer, true
        },
        on_buffer_input = proc(panel: ^core.Panel, state: ^core.State) {
            panel_state := transmute(^GrepPanel)panel.state
            run_query(panel_state, &panel_state.buffer, state.directory)
        },
        render = proc(panel: ^core.Panel, state: ^core.State) -> (ok: bool) {
            context.allocator = panel.allocator

            panel_state := transmute(^GrepPanel)panel.state
            pop_job_results(panel_state)

            s := transmute(^ui.State)state.ui

            ListState :: struct {
                core_state: ^core.State,
                panel_state: ^GrepPanel,
            }
            list_state := ListState {
                core_state = state,
                panel_state = panel_state
            }

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
                                dir = .LeftToRight,
                                kind = {ui.Grow{}, ui.Grow{}}
                            },
                            style = {
                                border = {.Right},
                                border_color = .Background4
                            }
                        )
                        {
                            ui.list(
                                GrepQueryResult,
                                s,
                                panel_state.query_results,
                                &list_state, &panel_state.selected_result, &panel_state.results_start, 
                                proc(s: ^ui.State, item: rawptr, state: rawptr) {
                                    result := transmute(^GrepQueryResult)item
                                    list_state := transmute(^ListState)state
                                    
                                    ui.left_to_right(s)
                                    {
                                       ui.open_element(s, fmt.tprintf("%v:%v: ", result.line, result.col), { kind = {ui.Exact(list_state.core_state.source_font_width*10), ui.Fit{} }})
                                       ui.close_element(s)
                                       
                                       if len(result.file_path) > 0 {
                                            ui.open_element(s, result.file_path[len(list_state.core_state.directory):], { kind = {ui.Grow{}, ui.Fit{}} })
                                            ui.close_element(s)
                                        } else {
                                            ui.open_element(s, "BAD FILE DIRECTORY", {}, style = { background_color = .BrightRed })
                                            ui.close_element(s)
                                        } 
                                    }
                                    ui.close_element(s)
                                }
                            )
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
    }
}

foreign import grep_lib "system:grep_panel"
@(default_calling_convention = "c")
foreign grep_lib {
    grep :: proc (pattern: cstring, directory: cstring) -> RS_GrepResults ---
    grep_buffer :: proc (pattern: cstring, it: ^core.FileBufferIter, func: proc "c" (it: ^core.FileBufferIter) -> core.FileBufferIterResult) -> RS_GrepResults ---
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
rs_grep_as_results :: proc(results: ^RS_GrepResults, allocator := context.allocator) -> []GrepQueryResult {
    context.allocator = allocator

    max_results := min(results.len, MAX_GREP_RESULTS)

    query_results := make([]GrepQueryResult, max_results)

    for i in 0..<len(query_results) {
        r := results.results[i]

        query_results[i] = GrepQueryResult {
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


