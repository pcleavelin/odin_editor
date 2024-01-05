package ui;

@(extra_linker_flags="-L./lib-rg/target/debug/")
foreign import rg "system:rg"

ExternMatch :: struct {
    text_ptr: [^]u8,
    text_len: int,
    text_cap: int,

    path_ptr: [^]u8,
    path_len: int,
    path_cap: int,

    line: u64,
    col: u64
}

ExternMatchArray :: struct {
    matches: [^]ExternMatch,
    len: uint,
    capacity: uint,
}

foreign rg {
    rg_search :: proc (pattern: cstring, path: cstring) -> ExternMatchArray ---
    drop_match_array :: proc(match_array: ExternMatchArray) ---
}

import "core:os"
import "core:path/filepath"
import "core:math"
import "core:fmt"
import "core:runtime"
import "core:strings"
import "vendor:raylib"

import "../core"
import "../theme"

GrepMatch :: struct {
    text: string,
    path: string,
    line: int,
    col: int,
}

transmute_extern_matches :: proc(extern_matches: ExternMatchArray, dest: ^[dynamic]GrepMatch) {
    if extern_matches.matches != nil {
        for i in 0..<extern_matches.len {
            match := &extern_matches.matches[i];

            path: string = "";
            if match.path_ptr != nil && match.path_len > 0 {
                path, _ = filepath.abs(strings.string_from_ptr(match.path_ptr, match.path_len));
            }

            text: string = "";
            if match.text_ptr != nil && match.text_len > 0 {
                text = strings.string_from_ptr(match.text_ptr, match.text_len);
            }

            cloned := GrepMatch {
                text = text,
                path = path,
                line = int(match.line),
                col = int(match.col)
            };

            append(dest, cloned);
        }
    }
}

GrepWindow :: struct {
    using window: core.Window,

    input_buffer: core.FileBuffer,

    selected_match: int,

    extern_matches: ExternMatchArray,
    matches: [dynamic]GrepMatch,
}

create_grep_window :: proc() -> ^GrepWindow {
    input_map := core.new_input_map();

    core.register_key_action(&input_map, .ENTER, proc(state: ^core.State) {
        win := cast(^GrepWindow)(state.window);

        if win.matches != nil && len(win.matches) > 0 {
            should_create_buffer := true;
            for buffer, index in state.buffers {
                if strings.compare(buffer.file_path, win.matches[win.selected_match].path) == 0 {
                    state.current_buffer = index;
                    should_create_buffer = false;
                    break;
                }
            }

            buffer: ^core.FileBuffer = nil;
            err := core.no_error();

            if should_create_buffer {
                new_buffer, err := core.new_file_buffer(context.allocator, strings.clone(win.matches[win.selected_match].path));
                if err.type != .None {
                    fmt.println("Failed to open/create file buffer:", err);
                } else {
                    runtime.append(&state.buffers, new_buffer);
                    state.current_buffer = len(state.buffers)-1;
                    buffer = &state.buffers[state.current_buffer];
                }
            } else {
                buffer = &state.buffers[state.current_buffer];
            }

            if buffer != nil {
                buffer.cursor.line = win.matches[win.selected_match].line-1;
                buffer.cursor.col = 0;
                buffer.glyph_buffer_height = math.min(256, int((state.screen_height - state.source_font_height*2) / state.source_font_height)) + 1;
                buffer.glyph_buffer_width = math.min(256, int((state.screen_width - state.source_font_width) / state.source_font_width));
                core.update_file_buffer_index_from_cursor(buffer);

                core.request_window_close(state);
            }
        }
    }, "jump to location");

    core.register_key_action(&input_map, .I, proc(state: ^core.State) {
        state.mode = .Insert;
    }, "enter insert mode");

    core.register_key_action(&input_map, .T, proc(state: ^core.State) {
        win := cast(^GrepWindow)(state.window);

        grep_files(win, state);
    }, "example search");
    core.register_key_action(&input_map, .K, proc(state: ^core.State) {
        win := cast(^GrepWindow)(state.window);

        if win.selected_match > 0 {
            win.selected_match -= 1;
        } else {
            win.selected_match = len(win.matches)-1;
        }

    }, "move selection up");
    core.register_key_action(&input_map, .J, proc(state: ^core.State) {
        win := cast(^GrepWindow)(state.window);

        if win.selected_match >= len(win.matches)-1 {
            win.selected_match = 0;
        } else {
            win.selected_match += 1;
        }
    }, "move selection down");

    grep_window := new(GrepWindow);
    grep_window^ = GrepWindow {
        window = core.Window {
            input_map = input_map,
            draw = draw_grep_window,
            get_buffer = grep_window_get_buffer,
            free = free_grep_window,
        },

        input_buffer = core.new_virtual_file_buffer(context.allocator),
        matches = make([dynamic]GrepMatch),
    };

    return grep_window;
}

free_grep_window :: proc(win: ^core.Window, state: ^core.State) {
    win := cast(^GrepWindow)(win);

    if win.extern_matches.matches != nil {
        drop_match_array(win.extern_matches);
        win.extern_matches.matches = nil;
        win.extern_matches.len = 0;
        win.extern_matches.capacity = 0;
    }

    delete(win.matches);
    core.free_file_buffer(&win.input_buffer);
}

grep_window_get_buffer :: proc(win: ^core.Window) -> ^core.FileBuffer {
    win := cast(^GrepWindow)(win);

    return &win.input_buffer;
}

@private
grep_files :: proc(win: ^core.Window, state: ^core.State) {
    win := cast(^GrepWindow)(win);

    if win.extern_matches.matches != nil {
        drop_match_array(win.extern_matches);
        win.extern_matches.matches = nil;
        win.extern_matches.len = 0;
        win.extern_matches.capacity = 0;
    }

    if win.matches != nil {
        clear_dynamic_array(&win.matches);
    } else {
        win.matches = make([dynamic]GrepMatch);
    }

    builder := strings.builder_make();
    it := core.new_file_buffer_iter(&win.input_buffer);
    for character in core.iterate_file_buffer(&it) {
        if character == '\n' { break; }

        strings.write_rune(&builder, rune(character));
    }
    pattern := strings.clone_to_cstring(strings.to_string(builder));

    win.extern_matches = rg_search(pattern, strings.clone_to_cstring(state.directory));
    transmute_extern_matches(win.extern_matches, &win.matches);
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

    for match, index in win.matches {
        relative_file_path, _ := filepath.rel(state.directory, match.path)
        text := raylib.TextFormat("%s:%d:%d: %s", relative_file_path, match.line, match.col, match.text);
        text_width := raylib.MeasureTextEx(state.font, text, f32(state.source_font_height), 0);

        if index == win.selected_match {
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
