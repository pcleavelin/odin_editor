package input

import "base:runtime"
import "core:log"

import "vendor:sdl2"

import "../core"
import "../util"

State :: core.State

register_default_go_actions :: proc(input_map: ^core.InputActions) {
    core.register_key_action(input_map, .H, proc(state: ^State, user_data: rawptr) {
        buffer := transmute(^core.FileBuffer)user_data

        core.move_cursor_start_of_line(buffer);
        core.reset_input_map(state)
    }, "move to beginning of line");
    core.register_key_action(input_map, .L, proc(state: ^State, user_data: rawptr) {
        buffer := transmute(^core.FileBuffer)user_data

        core.move_cursor_end_of_line(buffer);
        core.reset_input_map(state)
    }, "move to end of line");
}

register_default_input_actions :: proc(input_map: ^core.InputActions) {
    // Cursor Movement
    {
        core.register_key_action(input_map, .W, proc(state: ^State, user_data: rawptr) {
            buffer := transmute(^core.FileBuffer)user_data

            core.move_cursor_forward_start_of_word(buffer);
        }, "move forward one word");
        core.register_key_action(input_map, .E, proc(state: ^State, user_data: rawptr) {
            buffer := transmute(^core.FileBuffer)user_data

            core.move_cursor_forward_end_of_word(buffer);
        }, "move forward to end of word");

        core.register_key_action(input_map, .B, proc(state: ^State, user_data: rawptr) {
            buffer := transmute(^core.FileBuffer)user_data

            core.move_cursor_backward_start_of_word(buffer);
        }, "move backward one word");

        core.register_key_action(input_map, .K, proc(state: ^State, user_data: rawptr) {
            buffer := transmute(^core.FileBuffer)user_data

            core.move_cursor_up(buffer);
        }, "move up one line");
        core.register_key_action(input_map, .J, proc(state: ^State, user_data: rawptr) {
            buffer := transmute(^core.FileBuffer)user_data

            core.move_cursor_down(buffer);
        }, "move down one line");
        core.register_key_action(input_map, .H, proc(state: ^State, user_data: rawptr) {
            buffer := transmute(^core.FileBuffer)user_data

            core.move_cursor_left(buffer);
        }, "move left one char");
        core.register_key_action(input_map, .L, proc(state: ^State, user_data: rawptr) {
            buffer := transmute(^core.FileBuffer)user_data

            core.move_cursor_right(buffer);
        }, "move right one char");

        core.register_ctrl_key_action(input_map, .U, proc(state: ^State, user_data: rawptr) {
            buffer := transmute(^core.FileBuffer)user_data

            core.scroll_file_buffer(buffer, .Up);
        }, "scroll buffer up");
        core.register_ctrl_key_action(input_map, .D, proc(state: ^State, user_data: rawptr) {
            buffer := transmute(^core.FileBuffer)user_data

            core.scroll_file_buffer(buffer, .Down);
        }, "scroll buffer up");
    }

    // Scale font size
    {
        core.register_ctrl_key_action(input_map, .MINUS, proc(state: ^State, user_data: rawptr) {
            if state.source_font_height > 16 {
                state.source_font_height -= 2;
                state.source_font_width = state.source_font_height / 2;

                state.font_atlas = core.gen_font_atlas(state, core.HardcodedFontPath);
            }
            log.debug(state.source_font_height);
        }, "increase font size");
        core.register_ctrl_key_action(input_map, .EQUAL, proc(state: ^State, user_data: rawptr) {
            state.source_font_height += 2;
            state.source_font_width = state.source_font_height / 2;

            state.font_atlas = core.gen_font_atlas(state, core.HardcodedFontPath);
        }, "decrease font size");
    }

    // Save file
    core.register_ctrl_key_action(input_map, .S, proc(state: ^State, user_data: rawptr) {
        buffer := transmute(^core.FileBuffer)user_data

        if err := core.save_buffer_to_disk(state, buffer); err != nil {
            log.errorf("failed to save buffer to disk: %v", err)
        }
    }, "Save file")

    core.register_key_action(input_map, .G, core.new_input_actions(), "Go commands");
    register_default_go_actions(&(&input_map.key_actions[.G]).action.(core.InputActions));

    core.register_key_action(input_map, .V, proc(state: ^State, user_data: rawptr) {
        buffer := transmute(^core.FileBuffer)user_data

        state.mode = .Visual;
        core.reset_input_map(state)

        buffer.selection = core.new_selection(buffer.history.cursor);
    }, "enter visual mode");

}

