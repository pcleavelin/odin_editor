package main

import "core:os"
import "core:math"
import "core:strings"
import "core:runtime"
import "core:fmt"
import "core:mem"
import "core:slice"
import "vendor:raylib"

import "core"
import "theme"
import "ui"

State :: core.State;
FileBuffer :: core.FileBuffer;

// TODO: use buffer list in state
do_normal_mode :: proc(state: ^State, buffer: ^FileBuffer) {
    if state.current_input_map != nil {
        if raylib.IsKeyDown(.LEFT_CONTROL) {
            for key, action in &state.current_input_map.ctrl_key_actions {
                if raylib.IsKeyPressed(key) {
                    switch value in action.action {
                        case core.EditorAction:
                            value(state);
                        case core.InputMap:
                            state.current_input_map = &(&state.current_input_map.ctrl_key_actions[key]).action.(core.InputMap)
                    }
                }
            }
        } else {
            for key, action in state.current_input_map.key_actions {
                if raylib.IsKeyPressed(key) {
                    switch value in action.action {
                        case core.EditorAction:
                            value(state);
                        case core.InputMap:
                            state.current_input_map = &(&state.current_input_map.key_actions[key]).action.(core.InputMap)
                    }
                }
            }
        }
    }
}

// TODO: use buffer list in state
do_insert_mode :: proc(state: ^State, buffer: ^FileBuffer) {
    key := raylib.GetCharPressed();

    for key > 0 {
        if key >= 32 && key <= 125 && len(buffer.input_buffer) < 1024-1 {
            append(&buffer.input_buffer, u8(key));
        }

        key = raylib.GetCharPressed();
    }

    if raylib.IsKeyPressed(.ENTER) {
        append(&buffer.input_buffer, '\n');
    }

    if raylib.IsKeyPressed(.ESCAPE) {
        state.mode = .Normal;

        core.insert_content(buffer, buffer.input_buffer[:]);
        runtime.clear(&buffer.input_buffer);
        return;
    }

    if raylib.IsKeyPressed(.BACKSPACE) {
        core.delete_content(buffer, 1);
    }
}

switch_to_buffer :: proc(state: ^State, item: ^ui.MenuBarItem) {
    for buffer, index in state.buffers {
        if strings.compare(buffer.file_path, item.text) == 0 {
            state.current_buffer = index;
            break;
        }
    }
}

register_default_leader_actions :: proc(input_map: ^core.InputMap) {
    core.register_key_action(input_map, .B, proc(state: ^State) {
        state.buffer_list_window_is_visible = true;
        state.current_input_map = &state.buffer_list_window_input_map;
    }, "show list of open buffers");
}

register_default_input_actions :: proc(input_map: ^core.InputMap) {
    core.register_key_action(input_map, .W, proc(state: ^State) {
        core.move_cursor_forward_start_of_word(&state.buffers[state.current_buffer]);
    }, "move forward one word");

    core.register_key_action(input_map, .K, proc(state: ^State) {
        core.move_cursor_up(&state.buffers[state.current_buffer]);
    }, "move up one line");
    core.register_key_action(input_map, .J, proc(state: ^State) {
        core.move_cursor_down(&state.buffers[state.current_buffer]);
    }, "move down one line");
    core.register_key_action(input_map, .H, proc(state: ^State) {
        core.move_cursor_left(&state.buffers[state.current_buffer]);
    }, "move left one char");
    core.register_key_action(input_map, .L, proc(state: ^State) {
        core.move_cursor_right(&state.buffers[state.current_buffer]);
    }, "move right one char");

    core.register_ctrl_key_action(input_map, .U, proc(state: ^State) {
        core.scroll_file_buffer(&state.buffers[state.current_buffer], .Up);
    }, "scroll buffer up");
    core.register_ctrl_key_action(input_map, .D, proc(state: ^State) {
        core.scroll_file_buffer(&state.buffers[state.current_buffer], .Down);
    }, "scroll buffer up");

    core.register_key_action(input_map, .I, proc(state: ^State) {
        state.mode = .Insert;
    }, "enter insert mode");

    core.register_key_action(input_map, .SPACE, core.new_input_map(), "leader commands");
    register_default_leader_actions(&(&input_map.key_actions[.SPACE]).action.(core.InputMap));
}

