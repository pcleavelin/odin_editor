package main

import "core:os"
import "core:runtime"
import "core:fmt"
import "core:mem"
import "core:slice"
import "vendor:raylib"

source_font_width :: 8;
source_font_height :: 16;
line_number_padding :: 4 * source_font_width;

ErrorType :: enum {
    None,
    FileIOError,
}

Error :: struct {
    type: ErrorType,
    loc: runtime.Source_Code_Location,
    msg: string,
}

make_error :: proc(type: ErrorType, msg: string, loc := #caller_location) -> Error {
    return Error {
        type = type,
        loc = loc,
        msg = msg
    }
}

no_error :: proc() -> Error {
    return Error {
        type = .None,
    }
}

error :: proc{make_error, no_error};

ScrollDir :: enum {
    Up,
    Down,
}

ContentType :: enum {
    Original,
    Added,
}

ContentSlice :: struct {
    type: ContentType,
    slice: []u8,
}

FileBufferIndex :: struct {
    slice_index: int,
    content_index: int,
}

Cursor :: struct {
    col: int,
    line: int,
    buffer_index: FileBufferIndex,
}

Glyph :: struct #packed {
    codepoint: u8,
    color: u16,
}

FileBuffer :: struct {
    allocator: mem.Allocator,

    file_path: string,
    top_line: int,
    cursor: Cursor,

    original_content: [dynamic]u8,
    added_content: [dynamic]u8,
    content_slices: [dynamic][]u8,

    glyph_buffer_width: int,
    glyph_buffer_height: int,
    glyph_buffer: [dynamic]Glyph,

    input_buffer: [dynamic]u8,
}

FileBufferIter :: struct {
    index: FileBufferIndex,
    buffer: ^FileBuffer,
}

Mode :: enum {
    Normal,
    Insert,
}

State :: struct {
    mode: Mode,
}

new_file_buffer_iter_from_beginning :: proc(file_buffer: ^FileBuffer) -> FileBufferIter {
    return FileBufferIter { buffer = file_buffer };
}
new_file_buffer_iter_with_index :: proc(file_buffer: ^FileBuffer, index: FileBufferIndex) -> FileBufferIter {
    return FileBufferIter { buffer = file_buffer, index = index };
}
new_file_buffer_iter :: proc{new_file_buffer_iter_from_beginning, new_file_buffer_iter_with_index};

iterate_file_buffer :: proc(it: ^FileBufferIter) -> (character: u8, idx: FileBufferIndex, cond: bool) {
    if it.index.slice_index >= len(it.buffer.content_slices) || it.index.content_index >= len(it.buffer.content_slices[it.index.slice_index]) {
        return;
    }
    cond = true;

    character = it.buffer.content_slices[it.index.slice_index][it.index.content_index];

    it.index.content_index += 1;
    if it.index.content_index >= len(it.buffer.content_slices[it.index.slice_index]) {
        it.index.content_index = 0;
        it.index.slice_index += 1;
    }

    return;
}

update_file_buffer_index_from_cursor :: proc(buffer: ^FileBuffer) {
    it := new_file_buffer_iter(buffer);
    before_it := new_file_buffer_iter(buffer);

    line_length := 0;
    rendered_line := 0;

    for character in iterate_file_buffer(&it) {
        if line_length == buffer.cursor.col && rendered_line == buffer.cursor.line {
            break;
        }

        if character == '\n' {
            rendered_line += 1;
            line_length = 0;
        } else {
            line_length += 1;
        }

        before_it = it;
    }

    buffer.cursor.buffer_index = before_it.index;
}

file_buffer_line_length :: proc(buffer: ^FileBuffer) -> int {
    line_length := 0;
    rendered_line := 0;

    for i in 0..<len(buffer.content_slices) {
        content := buffer.content_slices[i];

        for c in content {
            if c == '\n' {
                rendered_line += 1;

                if rendered_line > buffer.cursor.line {
                    return line_length;
                }

                continue;
            }

            if rendered_line == buffer.cursor.line {
                line_length += 1;
            }
        }
    }

    return line_length;
}

move_cursor_up :: proc(buffer: ^FileBuffer) {
    if buffer.cursor.line > 0 {
        buffer.cursor.line -= 1;

        if buffer.cursor.line < buffer.top_line + 5 && buffer.cursor.line >= 4 {
            buffer.top_line = buffer.cursor.line - 4;
        }

        line_length := file_buffer_line_length(buffer);
        if buffer.cursor.col >= line_length {
            buffer.cursor.col = line_length < 1 ? 0 : line_length - 1;
        }

        update_file_buffer_index_from_cursor(buffer);
    }
}

move_cursor_down :: proc(buffer: ^FileBuffer) {
    buffer.cursor.line += 1;

    if buffer.cursor.line > buffer.top_line + (buffer.glyph_buffer_height - 5) {
        buffer.top_line = buffer.cursor.line - (buffer.glyph_buffer_height - 5);
    }

    line_length := file_buffer_line_length(buffer);
    if buffer.cursor.col >= line_length {
        buffer.cursor.col = line_length < 1 ? 0 : line_length - 1;
    }

    update_file_buffer_index_from_cursor(buffer);
}

