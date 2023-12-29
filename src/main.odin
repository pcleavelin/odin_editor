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
    if raylib.IsKeyPressed(.I) {
        state.mode = .Insert;
        return;
    }

    if raylib.IsKeyPressed(.W) {
        core.move_cursor_forward_start_of_word(buffer);
    }

    if raylib.IsKeyPressed(.K) {
        core.move_cursor_up(buffer);
    }
    if raylib.IsKeyPressed(.J) {
        core.move_cursor_down(buffer);
    }
    if raylib.IsKeyPressed(.H) {
        core.move_cursor_left(buffer);
    }
    if raylib.IsKeyPressed(.L) {
        core.move_cursor_right(buffer);
    }

    if raylib.IsKeyDown(.LEFT_CONTROL) && raylib.IsKeyDown(.U) {
        core.scroll_file_buffer(buffer, .Up);
    }
    if raylib.IsKeyDown(.LEFT_CONTROL) && raylib.IsKeyDown(.D) {
        core.scroll_file_buffer(buffer, .Down);
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

main :: proc() {
    state: State;

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
    menu_bar_state := ui.MenuBarState{
        items = []ui.MenuBarItem {
            ui.MenuBarItem {
                text = "Buffers",
                sub_items = buffer_items[:],
            }
        }
    };

    for !raylib.WindowShouldClose() && !state.should_close {
        screen_width := raylib.GetScreenWidth();
        screen_height := raylib.GetScreenHeight();
        mouse_pos := raylib.GetMousePosition();

        buffer := &state.buffers[state.current_buffer];

        buffer.glyph_buffer_height = math.min(256, int((screen_height - 32 - core.source_font_height) / core.source_font_height));

        {
            raylib.BeginDrawing();
            defer raylib.EndDrawing();

            raylib.ClearBackground(theme.get_palette_raylib_color(.Background));
            core.draw_file_buffer(&state, buffer, 32, core.source_font_height, font);
            ui.draw_menu_bar(&menu_bar_state, 0, 0, screen_width, screen_height, font, core.source_font_height);

            raylib.DrawRectangle(0, screen_height - core.source_font_height, screen_width, core.source_font_height, theme.get_palette_raylib_color(.Background2));

            line_info_text := raylib.TextFormat("Line: %d, Col: %d --- Slice Index: %d, Content Index: %d", buffer.cursor.line + 1, buffer.cursor.col + 1, buffer.cursor.index.slice_index, buffer.cursor.index.content_index);
            line_info_width := raylib.MeasureTextEx(font, line_info_text, core.source_font_height, 0).x;

            switch state.mode {
                case .Normal:
                    raylib.DrawRectangle(0, screen_height - core.source_font_height, 8 + len("NORMAL")*core.source_font_width, core.source_font_height, theme.get_palette_raylib_color(.Foreground4));
                    raylib.DrawRectangleV(raylib.Vector2 { f32(screen_width) - line_info_width - 8 , f32(screen_height - core.source_font_height) }, raylib.Vector2 { 8 + line_info_width, f32(core.source_font_height) }, theme.get_palette_raylib_color(.Foreground4));

                    raylib.DrawTextEx(font, "NORMAL", raylib.Vector2 { 4, f32(screen_height - core.source_font_height) }, core.source_font_height, 0, theme.get_palette_raylib_color(.Background1));
                case .Insert:
                    raylib.DrawRectangle(0, screen_height - core.source_font_height, 8 + len("INSERT")*core.source_font_width, core.source_font_height, raylib.SKYBLUE);
                    raylib.DrawRectangleV(raylib.Vector2 { f32(screen_width) - line_info_width - 8 , f32(screen_height - core.source_font_height) }, raylib.Vector2 { 8 + line_info_width, f32(core.source_font_height) }, raylib.SKYBLUE);

                    raylib.DrawTextEx(font, "INSERT", raylib.Vector2 { 4, f32(screen_height - core.source_font_height) }, core.source_font_height, 0, raylib.DARKBLUE);
            }


            raylib.DrawTextEx(font, line_info_text, raylib.Vector2 { f32(screen_width) - line_info_width - 4, f32(screen_height - core.source_font_height) }, core.source_font_height, 0, theme.get_palette_raylib_color(.Background1));
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