register_buffer_list_input_actions :: proc(input_map: ^core.InputMap) {
    core.register_key_action(input_map, .K, proc(state: ^State) {
        if state.buffer_list_window_selected_buffer > 0 {
            state.buffer_list_window_selected_buffer -= 1;
        } else {
            state.buffer_list_window_selected_buffer = len(state.buffers)-1;
        }
    }, "move selection up");
    core.register_key_action(input_map, .J, proc(state: ^State) {
        if state.buffer_list_window_selected_buffer >= len(state.buffers)-1 {
            state.buffer_list_window_selected_buffer = 0;
        } else {
            state.buffer_list_window_selected_buffer += 1;
        }
    }, "move selection down");
    core.register_key_action(input_map, .ENTER, proc(state: ^State) {
        state.current_buffer = state.buffer_list_window_selected_buffer;

        state.buffer_list_window_is_visible = false;
        state.current_input_map = &state.input_map;
    }, "switch to file");

    core.register_key_action(input_map, .Q, proc(state: ^State) {
        state.buffer_list_window_is_visible = false;
        state.current_input_map = &state.input_map;
    }, "close window");
}

main :: proc() {
    state := State {
        input_map = core.new_input_map(),
        buffer_list_window_input_map = core.new_input_map(),
    };
    state.current_input_map = &state.input_map;
    register_default_input_actions(&state.input_map);
    register_buffer_list_input_actions(&state.buffer_list_window_input_map);

    for arg in os.args[1:] {
        buffer, err := core.new_file_buffer(context.allocator, arg);
        if err.type != .None {
            fmt.println("Failed to create file buffer:", err);
            continue;
        }

        runtime.append(&state.buffers, buffer);
    }
    buffer_items := make([dynamic]ui.MenuBarItem, 0, len(state.buffers));
    for buffer, index in state.buffers {
        item := ui.MenuBarItem {
            text = buffer.file_path,
            on_click = switch_to_buffer,
        };

        runtime.append(&buffer_items, item);
    }

    raylib.InitWindow(640, 480, "odin_editor - [back to basics]");
    raylib.SetWindowState({ .WINDOW_RESIZABLE, .VSYNC_HINT });
    raylib.SetTargetFPS(60);
    raylib.SetExitKey(.KEY_NULL);

    font := raylib.LoadFont("../c_editor/Mx437_ToshibaSat_8x16.ttf");
    state.font = font;
    menu_bar_state := ui.MenuBarState{
        items = []ui.MenuBarItem {
            ui.MenuBarItem {
                text = "Buffers",
                sub_items = buffer_items[:],
            }
        }
    };

    for !raylib.WindowShouldClose() && !state.should_close {
        state.screen_width = raylib.GetScreenWidth();
        state.screen_height = raylib.GetScreenHeight();
        mouse_pos := raylib.GetMousePosition();

        buffer := &state.buffers[state.current_buffer];

        buffer.glyph_buffer_height = math.min(256, int((state.screen_height - core.source_font_height*2) / core.source_font_height)) + 1;
        buffer.glyph_buffer_width = math.min(256, int((state.screen_width - core.source_font_width) / core.source_font_width));

        {
            raylib.BeginDrawing();
            defer raylib.EndDrawing();

            raylib.ClearBackground(theme.get_palette_raylib_color(.Background));
            core.draw_file_buffer(&state, buffer, 32, core.source_font_height, font);
            ui.draw_menu_bar(&menu_bar_state, 0, 0, state.screen_width, state.screen_height, font, core.source_font_height);

            raylib.DrawRectangle(0, state.screen_height - core.source_font_height, state.screen_width, core.source_font_height, theme.get_palette_raylib_color(.Background2));

            line_info_text := raylib.TextFormat(
                "Line: %d, Col: %d --- Slice Index: %d, Content Index: %d",
                buffer.cursor.line + 1,
                buffer.cursor.col + 1,
                buffer.cursor.index.slice_index,
                buffer.cursor.index.content_index);
            line_info_width := raylib.MeasureTextEx(font, line_info_text, core.source_font_height, 0).x;

            switch state.mode {
                case .Normal:
                    raylib.DrawRectangle(
                        0,
                        state.screen_height - core.source_font_height,
                        8 + len("NORMAL")*core.source_font_width,
                        core.source_font_height,
                        theme.get_palette_raylib_color(.Foreground4));
                    raylib.DrawRectangleV(
                        raylib.Vector2 { f32(state.screen_width) - line_info_width - 8, f32(state.screen_height - core.source_font_height) },
                        raylib.Vector2 { 8 + line_info_width, f32(core.source_font_height) },
                        theme.get_palette_raylib_color(.Foreground4));
                    raylib.DrawTextEx(
                        font,
                        "NORMAL",
                        raylib.Vector2 { 4, f32(state.screen_height - core.source_font_height) },
                        core.source_font_height,
                        0,
                        theme.get_palette_raylib_color(.Background1));
                case .Insert:
                    raylib.DrawRectangle(
                        0,
                        state.screen_height - core.source_font_height,
                        8 + len("INSERT")*core.source_font_width,
                        core.source_font_height,
                        theme.get_palette_raylib_color(.Foreground2));
                    raylib.DrawRectangleV(
                        raylib.Vector2 { f32(state.screen_width) - line_info_width - 8, f32(state.screen_height - core.source_font_height) },
                        raylib.Vector2 { 8 + line_info_width, f32(core.source_font_height) },
                        theme.get_palette_raylib_color(.Foreground2));
                    raylib.DrawTextEx(
                        font,
                        "INSERT",
                        raylib.Vector2 { 4, f32(state.screen_height - core.source_font_height) },
                        core.source_font_height,
                        0,
                        theme.get_palette_raylib_color(.Background1));
            }

            raylib.DrawTextEx(
                font,
                line_info_text,
                raylib.Vector2 { f32(state.screen_width) - line_info_width - 4, f32(state.screen_height - core.source_font_height) },
                core.source_font_height,
                0,
                theme.get_palette_raylib_color(.Background1));

            if state.buffer_list_window_is_visible {
                ui.draw_buffer_list_window(&state);
            }

            if state.current_input_map != &state.input_map {
                longest_description := 0;
                for key, action in state.current_input_map.key_actions {
                    if len(action.description) > longest_description {
                        longest_description = len(action.description);
                    }
                }
                longest_description += 4;

                helper_height := i32(core.source_font_height * len(state.current_input_map.key_actions));

                raylib.DrawRectangle(
                    state.screen_width - i32(longest_description * core.source_font_width),
                    state.screen_height - helper_height - 20,
                    i32(longest_description*core.source_font_width),
                    helper_height,
                    theme.get_palette_raylib_color(.Background2));

                index := 0;
                for key, action in state.current_input_map.key_actions {
                    raylib.DrawTextEx(
                        font,
                        raylib.TextFormat("%s - %s", key, action.description),
                        raylib.Vector2 { f32(state.screen_width - i32(longest_description * core.source_font_width)), f32(state.screen_height - helper_height + i32((index) * core.source_font_height) - 20) },
                        core.source_font_height,
                        0,
                        theme.get_palette_raylib_color(.Foreground1));
                    index += 1;
                }
            }
        }

        switch state.mode {
            case .Normal:
                do_normal_mode(&state, buffer);
            case .Insert:
                do_insert_mode(&state, buffer);
        }

        ui.test_menu_bar(&state, &menu_bar_state, 0,0, mouse_pos, raylib.IsMouseButtonReleased(.LEFT), font, core.source_font_height);
    }
}
