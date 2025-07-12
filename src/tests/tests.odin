package tests

import "base:runtime"
import "core:testing"
import "core:fmt"
import "core:mem"
import "core:log"

import "../core"
import "../panels"
import "../util"

new_test_editor :: proc() -> core.State {
    state := core.State {
        ctx = context,
        screen_width = 640,
        screen_height = 480,
        source_font_width = 8,
        source_font_height = 16,

        panels = util.make_static_list(core.Panel, 128),

        directory = "test_directory",
    };

    return state
}

buffer_to_string :: proc(buffer: ^core.FileBuffer) -> string {
    if buffer == nil {
        log.error("nil buffer")
    }

    length := 0
    for chunk in buffer.piece_table.chunks {
        length += len(chunk)
    }

    buffer_contents := make([]u8, length)

    offset := 0
    for chunk in buffer.piece_table.chunks {
        for c in chunk {
            buffer_contents[offset] = c
            offset += 1
        }
    }

    return string(buffer_contents)
}

ArtificialInput :: union {
    ArtificialKey,
    ArtificialTextInput,
}

ArtificialKey :: struct {
    is_down: bool,
    key: core.Key,
}

ArtificialTextInput :: struct {
    text: string,
}

press_key :: proc(key: core.Key) -> ArtificialKey {
    return ArtificialKey {
        is_down = true,
        key = key
    }
}

release_key :: proc(key: core.Key) -> ArtificialKey {
    return ArtificialKey {
        is_down = false,
        key = key
    }
}

input_text :: proc(text: string) -> ArtificialTextInput {
    return ArtificialTextInput {
        text = text
    }
}

setup_empty_buffer :: proc(state: ^core.State) {
    buffer := core.new_virtual_file_buffer(context.allocator);
    panels.open(state, panels.make_file_buffer_panel(len(state.buffers)))
    runtime.append(&state.buffers, buffer);

    core.reset_input_map(state)
}

run_inputs :: proc(state: ^core.State, inputs: []ArtificialInput) {
    is_ctrl_pressed := false

    for input in inputs {
        run_editor_frame(state, input, &is_ctrl_pressed)
    }
}

run_input_multiple :: proc(state: ^core.State, input: ArtificialInput, amount: int) {
    is_ctrl_pressed := false

    for _ in 0..<amount {
        run_editor_frame(state, input, &is_ctrl_pressed)
    }
}

run_text_insertion :: proc(state: ^core.State, text: string) {
    is_ctrl_pressed := false

    inputs := []ArtificialInput {
        press_key(.I),
        input_text(text),
        press_key(.ESCAPE),
    }

    for input in inputs {
        run_editor_frame(state, input, &is_ctrl_pressed)
    }
}

expect_line_col :: proc(t: ^testing.T, cursor: core.Cursor, line, col: int) {
    testing.expect_value(t, cursor.line, line)
    testing.expect_value(t, cursor.col, col)
}

expect_cursor_index :: proc(t: ^testing.T, cursor: core.Cursor, chunk_index, char_index: int) {
    testing.expect_value(t, cursor.index.chunk_index, chunk_index)
    testing.expect_value(t, cursor.index.char_index, char_index)
}

@(test)
insert_from_empty_no_newlines :: proc(t: ^testing.T) {
    e := new_test_editor()
    setup_empty_buffer(&e)

    buffer := &e.buffers[0]

    inputted_text := "Hello, world!"
    expected_text := fmt.aprintf("%v\n", inputted_text)
    run_text_insertion(&e, inputted_text)

    expect_line_col(t, buffer.cursor, 0, 12)
    expect_cursor_index(t, buffer.cursor, 0, 12)

    contents := buffer_to_string(core.current_buffer(&e))
    testing.expectf(t, contents == expected_text, "got '%v', expected '%v'", contents, expected_text)
}

@(test)
insert_from_empty_with_newline :: proc(t: ^testing.T) {
    e := new_test_editor()
    setup_empty_buffer(&e)

    buffer := &e.buffers[0]

    inputted_text := "Hello, world!\nThis is a new line"
    expected_text := fmt.aprintf("%v\n", inputted_text)
    run_text_insertion(&e, inputted_text)

    expect_line_col(t, buffer.cursor, 1, 17)
    expect_cursor_index(t, buffer.cursor, 0, 31)

    contents := buffer_to_string(core.current_buffer(&e))
    testing.expectf(t, contents == expected_text, "got '%v', expected '%v'", contents, expected_text)
}

