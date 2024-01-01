package ui;

import "core:math"
import "vendor:raylib"

import "../core"
import "../theme"

draw_buffer_list_window :: proc(state: ^core.State) {
    win_rec := raylib.Rectangle {
        x = f32(state.screen_width/8),
        y = f32(state.screen_height/8),
        width = f32(state.screen_width - state.screen_width/4),
        height = f32(state.screen_height - state.screen_height/4),
    };
    raylib.DrawRectangleRec(
        win_rec,
        theme.get_palette_raylib_color(.Background4));

    win_margin := raylib.Vector2 { f32(state.source_font_width), f32(state.source_font_height) };

    buffer_prev_width := (win_rec.width - win_margin.x*2) / 2;
    buffer_prev_height := win_rec.height - win_margin.y*2;

    glyph_buffer_width := int(buffer_prev_width) / state.source_font_width - 1;
    glyph_buffer_height := int(buffer_prev_height) / state.source_font_height;

    raylib.DrawRectangle(
        i32(win_rec.x + win_rec.width / 2),
        i32(win_rec.y + win_margin.y),
        i32(buffer_prev_width),
        i32(buffer_prev_height),
        theme.get_palette_raylib_color(.Background2));

    for _, index in state.buffers {
        buffer := &state.buffers[index];
        text := raylib.TextFormat("%s:%d", buffer.file_path, buffer.cursor.line+1);
        text_width := raylib.MeasureTextEx(state.font, text, f32(state.source_font_height), 0);

        if index == state.buffer_list_window_selected_buffer {
            buffer.glyph_buffer_height = glyph_buffer_height;
            buffer.glyph_buffer_width = glyph_buffer_width;
            core.draw_file_buffer(
                state,
                buffer,
                int(win_rec.x + win_margin.x + win_rec.width / 2),
                int(win_rec.y + win_margin.y),
                state.font,
                show_line_numbers = false);

            raylib.DrawRectangle(
                i32(win_rec.x + win_margin.x),
                i32(win_rec.y + win_margin.y) + i32(index * state.source_font_height),
                i32(text_width.x),
                i32(state.source_font_height),
                theme.get_palette_raylib_color(.Background2));
        }

        raylib.DrawTextEx(
            state.font,
            text,
            raylib.Vector2 { win_rec.x + win_margin.x, win_rec.y + win_margin.y + f32(index * state.source_font_height) },
            f32(state.source_font_height),
            0,
            theme.get_palette_raylib_color(.Foreground2));
    }
}