move_cursor_left :: proc(buffer: ^FileBuffer) {
    if buffer.cursor.col > 0 {
        buffer.cursor.col -= 1;
        update_file_buffer_index_from_cursor(buffer);
    }
}

move_cursor_right :: proc(buffer: ^FileBuffer) {
    line_length := file_buffer_line_length(buffer);

    if line_length > 0 && buffer.cursor.col < line_length-1 {
        buffer.cursor.col += 1;
        update_file_buffer_index_from_cursor(buffer);
    }
}

new_file_buffer :: proc(allocator: mem.Allocator, file_path: string) -> (FileBuffer, Error) {
    context.allocator = allocator;

    fd, err := os.open(file_path);
    if err != os.ERROR_NONE {
        return FileBuffer{}, make_error(ErrorType.FileIOError, fmt.aprintf("failed to open file: errno=%x", err));
    }
    defer os.close(fd);

    if original_content, success := os.read_entire_file_from_handle(fd); success {
        width := 256;
        height := 50;

        buffer := FileBuffer {
            allocator = allocator,
            file_path = file_path,

            original_content = slice.clone_to_dynamic(original_content),
            added_content = make([dynamic]u8, 0, 1024*1024),
            content_slices = make([dynamic][]u8, 0, 1024*1024),

            glyph_buffer_width = width,
            glyph_buffer_height = height,
            glyph_buffer = make([dynamic]Glyph, width*height, width*height),

            input_buffer = make([dynamic]u8, 0, 1024),
        };

        append(&buffer.content_slices, buffer.original_content[:]);

        return buffer, error();
    } else {
        return FileBuffer{}, error(ErrorType.FileIOError, fmt.aprintf("failed to read from file"));
    }
}

update_glyph_buffer :: proc(buffer: ^FileBuffer) {
    for &glyph in buffer.glyph_buffer {
        glyph = Glyph{};
    }

    begin := buffer.top_line;
    rendered_col: int;
    rendered_line: int;

    it := new_file_buffer_iter(buffer);
    for character in iterate_file_buffer(&it) {
        if character == '\r' { continue; }

        screen_line := rendered_line - begin;
        // don't render past the screen
        if rendered_line >= begin && screen_line >= buffer.glyph_buffer_height { break; }

        // render INSERT mode text into glyph buffer
        if len(buffer.input_buffer) > 0 && rendered_line == buffer.cursor.line && rendered_col >= buffer.cursor.col && rendered_col < buffer.cursor.col + len(buffer.input_buffer) {
            for k in 0..<len(buffer.input_buffer) {
                screen_line = rendered_line - begin;

                if buffer.input_buffer[k] == '\n' {
                    rendered_col = 0;
                    rendered_line += 1;
                    continue;
                }

                if rendered_line >= begin && rendered_col < buffer.glyph_buffer_width {
                    buffer.glyph_buffer[rendered_col + screen_line * buffer.glyph_buffer_width].color = 0xFFFF;
                    buffer.glyph_buffer[rendered_col + screen_line * buffer.glyph_buffer_width].codepoint = buffer.input_buffer[k];

                    rendered_col += 1;
                }
            }
        }

        screen_line = rendered_line - begin;

        if character == '\n' {
            rendered_col = 0;
            rendered_line += 1;
            continue;
        }

        if rendered_line >= begin && rendered_col < buffer.glyph_buffer_width {
            buffer.glyph_buffer[rendered_col + screen_line * buffer.glyph_buffer_width] = Glyph { codepoint = character, color = 0 };
        }

        rendered_col += 1;
    }
}

draw_file_buffer :: proc(state: ^State, buffer: ^FileBuffer, x: int, y: int, font: raylib.Font) {
    update_glyph_buffer(buffer);

    begin := buffer.top_line;
    cursor_x := x + line_number_padding + buffer.cursor.col * source_font_width;
    cursor_y := y + buffer.cursor.line * source_font_height;

    cursor_y -= begin * source_font_height;
    if state.mode == .Normal {
        raylib.DrawRectangle(i32(cursor_x), i32(cursor_y), source_font_width, source_font_height, raylib.BLUE);
    } else if state.mode == .Insert {
        raylib.DrawRectangle(i32(cursor_x), i32(cursor_y), source_font_width, source_font_height, raylib.GREEN);
        raylib.DrawRectangle(i32(cursor_x + len(buffer.input_buffer) * source_font_width), i32(cursor_y), source_font_width, source_font_height, raylib.BLUE);
    }

    for j in 0..<buffer.glyph_buffer_height {
        text_y := y + source_font_height * j;

        // Line Numbers
        raylib.DrawTextEx(font, raylib.TextFormat("%d", begin + j + 1), raylib.Vector2 { f32(x), f32(text_y) }, source_font_height, 0, raylib.DARKGRAY);

        for i in 0..<buffer.glyph_buffer_width {
            text_x := x + line_number_padding + i * source_font_width;
            glyph := buffer.glyph_buffer[i + j * buffer.glyph_buffer_width];

            if glyph.codepoint == 0 { break; }

            raylib.DrawTextCodepoint(font, rune(glyph.codepoint), raylib.Vector2 { f32(text_x), f32(text_y) }, source_font_height, raylib.LIGHTGRAY);
        }
    }
}