@(test)
insert_in_between_text :: proc(t: ^testing.T) {
    e := new_test_editor()
    setup_empty_buffer(&e)

    buffer := &e.buffers[0]

    inputted_text := "Hello, world!"
    expected_text := "Hello, beautiful world!\n"

    run_text_insertion(&e, inputted_text)

    // Move the cursor to the space in between 'Hello,' and 'world!'
    run_input_multiple(&e, press_key(.H), 6)

    run_text_insertion(&e, " beautiful")

    expect_line_col(t, buffer.cursor, 0, 15)
    expect_cursor_index(t, buffer.cursor, 1, 9)

    contents := buffer_to_string(core.current_buffer(&e))
    testing.expectf(t, contents == expected_text, "got '%v', expected '%v'", contents, expected_text)
}

@(test)
insert_before_slice_at_beginning_of_file :: proc(t: ^testing.T) {
    e := new_test_editor()
    setup_empty_buffer(&e)

    buffer := &e.buffers[0]

    inputted_text := "Hello, world!"
    expected_text := "Well, Hello, beautiful world!\n"

    run_text_insertion(&e, inputted_text)

    // Move the cursor to the space in between 'Hello,' and 'world!'
    run_input_multiple(&e, press_key(.H), 6)
    run_text_insertion(&e, " beautiful")

    // Move to beginning of line (and hence the file)
    run_inputs(&e, []ArtificialInput{ press_key(.G), press_key(.H)})
    run_text_insertion(&e, "Well, ")

    expect_line_col(t, buffer.cursor, 0, 5)
    expect_cursor_index(t, buffer.cursor, 0, 5)

    contents := buffer_to_string(core.current_buffer(&e))
    testing.expectf(t, contents == expected_text, "got '%v', expected '%v'", contents, expected_text)
}

@(test)
insert_before_slice :: proc(t: ^testing.T) {
    e := new_test_editor()
    setup_empty_buffer(&e)

    buffer := &e.buffers[0]

    inputted_text := "Hello, world!"
    expected_text := "Hello, beautiful rich world!\n"

    run_text_insertion(&e, inputted_text)

    // Move the cursor to the space in between 'Hello,' and 'world!'
    run_input_multiple(&e, press_key(.H), 6)
    run_text_insertion(&e, " beautiful")

    // Move right to the start of the slice of ' world!'
    run_input_multiple(&e, press_key(.L), 1)

    run_text_insertion(&e, " rich")

    expect_line_col(t, buffer.cursor, 0, 20)
    expect_cursor_index(t, buffer.cursor, 2, 4)

    contents := buffer_to_string(core.current_buffer(&e))
    testing.expectf(t, contents == expected_text, "got '%v', expected '%v'", contents, expected_text)
}

@(test)
delete_last_content_slice_beginning_of_file :: proc(t: ^testing.T) {
    e := new_test_editor()
    setup_empty_buffer(&e)

    buffer := &e.buffers[0]

    run_text_insertion(&e, "Hello, world!")

    // Delete just the text
    run_input_multiple(&e, press_key(.I), 1)
    run_input_multiple(&e, press_key(.BACKSPACE), 13)

    expect_line_col(t, buffer.cursor, 0, 0)
    expect_cursor_index(t, buffer.cursor, 0, 0)

    // Try to delete when there is no text
    run_input_multiple(&e, press_key(.BACKSPACE), 1)

    expect_line_col(t, buffer.cursor, 0, 0)
    expect_cursor_index(t, buffer.cursor, 0, 0)
    testing.expect(t, len(buffer.piece_table.chunks) > 0, "BACKSPACE deleted final content slice in buffer")

    // "commit" insert mode changes, then re-enter insert mode and try to delete again
    run_input_multiple(&e, press_key(.ESCAPE), 1)
    run_input_multiple(&e, press_key(.I), 1)
    run_input_multiple(&e, press_key(.BACKSPACE), 1)

    expect_line_col(t, buffer.cursor, 0, 0)
    expect_cursor_index(t, buffer.cursor, 0, 0)
    testing.expect(t, len(buffer.piece_table.chunks) > 0, "BACKSPACE deleted final content slice in buffer")
}

