package input

import "base:runtime"
import "core:log"

import "vendor:sdl2"

import "../core"
import "../util"

State :: core.State

register_default_go_actions :: proc(input_map: ^core.InputActions) {
    core.register_key_action(input_map, .H, proc(state: ^State) {
        core.move_cursor_start_of_line(core.current_buffer(state));
        core.reset_input_map(state)
    }, "move to beginning of line");
    core.register_key_action(input_map, .L, proc(state: ^State) {
        core.move_cursor_end_of_line(core.current_buffer(state));
        core.reset_input_map(state)
    }, "move to end of line");
}

register_default_input_actions :: proc(input_map: ^core.InputActions) {
    // Cursor Movement
    {
        core.register_key_action(input_map, .W, proc(state: ^State) {
            core.move_cursor_forward_start_of_word(core.current_buffer(state));
        }, "move forward one word");
        core.register_key_action(input_map, .E, proc(state: ^State) {
            core.move_cursor_forward_end_of_word(core.current_buffer(state));
        }, "move forward to end of word");

        core.register_key_action(input_map, .B, proc(state: ^State) {
            core.move_cursor_backward_start_of_word(core.current_buffer(state));
        }, "move backward one word");

        core.register_key_action(input_map, .K, proc(state: ^State) {
            core.move_cursor_up(core.current_buffer(state));
        }, "move up one line");
        core.register_key_action(input_map, .J, proc(state: ^State) {
            core.move_cursor_down(core.current_buffer(state));
        }, "move down one line");
        core.register_key_action(input_map, .H, proc(state: ^State) {
            core.move_cursor_left(core.current_buffer(state));
        }, "move left one char");
        core.register_key_action(input_map, .L, proc(state: ^State) {
            core.move_cursor_right(core.current_buffer(state));
        }, "move right one char");

        core.register_ctrl_key_action(input_map, .U, proc(state: ^State) {
            core.scroll_file_buffer(core.current_buffer(state), .Up);
        }, "scroll buffer up");
        core.register_ctrl_key_action(input_map, .D, proc(state: ^State) {
            core.scroll_file_buffer(core.current_buffer(state), .Down);
        }, "scroll buffer up");
    }

    // Scale font size
    {
        core.register_ctrl_key_action(input_map, .MINUS, proc(state: ^State) {
            if state.source_font_height > 16 {
                state.source_font_height -= 2;
                state.source_font_width = state.source_font_height / 2;

                state.font_atlas = core.gen_font_atlas(state, core.HardcodedFontPath);
            }
            log.debug(state.source_font_height);
        }, "increase font size");
        core.register_ctrl_key_action(input_map, .EQUAL, proc(state: ^State) {
            state.source_font_height += 2;
            state.source_font_width = state.source_font_height / 2;

            state.font_atlas = core.gen_font_atlas(state, core.HardcodedFontPath);
        }, "decrease font size");
    }

    // Save file
    core.register_ctrl_key_action(input_map, .S, proc(state: ^State) {
        if err := core.save_buffer_to_disk(state, core.current_buffer(state)); err != nil {
            log.errorf("failed to save buffer to disk: %v", err)
        }
    }, "Save file")

    core.register_key_action(input_map, .G, core.new_input_actions(), "Go commands");
    register_default_go_actions(&(&input_map.key_actions[.G]).action.(core.InputActions));

    core.register_key_action(input_map, .V, proc(state: ^State) {
        state.mode = .Visual;
        core.reset_input_map(state)

        core.current_buffer(state).selection = core.new_selection(core.current_buffer(state).history.cursor);
    }, "enter visual mode");

}

