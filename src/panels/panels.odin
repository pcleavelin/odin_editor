package panels

import "core:path/filepath"
import "core:fmt"

import "../core"
import "../ui"

make_file_buffer_panel :: proc(buffer_index: int) -> core.Panel {
    return core.Panel {
        panel_state = core.FileBufferPanel { buffer_index = buffer_index },
        render_proc = proc(state: ^core.State, panel_state: ^core.PanelState) -> (ok: bool) {
            panel_state := panel_state.(core.FileBufferPanel) or_return;

            draw_func := proc(state: ^core.State, e: ui.UI_Element, user_data: rawptr) {
                buffer := transmute(^core.FileBuffer)user_data;
                if buffer != nil {
                    buffer.glyph_buffer_width = e.layout.size.x / state.source_font_width;
                    buffer.glyph_buffer_height = e.layout.size.y / state.source_font_height + 1;

                    core.draw_file_buffer(state, buffer, e.layout.pos.x, e.layout.pos.y);
                }
            };

            s := transmute(^ui.State)state.ui
            buffer := &state.buffers[panel_state.buffer_index]
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

            return true
        }
    }
}
