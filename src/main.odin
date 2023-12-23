package main

import "core:fmt"
import "core:mem"
import "vendor:raylib"

source_font_width :: 8;
source_font_height :: 16;
line_number_padding :: 4 * source_font_width;

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
    content_slices: [dynamic]ContentSlice,

    glyph_buffer_width: int,
    glyph_buffer_height: int,
    glyph_buffer: [dynamic]Glyph,

    input_buffer: [dynamic]u8,
}

FileBufferIter :: struct {
    index: FileBufferIndex,
    buffer: ^FileBuffer,
}

new_file_buffer_iter :: proc(file_buffer: ^FileBuffer) -> FileBufferIter {
    return FileBufferIter { buffer = file_buffer };
}
iterate_file_buffer :: proc(it: ^FileBufferIter) -> (character: u8, idx: FileBufferIndex, cond: bool) {
    if it.index.slice_index >= len(it.buffer.content_slices) || it.index.content_index >= len(it.buffer.content_slices[it.index.slice_index].slice) {
        return;
    }
    cond = true;

    character = it.buffer.content_slices[it.index.slice_index].slice[it.index.content_index];

    it.index.content_index += 1;
    if it.index.content_index >= len(it.buffer.content_slices[it.index.slice_index].slice) {
        it.index.content_index = 0;
        it.index.slice_index += 1;
    }

    return;
}

new_file_buffer :: proc(allocator: mem.Allocator, file_path: string) -> FileBuffer {
    context.allocator = allocator;

    width := 80;
    height := 24;

    test_str := "This is a test string\nfor a file buffer\nThis is line 3\nThis is line 4\n\n\nThis is line 7 (with some gaps between 4)";

    buffer := FileBuffer {
        allocator = allocator,
        file_path = file_path,

        original_content = make([dynamic]u8, 0, len(test_str)),
        added_content = make([dynamic]u8, 0, 1024*1024),
        content_slices = make([dynamic]ContentSlice, 0, 1024*1024),

        glyph_buffer_width = width,
        glyph_buffer_height = height,
        glyph_buffer = make([dynamic]Glyph, width*height, width*height),

        input_buffer = make([dynamic]u8, 0, 1024),
    };

    append(&buffer.original_content, test_str);
    append(&buffer.content_slices, ContentSlice { type = .Original, slice = buffer.original_content[:] });

    return buffer;
}

update_glyph_buffer :: proc(buffer: ^FileBuffer) {
    //mem.set(&buffer.glyph_buffer, 0, size_of(Glyph)*buffer.glyph_buffer_width*buffer.glyph_buffer_height);

    begin := buffer.top_line;
    rendered_col: int;
    rendered_line: int;

    it := new_file_buffer_iter(buffer);
    for character in iterate_file_buffer(&it) {
        if character == '\r' { continue; }

        line := rendered_line - begin;
        if rendered_line >= begin && line >= buffer.glyph_buffer_height { break; }

        if character == '\n' {
            rendered_col = 0;
            rendered_line += 1;
            continue;
        }

        if rendered_line >= begin && rendered_col < buffer.glyph_buffer_width {
            buffer.glyph_buffer[rendered_col + line * buffer.glyph_buffer_width] = Glyph { codepoint = character, color = 0 };
        }

        rendered_col += 1;
    }
}

draw_file_buffer :: proc(buffer: ^FileBuffer, x: int, y: int, font: raylib.Font) {
    update_glyph_buffer(buffer);

    begin := buffer.top_line;
    cursor_x := x + line_number_padding + buffer.cursor.col * source_font_width;
    cursor_y := y + buffer.cursor.line * source_font_height;

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

main :: proc() {
    raylib.InitWindow(640, 480, "odin_editor - [back to basics]");
    raylib.SetWindowState({ .WINDOW_RESIZABLE, .VSYNC_HINT });
    raylib.SetTargetFPS(60);
    raylib.SetExitKey(.KEY_NULL);

    font := raylib.LoadFont("../c_editor/Mx437_ToshibaSat_8x16.ttf");

    fmt.println("Hello");
    buffer := new_file_buffer(context.allocator, "./main.odin");
    update_glyph_buffer(&buffer);

    for !raylib.WindowShouldClose() {
        {
            raylib.BeginDrawing();
            defer raylib.EndDrawing();
            
            raylib.ClearBackground(raylib.GetColor(0x232136ff));

            draw_file_buffer(&buffer, 0, 0, font);
        }
    }
}
