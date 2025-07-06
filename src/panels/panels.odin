package panels

import "base:runtime"
import "core:path/filepath"
import "core:fmt"

import "vendor:sdl2"

import "../core"
import "../util"
import "../ui"

render_file_buffer :: proc(state: ^core.State, s: ^ui.State, buffer: ^core.FileBuffer) {
    draw_func := proc(state: ^core.State, e: ui.UI_Element, user_data: rawptr) {
        buffer := transmute(^core.FileBuffer)user_data;
        if buffer != nil {
            buffer.glyph_buffer_width = e.layout.size.x / state.source_font_width;
            buffer.glyph_buffer_height = e.layout.size.y / state.source_font_height + 1;

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
        }
        ui.close_element(s)
    }
    ui.close_element(s)
}

render_raw_buffer :: proc(state: ^core.State, s: ^ui.State, buffer: ^core.FileBuffer) {
    draw_func := proc(state: ^core.State, e: ui.UI_Element, user_data: rawptr) {
        buffer := transmute(^core.FileBuffer)user_data;
        if buffer != nil {
            buffer.glyph_buffer_width = e.layout.size.x / state.source_font_width;
            buffer.glyph_buffer_height = e.layout.size.y / state.source_font_height + 1;

            core.draw_file_buffer(state, buffer, e.layout.pos.x, e.layout.pos.y, false);
        }
    };

    ui.open_element(s, ui.UI_Element_Kind_Custom{fn = draw_func, user_data = transmute(rawptr)buffer}, {
        kind = {ui.Grow{}, ui.Grow{}}
    })
    ui.close_element(s)
    
}

make_file_buffer_panel :: proc(buffer_index: int) -> core.Panel {
    return core.Panel {
        panel_state = core.FileBufferPanel { buffer_index = buffer_index },
        // TODO: move the input registration from main.odin to here
        input_map = core.new_input_map(),
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
    input_map := core.new_input_map()
    grep_input_buffer := core.new_virtual_file_buffer(context.allocator)
    runtime.append(&state.buffers, grep_input_buffer)

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
            }
        }
    }, "move selection down");

    core.register_key_action(&input_map.mode[.Insert], .ESCAPE, proc(state: ^core.State) {
        state.mode = .Normal;
        sdl2.StopTextInput();
    }, "exit insert mode");
    core.register_key_action(&input_map.mode[.Insert], .ENTER, proc(state: ^core.State) {
        state.mode = .Normal;
        sdl2.StopTextInput();
    }, "search");

    results := make([]core.GrepQueryResult, 4)
    results[0] = core.GrepQueryResult {
        file_path = "src/main.odin"
    }
    results[1] = core.GrepQueryResult {
        file_path = "src/core/core.odin"
    }
    results[2] = core.GrepQueryResult {
        file_path = "src/panels/panels.odin"
    }
    results[3] = core.GrepQueryResult {
        file_path = "src/core/gfx.odin"
    }
    
    return core.Panel {
        panel_state = core.GrepPanel {
            buffer = len(state.buffers)-1,
            query_results = results,
        },
        input_map = input_map,
        buffer_proc = proc(state: ^core.State, panel_state: ^core.PanelState) -> (buffer: ^core.FileBuffer, ok: bool) {
            panel_state := panel_state.(core.GrepPanel) or_return;

            return &state.buffers[panel_state.buffer], true
        },
        render_proc = proc(state: ^core.State, panel_state: ^core.PanelState) -> (ok: bool) {
            panel_state := panel_state.(core.GrepPanel) or_return;

            s := transmute(^ui.State)state.ui
            ui.open_element(s, nil, {
                dir = .TopToBottom,
                kind = {ui.Grow{}, ui.Grow{}}
            })
            {
                defer ui.close_element(s)

                for result, i in panel_state.query_results {
                    // TODO: when styling is implemented, make this look better
                    if panel_state.selected_result == i {
                        ui.open_element(s, fmt.tprintf("%s <--", result.file_path), {})
                        ui.close_element(s)
                    } else {
                        ui.open_element(s, result.file_path, {})
                        ui.close_element(s)
                    }
                }

                ui.open_element(s, nil, {
                    kind = {ui.Grow{}, ui.Exact(state.source_font_height)}
                })
                { 
                    defer ui.close_element(s)

                    render_raw_buffer(state, s, &state.buffers[panel_state.buffer])
                }
            }

            return true
        }
    }
}