@(test)
delete_in_slice :: proc(t: ^testing.T) {
    e := new_test_editor()
    setup_empty_buffer(&e)

    buffer := &e.buffers[0]

    inputted_text := "Hello, world!"
    expected_text := "Hello, beautiful h world!\n"
    //                ------          - ---------
    //                      ---------- -
    //                0     1         234

    run_text_insertion(&e, inputted_text)

    // Move the cursor to the space in between 'Hello,' and 'world!'
    run_input_multiple(&e, press_key(.H), 6)
    run_text_insertion(&e, " beautiful")

    // Move right to the start of the slice of ' world!'
    run_input_multiple(&e, press_key(.L), 1)
    run_text_insertion(&e, " rich")

    run_input_multiple(&e, press_key(.I), 1)
    run_input_multiple(&e, press_key(.BACKSPACE), 3)
    run_input_multiple(&e, press_key(.ESCAPE), 1)

    expect_line_col(t, buffer.cursor, 0, 17)
    expect_cursor_index(t, buffer.cursor, 3, 0)

    contents := buffer_to_string(core.current_buffer(&e))
    testing.expectf(t, contents == expected_text, "got '%v', expected '%v'", contents, expected_text)
}

@(test)
delete_across_slices :: proc(t: ^testing.T) {
    e := new_test_editor()
    setup_empty_buffer(&e)

    buffer := &e.buffers[0]

    inputted_text := "Hello, world!"
    expected_text := "Hello, beautiful world!\n"
    //                ------          ---------
    //                      ---------- 
    //                0     1         2

    run_text_insertion(&e, inputted_text)

    // Move the cursor to the space in between 'Hello,' and 'world!'
    run_input_multiple(&e, press_key(.H), 6)
    run_text_insertion(&e, " beautiful")

    // Move right to the start of the slice of ' world!'
    run_input_multiple(&e, press_key(.L), 1)
    run_text_insertion(&e, " rich")

    run_input_multiple(&e, press_key(.I), 1)
    run_input_multiple(&e, press_key(.BACKSPACE), 3)
    run_input_multiple(&e, press_key(.ESCAPE), 1)

    // Move right, passed the 'h' on to the space before 'world!'
    run_input_multiple(&e, press_key(.L), 1)

    // Remove the ' h', which consists of two content slices
    run_input_multiple(&e, press_key(.I), 1)
    run_input_multiple(&e, press_key(.BACKSPACE), 2)
    run_input_multiple(&e, press_key(.ESCAPE), 1)

    expect_line_col(t, buffer.cursor, 0, 16)
    expect_cursor_index(t, buffer.cursor, 2, 0)

    contents := buffer_to_string(core.current_buffer(&e))
    testing.expectf(t, contents == expected_text, "got '%v', expected '%v'", contents, expected_text)
}

@(test)
move_down_next_line_has_shorter_length :: proc(t: ^testing.T) {
    e := new_test_editor()
    setup_empty_buffer(&e)

    is_ctrl_pressed := false

    buffer := &e.buffers[0]

    run_text_insertion(&e, "012345678\n0")

    // Move up to the first line
    run_input_multiple(&e, press_key(.K), 1)

    // Move to the end of the line
    run_inputs(&e, []ArtificialInput{ press_key(.G), press_key(.L)})

    // Move down to the second line
    run_input_multiple(&e, press_key(.J), 1)

    expect_line_col(t, buffer.cursor, 1, 0)
    expect_cursor_index(t, buffer.cursor, 0, 10)
}

@(test)
move_down_on_last_line :: proc(t: ^testing.T) {
    e := new_test_editor()
    setup_empty_buffer(&e)

    is_ctrl_pressed := false

    buffer := &e.buffers[0]

    run_text_insertion(&e, "012345678")

    // Try to move down
    run_input_multiple(&e, press_key(.J), 1)

    // Cursor should stay where it is
    expect_line_col(t, buffer.cursor, 0, 8)
    expect_cursor_index(t, buffer.cursor, 0, 8)
}

@(test)
move_left_at_beginning_of_file :: proc(t: ^testing.T) {
    e := new_test_editor()
    setup_empty_buffer(&e)

    buffer := &e.buffers[0]

    run_text_insertion(&e, "01234")
    // Move cursor from --------^
    // to ------------------^
    run_input_multiple(&e, press_key(.H), 4)

    expect_line_col(t, buffer.cursor, 0, 0)
    expect_cursor_index(t, buffer.cursor, 0, 0)

    // Try to move before the beginning of the file
    run_input_multiple(&e, press_key(.H), 1)

    // Should stay the same
    expect_line_col(t, buffer.cursor, 0, 0)
    expect_cursor_index(t, buffer.cursor, 0, 0)
}

@(test)
move_right_at_end_of_file :: proc(t: ^testing.T) {
    e := new_test_editor()
    setup_empty_buffer(&e)

    is_ctrl_pressed := false

    buffer := &e.buffers[0]

    run_text_insertion(&e, "01234")

    expect_line_col(t, buffer.cursor, 0, 4)
    expect_cursor_index(t, buffer.cursor, 0, 4)

    // Try to move after the end of the file
    run_input_multiple(&e, press_key(.L), 1)

    // Should stay the same
    expect_line_col(t, buffer.cursor, 0, 4)
    expect_cursor_index(t, buffer.cursor, 0, 4)
}