register_default_visual_actions :: proc(input_map: ^core.InputActions) {
    core.register_key_action(input_map, .ESCAPE, proc(state: ^State, user_data: rawptr) {
        buffer := transmute(^core.FileBuffer)user_data

        state.mode = .Normal;
        core.reset_input_map(state)

        buffer.selection = nil;
        core.update_file_buffer_scroll(buffer)
    }, "exit visual mode");

    // Cursor Movement
    {
        core.register_key_action(input_map, .W, proc(state: ^State, user_data: rawptr) {
            buffer := transmute(^core.FileBuffer)user_data

            sel_cur := &(buffer.selection.?);

            core.move_cursor_forward_start_of_word(buffer, cursor = &sel_cur.end);
        }, "move forward one word");
        core.register_key_action(input_map, .E, proc(state: ^State, user_data: rawptr) {
            buffer := transmute(^core.FileBuffer)user_data

            sel_cur := &(buffer.selection.?);

            core.move_cursor_forward_end_of_word(buffer, cursor = &sel_cur.end);
        }, "move forward to end of word");

        core.register_key_action(input_map, .B, proc(state: ^State, user_data: rawptr) {
            buffer := transmute(^core.FileBuffer)user_data

            sel_cur := &(buffer.selection.?);

            core.move_cursor_backward_start_of_word(buffer, cursor = &sel_cur.end);
        }, "move backward one word");

        core.register_key_action(input_map, .K, proc(state: ^State, user_data: rawptr) {
            buffer := transmute(^core.FileBuffer)user_data

            sel_cur := &(buffer.selection.?);

            core.move_cursor_up(buffer, cursor = &sel_cur.end);
        }, "move up one line");
        core.register_key_action(input_map, .J, proc(state: ^State, user_data: rawptr) {
            buffer := transmute(^core.FileBuffer)user_data

            sel_cur := &(buffer.selection.?);

            core.move_cursor_down(buffer, cursor = &sel_cur.end);
        }, "move down one line");
        core.register_key_action(input_map, .H, proc(state: ^State, user_data: rawptr) {
            buffer := transmute(^core.FileBuffer)user_data

            sel_cur := &(buffer.selection.?);

            core.move_cursor_left(buffer, cursor = &sel_cur.end);
        }, "move left one char");
        core.register_key_action(input_map, .L, proc(state: ^State, user_data: rawptr) {
            buffer := transmute(^core.FileBuffer)user_data

            sel_cur := &(buffer.selection.?);

            core.move_cursor_right(buffer, cursor = &sel_cur.end);
        }, "move right one char");

        core.register_ctrl_key_action(input_map, .U, proc(state: ^State, user_data: rawptr) {
            buffer := transmute(^core.FileBuffer)user_data

            sel_cur := &(buffer.selection.?);

            core.scroll_file_buffer(buffer, .Up, cursor = &sel_cur.end);
        }, "scroll buffer up");
        core.register_ctrl_key_action(input_map, .D, proc(state: ^State, user_data: rawptr) {
            buffer := transmute(^core.FileBuffer)user_data

            sel_cur := &(buffer.selection.?);

            core.scroll_file_buffer(buffer, .Down, cursor = &sel_cur.end);
        }, "scroll buffer up");
    }

    // Text Modification
    {
        core.register_key_action(input_map, .D, proc(state: ^State, user_data: rawptr) {
            buffer := transmute(^core.FileBuffer)user_data

            core.push_new_snapshot(&buffer.history)

            sel_cur := &(buffer.selection.?);

            core.delete_content(buffer, sel_cur);
            buffer.selection = nil;
            core.update_file_buffer_scroll(buffer)

            state.mode = .Normal
            core.reset_input_map(state)
        }, "delete selection");

        core.register_key_action(input_map, .C, proc(state: ^State, user_data: rawptr) {
            buffer := transmute(^core.FileBuffer)user_data

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
        core.register_key_action(input_map, .Y, proc(state: ^State, user_data: rawptr) {
            buffer := transmute(^core.FileBuffer)user_data

            core.yank_selection(state, buffer)

            state.mode = .Normal;
            core.reset_input_map(state)

            buffer.selection = nil;
            core.update_file_buffer_scroll(buffer)
        }, "Yank Line");

        core.register_key_action(input_map, .P, proc(state: ^State, user_data: rawptr) {
            buffer := transmute(^core.FileBuffer)user_data

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

register_default_text_input_actions :: proc(input_map: ^core.InputActions) {
    core.register_key_action(input_map, .I, proc(state: ^State, user_data: rawptr) {
        buffer := transmute(^core.FileBuffer)user_data

        core.push_new_snapshot(&buffer.history)

        state.mode = .Insert;
        sdl2.StartTextInput();
    }, "enter insert mode");
    core.register_key_action(input_map, .A, proc(state: ^State, user_data: rawptr) {
        buffer := transmute(^core.FileBuffer)user_data

        core.push_new_snapshot(&buffer.history)

        core.move_cursor_right(buffer, false);
        state.mode = .Insert;
        sdl2.StartTextInput();
    }, "enter insert mode after character (append)");

    core.register_key_action(input_map, .U, proc(state: ^State, user_data: rawptr) {
        buffer := transmute(^core.FileBuffer)user_data

        core.pop_snapshot(&buffer.history, true)
    }, "Undo");

    core.register_ctrl_key_action(input_map, .R, proc(state: ^State, user_data: rawptr) {
        buffer := transmute(^core.FileBuffer)user_data

        core.recover_snapshot(&buffer.history)
    }, "Redo");

    // TODO: add shift+o to insert newline above current one

    core.register_key_action(input_map, .O, proc(state: ^State, user_data: rawptr) {
        buffer := transmute(^core.FileBuffer)user_data

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

            core.register_key_action(&yank_actions, .Y, proc(state: ^State, user_data: rawptr) {
                buffer := transmute(^core.FileBuffer)user_data

                core.yank_whole_line(state, buffer)

                core.reset_input_map(state)
            }, "Yank Line");
        }

        core.register_key_action(input_map, .P, proc(state: ^State, user_data: rawptr) {
            buffer := transmute(^core.FileBuffer)user_data

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
