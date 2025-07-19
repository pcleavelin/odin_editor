package panels

import "base:runtime"
import "core:log"
import "core:fmt"
import "core:path/filepath"

import "vendor:sdl2"

import ts "../tree_sitter"
import "../core"
import "../ui"

make_file_buffer_panel :: proc(file_path: string, line: int = 0, col: int = 0) -> core.Panel {
    return core.Panel {
        type = core.FileBufferPanel {
            file_path = file_path,
            line = line,
            col = col,
        },
        drop = proc(panel: ^core.Panel, state: ^core.State) {
            panel_state := &panel.type.(core.FileBufferPanel)

            ts.delete_state(&panel_state.buffer.tree)
        },
        create = proc(panel: ^core.Panel, state: ^core.State) {
            context.allocator = panel.allocator

            panel_state := &panel.type.(core.FileBufferPanel)
            panel.input_map = core.new_input_map()

            if len(panel_state.file_path) == 0 {
                panel_state.buffer = core.new_virtual_file_buffer(panel.allocator)
            } else {
                buffer, err := core.new_file_buffer(panel.allocator, panel_state.file_path, state.directory)
                if err.type != .None {
                    log.error("Failed to create file buffer:", err);
                    return;
                }
                panel_state.buffer = buffer

                buffer.history.cursor.line = panel_state.line
                buffer.history.cursor.col = panel_state.col
                buffer.top_line = buffer.history.cursor.line
                core.update_file_buffer_index_from_cursor(&buffer)
            }

            leader_actions := core.new_input_actions()
            register_default_leader_actions(&leader_actions);
            core.register_key_action(&panel.input_map.mode[.Normal], .SPACE, leader_actions, "leader commands");

            core.register_ctrl_key_action(&panel.input_map.mode[.Normal], .W, core.new_input_actions(), "Panel Navigation") 
            register_default_panel_actions(&(&panel.input_map.mode[.Normal].ctrl_key_actions[.W]).action.(core.InputActions))

            file_buffer_input_actions(&panel.input_map.mode[.Normal]);
            file_buffer_visual_actions(&panel.input_map.mode[.Visual]);
            file_buffer_text_input_actions(&panel.input_map.mode[.Normal]);
        },
        buffer = proc(panel: ^core.Panel, state: ^core.State) -> (buffer: ^core.FileBuffer, ok: bool) {
            panel_state := &panel.type.(core.FileBufferPanel)

            return &panel_state.buffer, true
        },
        render = proc(panel: ^core.Panel, state: ^core.State) -> (ok: bool) {
            panel_state := &panel.type.(core.FileBufferPanel)

            s := transmute(^ui.State)state.ui
            render_file_buffer(state, s, &panel_state.buffer)

            return true
        }
    }
}

open_file_buffer_in_new_panel :: proc(state: ^core.State, file_path: string, line, col: int) -> (panel_id: int, ok: bool) {
    if panel_id, ok := open(state, make_file_buffer_panel(file_path, line, col)); ok {
        return panel_id, true
    }

    return -1, false
}