register_default_visual_actions :: proc(input_map: ^core.InputActions) {
    core.register_key_action(input_map, .ESCAPE, proc(state: ^State) {
        state.mode = .Normal;
        core.reset_input_map(state)

        core.current_buffer(state).selection = nil;
        core.update_file_buffer_scroll(core.current_buffer(state))
    }, "exit visual mode");

    // Cursor Movement
    {
        core.register_key_action(input_map, .W, proc(state: ^State) {
            sel_cur := &(core.current_buffer(state).selection.?);

            core.move_cursor_forward_start_of_word(core.current_buffer(state), cursor = &sel_cur.end);
        }, "move forward one word");
        core.register_key_action(input_map, .E, proc(state: ^State) {
            sel_cur := &(core.current_buffer(state).selection.?);

            core.move_cursor_forward_end_of_word(core.current_buffer(state), cursor = &sel_cur.end);
        }, "move forward to end of word");

        core.register_key_action(input_map, .B, proc(state: ^State) {
            sel_cur := &(core.current_buffer(state).selection.?);

            core.move_cursor_backward_start_of_word(core.current_buffer(state), cursor = &sel_cur.end);
        }, "move backward one word");

        core.register_key_action(input_map, .K, proc(state: ^State) {
            sel_cur := &(core.current_buffer(state).selection.?);

            core.move_cursor_up(core.current_buffer(state), cursor = &sel_cur.end);
        }, "move up one line");
        core.register_key_action(input_map, .J, proc(state: ^State) {
            sel_cur := &(core.current_buffer(state).selection.?);

            core.move_cursor_down(core.current_buffer(state), cursor = &sel_cur.end);
        }, "move down one line");
        core.register_key_action(input_map, .H, proc(state: ^State) {
            sel_cur := &(core.current_buffer(state).selection.?);

            core.move_cursor_left(core.current_buffer(state), cursor = &sel_cur.end);
        }, "move left one char");
        core.register_key_action(input_map, .L, proc(state: ^State) {
            sel_cur := &(core.current_buffer(state).selection.?);

            core.move_cursor_right(core.current_buffer(state), cursor = &sel_cur.end);
        }, "move right one char");

        core.register_ctrl_key_action(input_map, .U, proc(state: ^State) {
            sel_cur := &(core.current_buffer(state).selection.?);

            core.scroll_file_buffer(core.current_buffer(state), .Up, cursor = &sel_cur.end);
        }, "scroll buffer up");
        core.register_ctrl_key_action(input_map, .D, proc(state: ^State) {
            sel_cur := &(core.current_buffer(state).selection.?);

            core.scroll_file_buffer(core.current_buffer(state), .Down, cursor = &sel_cur.end);
        }, "scroll buffer up");
    }

    // Text Modification
    {
        core.register_key_action(input_map, .D, proc(state: ^State) {
            core.push_new_snapshot(&core.current_buffer(state).history)

            sel_cur := &(core.current_buffer(state).selection.?);

            core.delete_content(core.current_buffer(state), sel_cur);
            core.current_buffer(state).selection = nil;
            core.update_file_buffer_scroll(core.current_buffer(state))

            state.mode = .Normal
            core.reset_input_map(state)
        }, "delete selection");

        core.register_key_action(input_map, .C, proc(state: ^State) {
            core.push_new_snapshot(&core.current_buffer(state).history)

            sel_cur := &(core.current_buffer(state).selection.?);

            core.delete_content(core.current_buffer(state), sel_cur);
            core.current_buffer(state).selection = nil;
            core.update_file_buffer_scroll(core.current_buffer(state))

            state.mode = .Insert
            core.reset_input_map(state, core.Mode.Normal)
            sdl2.StartTextInput();
        }, "change selection");
    }

    // Copy-Paste
    {
        core.register_key_action(input_map, .Y, proc(state: ^State) {
            core.yank_selection(state)

            state.mode = .Normal;
            core.reset_input_map(state)

            core.current_buffer(state).selection = nil;
            core.update_file_buffer_scroll(core.current_buffer(state))
        }, "Yank Line");

        core.register_key_action(input_map, .P, proc(state: ^State) {
            core.push_new_snapshot(&core.current_buffer(state).history)

            if state.yank_register.whole_line {
                core.insert_content(core.current_buffer(state), []u8{'\n'});
                core.paste_register(state, state.yank_register)
                core.insert_content(core.current_buffer(state), []u8{'\n'});
            } else {
                core.paste_register(state, state.yank_register)
            }

            core.reset_input_map(state)
        }, "Paste");
    }
}

register_default_text_input_actions :: proc(input_map: ^core.InputActions) {
    core.register_key_action(input_map, .I, proc(state: ^State) {
        core.push_new_snapshot(&core.current_buffer(state).history)

        state.mode = .Insert;
        sdl2.StartTextInput();
    }, "enter insert mode");
    core.register_key_action(input_map, .A, proc(state: ^State) {
        core.push_new_snapshot(&core.current_buffer(state).history)

        core.move_cursor_right(core.current_buffer(state), false);
        state.mode = .Insert;
        sdl2.StartTextInput();
    }, "enter insert mode after character (append)");

    core.register_key_action(input_map, .U, proc(state: ^State) {
        core.pop_snapshot(&core.current_buffer(state).history, true)
    }, "Undo");

    core.register_ctrl_key_action(input_map, .R, proc(state: ^State) {
        core.recover_snapshot(&core.current_buffer(state).history)
    }, "Redo");

    // TODO: add shift+o to insert newline above current one

    core.register_key_action(input_map, .O, proc(state: ^State) {
        core.push_new_snapshot(&core.current_buffer(state).history)

        if buffer := core.current_buffer(state); buffer != nil {
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

            core.register_key_action(&yank_actions, .Y, proc(state: ^State) {
                core.yank_whole_line(state)

                core.reset_input_map(state)
            }, "Yank Line");
        }

        core.register_key_action(input_map, .P, proc(state: ^State) {
            core.push_new_snapshot(&core.current_buffer(state).history)

            if state.yank_register.whole_line {
                core.move_cursor_end_of_line(core.current_buffer(state), false);
                core.insert_content(core.current_buffer(state), []u8{'\n'});
                core.move_cursor_right(core.current_buffer(state), false);
            } else {
                core.move_cursor_right(core.current_buffer(state))
            }
            core.paste_register(state, state.yank_register)
            core.move_cursor_start_of_line(core.current_buffer(state))

            core.reset_input_map(state)
        }, "Paste");
    }

}