@(test)
move_to_end_of_line_from_end :: proc(t: ^testing.T) {
    e := new_test_editor()
    setup_empty_buffer(&e)

    is_ctrl_pressed := false

    buffer := &e.buffers[0]

    run_text_insertion(&e, "01234\n01234")

    // Move up to the first line
    run_input_multiple(&e, press_key(.K), 1)

    // Move to the end of the line
    run_inputs(&e, []ArtificialInput{ press_key(.G), press_key(.L)})

    expect_line_col(t, buffer.cursor, 0, 4)
    expect_cursor_index(t, buffer.cursor, 0, 4)
}

@(test)
move_to_end_of_line_from_middle :: proc(t: ^testing.T) {
    e := new_test_editor()
    setup_empty_buffer(&e)

    is_ctrl_pressed := false

    buffer := &e.buffers[0]

    run_text_insertion(&e, "01234\n01234")

    // Move up to the first line
    run_input_multiple(&e, press_key(.K), 1)

    // Move into the middle of the line
    run_input_multiple(&e, press_key(.H), 2)

    // Move to the end of the line
    run_inputs(&e, []ArtificialInput{ press_key(.G), press_key(.L)})

    expect_line_col(t, buffer.cursor, 0, 4)
    expect_cursor_index(t, buffer.cursor, 0, 4)
}

@(test)
move_to_beginning_of_line_from_middle :: proc(t: ^testing.T) {
    e := new_test_editor()
    setup_empty_buffer(&e)

    is_ctrl_pressed := false

    buffer := &e.buffers[0]

    run_text_insertion(&e, "01234\n01234")

    // Move up to the first line
    run_input_multiple(&e, press_key(.K), 1)

    // Move into the middle of the line
    run_input_multiple(&e, press_key(.H), 2)

    // Move to the beginning of the line
    run_inputs(&e, []ArtificialInput{ press_key(.G), press_key(.H)})

    expect_line_col(t, buffer.cursor, 0, 0)
    expect_cursor_index(t, buffer.cursor, 0, 0)
}

@(test)
move_to_beginning_of_line_from_start :: proc(t: ^testing.T) {
    e := new_test_editor()
    setup_empty_buffer(&e)

    is_ctrl_pressed := false

    buffer := &e.buffers[0]

    run_text_insertion(&e, "01234\n01234")

    // Move up to the first line
    run_input_multiple(&e, press_key(.K), 1)

    // Move to the start of the line
    run_input_multiple(&e, press_key(.H), 4)

    // Move to the beginning of the line
    run_inputs(&e, []ArtificialInput{ press_key(.G), press_key(.H)})

    expect_line_col(t, buffer.cursor, 0, 0)
    expect_cursor_index(t, buffer.cursor, 0, 0)
}

@(test)
insert_line_under_current :: proc(t: ^testing.T) {
    e := new_test_editor()
    setup_empty_buffer(&e)

    buffer := &e.buffers[0]

    initial_text := "Hello, world!\nThis is a new line"
    run_text_insertion(&e, initial_text)

    expected_text := "Hello, world!\nThis is the second line\nThis is a new line\n"
    //                -------------                         ---------------------- 
    //                             -------------------------                      
    //                0            1                        3                     

    // Move cursor up onto the end of "Hello, world!"
    run_input_multiple(&e, press_key(.K), 1)

    // Insert line below and enter insert mode
    run_input_multiple(&e, press_key(.O), 1)

    // Technically the cursor is still on the first line, because the `input_buffer`
    // has been modified but not the actual contents of the filebuffer
    expect_line_col(t, buffer.cursor, 0, 13)
    expect_cursor_index(t, buffer.cursor, 0, 13)

    run_text_insertion(&e, "This is the second line")

    expect_line_col(t, buffer.cursor, 1, 22)
    expect_cursor_index(t, buffer.cursor, 1, 23)

    contents := buffer_to_string(core.current_buffer(&e))
    testing.expectf(t, contents == expected_text, "got '%v', expected '%v'", contents, expected_text)
}