render_file_buffer :: proc(state: ^core.State, s: ^ui.State, buffer: ^core.FileBuffer) {
    draw_func := proc(state: ^core.State, e: ui.UI_Element, user_data: rawptr) {
        buffer := transmute(^core.FileBuffer)user_data;
        if buffer != nil {
            buffer.glyphs.width = e.layout.size.x / state.source_font_width;
            buffer.glyphs.height = e.layout.size.y / state.source_font_height + 1;

            core.draw_file_buffer(state, buffer, e.layout.pos.x, e.layout.pos.y, e.layout.size.x, e.layout.size.y);
        }
    };

    relative_file_path, _ := filepath.rel(state.directory, buffer.file_path, context.temp_allocator)

    ui.open_element(s, nil,
        {
            dir = .TopToBottom,
            kind = {ui.Grow{}, ui.Grow{}},
        },
        style = {
            border = {.Left, .Right, .Top, .Bottom},
            border_color = .Background4,
            background_color = .Background1,
        }
    )
    {
        ui.open_element(s,
            ui.UI_Element_Kind_Custom{fn = draw_func, user_data = transmute(rawptr)buffer},
            {
                kind = {ui.Grow{}, ui.Grow{}}
            },
            style = {
                border = {.Left, .Right, .Top, .Bottom},
                border_color = .Background4,
                background_color = .Background1,
            }
        )
        ui.close_element(s)

        ui.open_element(s, nil, {
            kind = {ui.Grow{}, ui.Exact(state.source_font_height)}
            },
            style = {
                border = {.Left, .Right, .Top, .Bottom},
                border_color = .Background4,
            }
        )
        {
            ui.open_element(s, fmt.tprintf("%s", state.mode), {})
            ui.close_element(s)

            ui.open_element(s, nil, { kind = {ui.Grow{}, ui.Grow{}}})
            ui.close_element(s)

            it := core.new_file_buffer_iter_with_cursor(buffer, buffer.history.cursor)
            ui.open_element(
                s,
                fmt.tprintf(
                    "%v:%v - Slice %v:%v - Char: %v",
                    buffer.history.cursor.line + 1,
                    buffer.history.cursor.col + 1,
                    buffer.history.cursor.index.chunk_index,
                    buffer.history.cursor.index.char_index,
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

file_buffer_go_actions :: proc(input_map: ^core.InputActions) {
    core.register_key_action(input_map, .H, proc(state: ^core.State, user_data: rawptr) {
        buffer := &(&(transmute(^core.Panel)user_data).type.(core.FileBufferPanel)).buffer

        core.move_cursor_start_of_line(buffer);
        core.reset_input_map(state)
    }, "move to beginning of line");
    core.register_key_action(input_map, .L, proc(state: ^core.State, user_data: rawptr) {
        buffer := &(&(transmute(^core.Panel)user_data).type.(core.FileBufferPanel)).buffer

        core.move_cursor_end_of_line(buffer);
        core.reset_input_map(state)
    }, "move to end of line");
}

file_buffer_input_actions :: proc(input_map: ^core.InputActions) {
    // Cursor Movement
    {
        core.register_key_action(input_map, .W, proc(state: ^core.State, user_data: rawptr) {
            buffer := &(&(transmute(^core.Panel)user_data).type.(core.FileBufferPanel)).buffer

            core.move_cursor_forward_start_of_word(buffer);
        }, "move forward one word");
        core.register_key_action(input_map, .E, proc(state: ^core.State, user_data: rawptr) {
            buffer := &(&(transmute(^core.Panel)user_data).type.(core.FileBufferPanel)).buffer

            core.move_cursor_forward_end_of_word(buffer);
        }, "move forward to end of word");

        core.register_key_action(input_map, .B, proc(state: ^core.State, user_data: rawptr) {
            buffer := &(&(transmute(^core.Panel)user_data).type.(core.FileBufferPanel)).buffer

            core.move_cursor_backward_start_of_word(buffer);
        }, "move backward one word");

        core.register_key_action(input_map, .K, proc(state: ^core.State, user_data: rawptr) {
            buffer := &(&(transmute(^core.Panel)user_data).type.(core.FileBufferPanel)).buffer

            core.move_cursor_up(buffer);
        }, "move up one line");
        core.register_key_action(input_map, .J, proc(state: ^core.State, user_data: rawptr) {
            buffer := &(&(transmute(^core.Panel)user_data).type.(core.FileBufferPanel)).buffer

            core.move_cursor_down(buffer);
        }, "move down one line");
        core.register_key_action(input_map, .H, proc(state: ^core.State, user_data: rawptr) {
            buffer := &(&(transmute(^core.Panel)user_data).type.(core.FileBufferPanel)).buffer

            core.move_cursor_left(buffer);
        }, "move left one char");
        core.register_key_action(input_map, .L, proc(state: ^core.State, user_data: rawptr) {
            buffer := &(&(transmute(^core.Panel)user_data).type.(core.FileBufferPanel)).buffer

            core.move_cursor_right(buffer);
        }, "move right one char");

        core.register_ctrl_key_action(input_map, .U, proc(state: ^core.State, user_data: rawptr) {
            buffer := &(&(transmute(^core.Panel)user_data).type.(core.FileBufferPanel)).buffer

            core.scroll_file_buffer(buffer, .Up);
        }, "scroll buffer up");
        core.register_ctrl_key_action(input_map, .D, proc(state: ^core.State, user_data: rawptr) {
            buffer := &(&(transmute(^core.Panel)user_data).type.(core.FileBufferPanel)).buffer

            core.scroll_file_buffer(buffer, .Down);
        }, "scroll buffer up");
    }

    // Scale font size
    {
        core.register_ctrl_key_action(input_map, .MINUS, proc(state: ^core.State, user_data: rawptr) {
            if state.source_font_height > 16 {
                state.source_font_height -= 2;
                state.source_font_width = state.source_font_height / 2;

                state.font_atlas = core.gen_font_atlas(state, core.HardcodedFontPath);
            }
            log.debug(state.source_font_height);
        }, "increase font size");
        core.register_ctrl_key_action(input_map, .EQUAL, proc(state: ^core.State, user_data: rawptr) {
            state.source_font_height += 2;
            state.source_font_width = state.source_font_height / 2;

            state.font_atlas = core.gen_font_atlas(state, core.HardcodedFontPath);
        }, "decrease font size");
    }

    // Save file
    core.register_ctrl_key_action(input_map, .S, proc(state: ^core.State, user_data: rawptr) {
        buffer := &(&(transmute(^core.Panel)user_data).type.(core.FileBufferPanel)).buffer

        if err := core.save_buffer_to_disk(state, buffer); err != nil {
            log.errorf("failed to save buffer to disk: %v", err)
        }
    }, "Save file")

    core.register_key_action(input_map, .G, core.new_input_actions(), "Go commands");
    file_buffer_go_actions(&(&input_map.key_actions[.G]).action.(core.InputActions));

    core.register_key_action(input_map, .V, proc(state: ^core.State, user_data: rawptr) {
        buffer := &(&(transmute(^core.Panel)user_data).type.(core.FileBufferPanel)).buffer

        state.mode = .Visual;
        core.reset_input_map(state)

        buffer.selection = core.new_selection(buffer.history.cursor);
    }, "enter visual mode");

}

file_buffer_visual_actions :: proc(input_map: ^core.InputActions) {
    core.register_key_action(input_map, .ESCAPE, proc(state: ^core.State, user_data: rawptr) {
        buffer := &(&(transmute(^core.Panel)user_data).type.(core.FileBufferPanel)).buffer

        state.mode = .Normal;
        core.reset_input_map(state)

        buffer.selection = nil;
        core.update_file_buffer_scroll(buffer)
    }, "exit visual mode");

    // Cursor Movement
    {
        core.register_key_action(input_map, .W, proc(state: ^core.State, user_data: rawptr) {
            buffer := &(&(transmute(^core.Panel)user_data).type.(core.FileBufferPanel)).buffer

            sel_cur := &(buffer.selection.?);

            core.move_cursor_forward_start_of_word(buffer, cursor = &sel_cur.end);
        }, "move forward one word");
        core.register_key_action(input_map, .E, proc(state: ^core.State, user_data: rawptr) {
            buffer := &(&(transmute(^core.Panel)user_data).type.(core.FileBufferPanel)).buffer

            sel_cur := &(buffer.selection.?);

            core.move_cursor_forward_end_of_word(buffer, cursor = &sel_cur.end);
        }, "move forward to end of word");

        core.register_key_action(input_map, .B, proc(state: ^core.State, user_data: rawptr) {
            buffer := &(&(transmute(^core.Panel)user_data).type.(core.FileBufferPanel)).buffer

            sel_cur := &(buffer.selection.?);

            core.move_cursor_backward_start_of_word(buffer, cursor = &sel_cur.end);
        }, "move backward one word");

        core.register_key_action(input_map, .K, proc(state: ^core.State, user_data: rawptr) {
            buffer := &(&(transmute(^core.Panel)user_data).type.(core.FileBufferPanel)).buffer

            sel_cur := &(buffer.selection.?);

            core.move_cursor_up(buffer, cursor = &sel_cur.end);
        }, "move up one line");
        core.register_key_action(input_map, .J, proc(state: ^core.State, user_data: rawptr) {
            buffer := &(&(transmute(^core.Panel)user_data).type.(core.FileBufferPanel)).buffer

            sel_cur := &(buffer.selection.?);

            core.move_cursor_down(buffer, cursor = &sel_cur.end);
        }, "move down one line");
        core.register_key_action(input_map, .H, proc(state: ^core.State, user_data: rawptr) {
            buffer := &(&(transmute(^core.Panel)user_data).type.(core.FileBufferPanel)).buffer

            sel_cur := &(buffer.selection.?);

            core.move_cursor_left(buffer, cursor = &sel_cur.end);
        }, "move left one char");
        core.register_key_action(input_map, .L, proc(state: ^core.State, user_data: rawptr) {
            buffer := &(&(transmute(^core.Panel)user_data).type.(core.FileBufferPanel)).buffer

            sel_cur := &(buffer.selection.?);

            core.move_cursor_right(buffer, cursor = &sel_cur.end);
        }, "move right one char");

        core.register_ctrl_key_action(input_map, .U, proc(state: ^core.State, user_data: rawptr) {
            buffer := &(&(transmute(^core.Panel)user_data).type.(core.FileBufferPanel)).buffer

            sel_cur := &(buffer.selection.?);

            core.scroll_file_buffer(buffer, .Up, cursor = &sel_cur.end);
        }, "scroll buffer up");
        core.register_ctrl_key_action(input_map, .D, proc(state: ^core.State, user_data: rawptr) {
            buffer := &(&(transmute(^core.Panel)user_data).type.(core.FileBufferPanel)).buffer

            sel_cur := &(buffer.selection.?);

            core.scroll_file_buffer(buffer, .Down, cursor = &sel_cur.end);
        }, "scroll buffer up");
    }

    // Text Modification
    {
        core.register_key_action(input_map, .D, proc(state: ^core.State, user_data: rawptr) {
            buffer := &(&(transmute(^core.Panel)user_data).type.(core.FileBufferPanel)).buffer

            core.push_new_snapshot(&buffer.history)

            sel_cur := &(buffer.selection.?);

            core.delete_content(buffer, sel_cur);
            buffer.selection = nil;
            core.update_file_buffer_scroll(buffer)

            state.mode = .Normal
            core.reset_input_map(state)
        }, "delete selection");

        core.register_key_action(input_map, .C, proc(state: ^core.State, user_data: rawptr) {
            buffer := &(&(transmute(^core.Panel)user_data).type.(core.FileBufferPanel)).buffer

            core.push_new_snapshot(&buffer.history)

            sel_cur := &(buffer.selection.?);

            core.delete_content(buffer, sel_cur);
            buffer.selection = nil;
            core.update_file_buffer_scroll(buffer)

            state.mode = .Insert
            core.reset_input_map(state, core.Mode.Normal)
            sdl2.StartTextInput();
        }, "change selection");
    }

    // Copy-Paste
    {
        core.register_key_action(input_map, .Y, proc(state: ^core.State, user_data: rawptr) {
            buffer := &(&(transmute(^core.Panel)user_data).type.(core.FileBufferPanel)).buffer

            core.yank_selection(state, buffer)

            state.mode = .Normal;
            core.reset_input_map(state)

            buffer.selection = nil;
            core.update_file_buffer_scroll(buffer)
        }, "Yank Line");

        core.register_key_action(input_map, .P, proc(state: ^core.State, user_data: rawptr) {
            buffer := &(&(transmute(^core.Panel)user_data).type.(core.FileBufferPanel)).buffer

            core.push_new_snapshot(&buffer.history)

            if state.yank_register.whole_line {
                core.insert_content(buffer, []u8{'\n'});
                core.paste_register(state, state.yank_register, buffer)
                core.insert_content(buffer, []u8{'\n'});
            } else {
                core.paste_register(state, state.yank_register, buffer)
            }

            core.reset_input_map(state)
        }, "Paste");
    }
}

file_buffer_text_input_actions :: proc(input_map: ^core.InputActions) {
    core.register_key_action(input_map, .I, proc(state: ^core.State, user_data: rawptr) {
        buffer := &(&(transmute(^core.Panel)user_data).type.(core.FileBufferPanel)).buffer

        core.push_new_snapshot(&buffer.history)

        state.mode = .Insert;
        sdl2.StartTextInput();
    }, "enter insert mode");
    core.register_key_action(input_map, .A, proc(state: ^core.State, user_data: rawptr) {
        buffer := &(&(transmute(^core.Panel)user_data).type.(core.FileBufferPanel)).buffer

        core.push_new_snapshot(&buffer.history)

        core.move_cursor_right(buffer, false);
        state.mode = .Insert;
        sdl2.StartTextInput();
    }, "enter insert mode after character (append)");

    core.register_key_action(input_map, .U, proc(state: ^core.State, user_data: rawptr) {
        buffer := &(&(transmute(^core.Panel)user_data).type.(core.FileBufferPanel)).buffer

        core.pop_snapshot(&buffer.history, true)
    }, "Undo");

    core.register_ctrl_key_action(input_map, .R, proc(state: ^core.State, user_data: rawptr) {
        buffer := &(&(transmute(^core.Panel)user_data).type.(core.FileBufferPanel)).buffer

        core.recover_snapshot(&buffer.history)
    }, "Redo");

    // TODO: add shift+o to insert newline above current one

    core.register_key_action(input_map, .O, proc(state: ^core.State, user_data: rawptr) {
        buffer := &(&(transmute(^core.Panel)user_data).type.(core.FileBufferPanel)).buffer

        core.push_new_snapshot(&buffer.history)

        if buffer := buffer; buffer != nil {
            core.move_cursor_end_of_line(buffer, false);
            runtime.clear(&buffer.input_buffer)

            append(&buffer.input_buffer, '\n')

            state.mode = .Insert;

            sdl2.StartTextInput();
        }
    }, "insert mode on newline");

    // Copy-Paste
    {
        {
            yank_actions := core.new_input_actions()
            defer core.register_key_action(input_map, .Y, yank_actions)

            core.register_key_action(&yank_actions, .Y, proc(state: ^core.State, user_data: rawptr) {
                buffer := &(&(transmute(^core.Panel)user_data).type.(core.FileBufferPanel)).buffer

                core.yank_whole_line(state, buffer)

                core.reset_input_map(state)
            }, "Yank Line");
        }

        core.register_key_action(input_map, .P, proc(state: ^core.State, user_data: rawptr) {
            buffer := &(&(transmute(^core.Panel)user_data).type.(core.FileBufferPanel)).buffer

            core.push_new_snapshot(&buffer.history)

            if state.yank_register.whole_line {
                core.move_cursor_end_of_line(buffer, false);
                core.insert_content(buffer, []u8{'\n'});
                core.move_cursor_right(buffer, false);
            } else {
                core.move_cursor_right(buffer)
            }
            core.paste_register(state, state.yank_register, buffer)
            core.move_cursor_start_of_line(buffer)

            core.reset_input_map(state)
        }, "Paste");
    }

}