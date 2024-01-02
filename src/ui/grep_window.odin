package ui;

import "core:math"
import "vendor:raylib"

import "../core"
import "../theme"

GrepWindow :: struct {
    using window: core.Window,

    input_buffer: core.FileBuffer,
}

create_grep_window :: proc() -> ^GrepWindow {
    input_map := core.new_input_map();

    core.register_key_action(&input_map, .ENTER, proc(state: ^core.State) {
        win := cast(^GrepWindow)(state.window);

        core.request_window_close(state);
    }, "jump to location");

    core.register_key_action(&input_map, .I, proc(state: ^core.State) {
        state.mode = .Insert;
    }, "enter insert mode");

    grep_window := new(GrepWindow);
    grep_window^ = GrepWindow {
        window = core.Window {
            input_map = input_map,
            draw = draw_grep_window,
            get_buffer = grep_window_get_buffer,
            free = free_grep_window,
        },

        input_buffer = core.new_virtual_file_buffer(context.allocator),
    };

    return grep_window;
}

free_grep_window :: proc(win: ^core.Window, state: ^core.State) {
    win := cast(^GrepWindow)(win);

    core.free_file_buffer(&win.input_buffer);
}

grep_window_get_buffer :: proc(win: ^core.Window) -> ^core.FileBuffer {
    win := cast(^GrepWindow)(win);

    return &win.input_buffer;
}

@private
grep_files :: proc(win: ^core.Window, state: ^core.State) {
    // TODO: use rip-grep to search through files
}

draw_grep_window :: proc(win: ^core.Window, state: ^core.State) {
    win := cast(^GrepWindow)(win);

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
    glyph_buffer_height := 1;

    raylib.DrawRectangle(
        i32(win_rec.x + win_margin.x),
        i32(win_rec.y + win_rec.height - win_margin.y * 2),
        i32(buffer_prev_width),
        i32(state.source_font_height),
        theme.get_palette_raylib_color(.Background2));

    win.input_buffer.glyph_buffer_height = glyph_buffer_height;
    win.input_buffer.glyph_buffer_width = glyph_buffer_width;
    core.draw_file_buffer(
        state,
        &win.input_buffer,
        int(win_rec.x + win_margin.x),
        int(win_rec.y + win_rec.height - win_margin.y * 2),
        state.font,
        show_line_numbers = false);
}