scroll_file_buffer :: proc(buffer: ^FileBuffer, dir: ScrollDir) {
    switch dir {
        case .Up:
        {
            if buffer.top_line > 0 {
                buffer.top_line -= 20;

                if buffer.top_line < 0 {
                    buffer.top_line = 0;
                }
            }

            if buffer.cursor.line >= buffer.top_line + buffer.glyph_buffer_height - 4 {
                buffer.cursor.line = buffer.top_line + buffer.glyph_buffer_height - 1 - 4;
            }
        }
        case .Down:
        {
            buffer.top_line += 20;
            // TODO: check if top_line has gone past end of document

            if buffer.cursor.line < buffer.top_line + 4 {
                buffer.cursor.line = buffer.top_line + 4;
            }
        }
    }
}

// TODO: use buffer list in state
do_normal_mode :: proc(state: ^State, buffer: ^FileBuffer) {
    if raylib.IsKeyPressed(.I) {
        state.mode = .Insert;
        return;
    }

    if raylib.IsKeyPressed(.K) {
        move_cursor_up(buffer);
    }
    if raylib.IsKeyPressed(.J) {
        move_cursor_down(buffer);
    }
    if raylib.IsKeyPressed(.H) {
        move_cursor_left(buffer);
    }
    if raylib.IsKeyPressed(.L) {
        move_cursor_right(buffer);
    }

    if raylib.IsKeyDown(.LEFT_CONTROL) && raylib.IsKeyDown(.U) {
        scroll_file_buffer(buffer, .Up);
    }
    if raylib.IsKeyDown(.LEFT_CONTROL) && raylib.IsKeyDown(.D) {
        scroll_file_buffer(buffer, .Down);
    }
}

insert_content :: proc(buffer: ^FileBuffer, to_be_inserted: []u8) {
    if len(to_be_inserted) == 0 {
        return;
    }

    // TODO: is this even needed? would mean that the cursor isn't always in a valid state.
    update_file_buffer_index_from_cursor(buffer);
    before_it := new_file_buffer_iter(buffer, buffer.cursor.buffer_index);

    length := append(&buffer.added_content, ..to_be_inserted);
    inserted_slice: []u8 = buffer.added_content[len(buffer.added_content)-length:];

    if before_it.index.content_index == 0 {
        // insertion happening in beginning of content slice

        inject_at(&buffer.content_slices, 0, inserted_slice);
    }
    else {
        // insertion is happening in middle of content slice

        // cut current slice
        end_slice := buffer.content_slices[before_it.index.slice_index][before_it.index.content_index:];
        buffer.content_slices[before_it.index.slice_index] = buffer.content_slices[before_it.index.slice_index][:before_it.index.content_index];

        inject_at(&buffer.content_slices, before_it.index.slice_index+1, inserted_slice);
        inject_at(&buffer.content_slices, before_it.index.slice_index+2, end_slice);
    }

    update_file_buffer_index_from_cursor(buffer);
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

        insert_content(buffer, buffer.input_buffer[:]);
        runtime.clear(&buffer.input_buffer);
        return;
    }
}

main :: proc() {
    raylib.InitWindow(640, 480, "odin_editor - [back to basics]");
    raylib.SetWindowState({ .WINDOW_RESIZABLE, .VSYNC_HINT });
    raylib.SetTargetFPS(60);
    raylib.SetExitKey(.KEY_NULL);

    font := raylib.LoadFont("../c_editor/Mx437_ToshibaSat_8x16.ttf");
    state: State;

    buffer, err := new_file_buffer(context.allocator, "./src/main.odin");
    if err.type != .None {
        fmt.println("Failed to create file buffer:", err);
        os.exit(1);
    }

    for !raylib.WindowShouldClose() {
        {
            raylib.BeginDrawing();
            defer raylib.EndDrawing();

            raylib.ClearBackground(raylib.GetColor(0x232136ff));
            draw_file_buffer(&state, &buffer, 0, 32, font);
            raylib.DrawTextEx(font, raylib.TextFormat("Line: %d, Col: %d", buffer.cursor.line + 1, buffer.cursor.col + 1), raylib.Vector2 { 0, 0 }, source_font_height, 0, raylib.DARKGRAY);
        }

        switch state.mode {
            case .Normal:
                do_normal_mode(&state, &buffer);
            case .Insert:
                do_insert_mode(&state, &buffer);
        }
    }
}