@(test)
yank_and_paste_whole_line :: proc(t: ^testing.T) {
    e := new_test_editor()
    setup_empty_buffer(&e)

    buffer := &e.buffers[0]

    initial_text := "Hello, world!\nThis is a new line"
    run_text_insertion(&e, initial_text)

    expected_text := "Hello, world!\nThis is a new line\nThis is a new line\n"

    // Copy whole line
    run_input_multiple(&e, press_key(.Y), 2)

    // Move up to "Hello, world!"
    run_input_multiple(&e, press_key(.K), 1)

    // Paste it below current one
    run_input_multiple(&e, press_key(.P), 1)

    expect_line_col(t, buffer.cursor, 1, 0)

    contents := buffer_to_string(core.current_buffer(&e))
    testing.expectf(t, contents == expected_text, "got '%v', expected '%v'", contents, expected_text)
}

run_editor_frame :: proc(state: ^core.State, input: ArtificialInput, is_ctrl_pressed: ^bool) {
    log.infof("running input: %v", input)

    {
        run_key_action := proc(state: ^core.State, control_key_pressed: bool, key: core.Key) -> bool {
            log.info("key_action")

            if state.current_input_map != nil {
                if control_key_pressed {
                    if action, exists := state.current_input_map.ctrl_key_actions[key]; exists {
                        switch value in action.action {
                            case core.EditorAction:
                                value(state);
                                return true;
                            case core.InputActions:
                                state.current_input_map = &(&state.current_input_map.ctrl_key_actions[key]).action.(core.InputActions)
                                return true;
                        }
                    }
                } else {
                    if action, exists := state.current_input_map.key_actions[key]; exists {
                        switch value in action.action {
                            case core.EditorAction:
                                value(state);
                                return true;
                            case core.InputActions:
                                state.current_input_map = &(&state.current_input_map.key_actions[key]).action.(core.InputActions)
                                return true;
                        }
                    }
                }
            } else {
                log.info("current_input_map is null")
            }

            return false
        }

        switch state.mode {
            case .Visual: fallthrough
            case .Normal: {
                log.info("it's normal/visual mode")

                if key, ok := input.(ArtificialKey); ok {
                    if key.is_down {
                        if key.key == .LCTRL {
                            is_ctrl_pressed^ = true;
                        } else {
                            run_key_action(state, is_ctrl_pressed^, key.key)
                        }
                    } else {
                        if key.key == .LCTRL {
                            is_ctrl_pressed^ = false;
                        }
                    }
                }
            }
            case .Insert: {
                log.info("it's insert mode")

                buffer := core.current_buffer(state);

                if key, ok := input.(ArtificialKey); ok {
                    if key.is_down {
                        // TODO: make this work properly
                        if true || !run_key_action(state, is_ctrl_pressed^, key.key) {
                            #partial switch key.key {
                                case .ESCAPE: {
                                    state.mode = .Normal;

                                    core.insert_content(buffer, buffer.input_buffer[:]);
                                    runtime.clear(&buffer.input_buffer);
                                }
                                case .TAB: {
                                    // TODO: change this to insert a tab character
                                    for _ in 0..<4 {
                                        append(&buffer.input_buffer, ' ');
                                    }
                                }
                                case .BACKSPACE: {
                                    core.delete_content(buffer, 1);
                                }
                                case .ENTER: {
                                    append(&buffer.input_buffer, '\n');
                                }
                            }
                        }
                    }
                }

                log.info("before text input")
                if text_input, ok := input.(ArtificialTextInput); ok {
                    log.infof("attempting to append '%v' to buffer", text_input)

                    for char in text_input.text {
                        if char < 1 {
                            break;
                        }

                        if char == '\n' || (char >= 32 && char <= 125 && len(buffer.input_buffer) < 1024-1) {
                            log.infof("appening '%v' to buffer", char)
                            append(&buffer.input_buffer, u8(char));
                        }
                    }

                    if current_panel, ok := state.current_panel.?; ok {
                        if panel, ok := util.get(&state.panels, current_panel).?; ok && panel.on_buffer_input_proc != nil {
                            panel.on_buffer_input_proc(state, &panel.panel_state)
                        }
                    }
                }
            }
        }
    }
    
    // TODO: share this with the main application
    do_insert_mode :: proc(state: ^core.State, buffer: ^core.FileBuffer) {
        key := 0;

        for key > 0 {
            if key >= 32 && key <= 125 && len(buffer.input_buffer) < 1024-1 {
                append(&buffer.input_buffer, u8(key));
            }

            key = 0;
        }
    }

    switch state.mode {
        case .Normal:
            // buffer := core.current_buffer(state);
            // do_normal_mode(state, buffer);
        case .Insert:
            buffer := core.current_buffer(state);
            do_insert_mode(state, buffer);
        case .Visual:
            // buffer := core.current_buffer(state);
            // do_visual_mode(state, buffer);
    }

    runtime.free_all(context.temp_allocator);
}
