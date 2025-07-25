package core

import "core:fmt"

import ts "../tree_sitter"
import "../theme"

GlyphBuffer :: struct {
    buffer: []Glyph,
    width: int,
    height: int,
}

Glyph :: struct {
    codepoint: u8,
    color: theme.PaletteColor,
}

make_glyph_buffer :: proc(width, height: int, allocator := context.allocator) -> GlyphBuffer {
    context.allocator = allocator

    return GlyphBuffer {
        width = width,
        height = height,
        buffer = make([]Glyph, width*height)
    }
}

update_glyph_buffer_from_file_buffer :: proc(buffer: ^FileBuffer, width, height: int) {
    // TODO: limit to 256
    buffer.glyphs.width = width
    buffer.glyphs.height = height

    for &glyph in buffer.glyphs.buffer {
        glyph = Glyph {}
        glyph.color = .Foreground
    }

    outer: for highlight in buffer.tree.highlights {
        for line in highlight.start.row..=highlight.end.row {
            if int(line) < buffer.top_line { continue; }

            screen_line := int(line) - buffer.top_line
            if screen_line >= buffer.glyphs.height { break outer; }

            for col in highlight.start.column..<highlight.end.column {
                buffer.glyphs.buffer[int(col) + screen_line * buffer.glyphs.width].color = highlight.color;
            }
        }
    }

    begin := buffer.top_line;
    rendered_col: int;
    rendered_line: int;

    it := new_file_buffer_iter(buffer);
    for character in iterate_file_buffer(&it) {
        if character == '\r' { continue; }

        screen_line := rendered_line - begin;
        // don't render past the screen
        if rendered_line >= begin && screen_line >= buffer.glyphs.height { break; }

        // NOTE: `input_buffer` doesn't exist anymore, but this is a nice reference for just inserting text within the glyph buffer
        //
        // if len(buffer.input_buffer) > 0 && rendered_line == buffer.history.cursor.line && rendered_col >= buffer.history.cursor.col && rendered_col < buffer.history.cursor.col + len(buffer.input_buffer) {
        //     for k in 0..<len(buffer.input_buffer) {
        //         screen_line = rendered_line - begin;

        //         if buffer.input_buffer[k] == '\n' {
        //             rendered_col = 0;
        //             rendered_line += 1;
        //             continue;
        //         }

        //         if rendered_line >= begin && rendered_col < buffer.glyphs.width {
        //             buffer.glyphs.buffer[rendered_col + screen_line * buffer.glyphs.width].color = .Foreground;
        //             buffer.glyphs.buffer[rendered_col + screen_line * buffer.glyphs.width].codepoint = buffer.input_buffer[k];

        //             rendered_col += 1;
        //         }
        //     }
        // }

        screen_line = rendered_line - begin;

        if character == '\n' {
            rendered_col = 0;
            rendered_line += 1;
            continue;
        }

        if rendered_line >= begin && rendered_col < buffer.glyphs.width {
            buffer.glyphs.buffer[rendered_col + screen_line * buffer.glyphs.width].codepoint = character
        }

        rendered_col += 1;
    }
}

update_glyph_buffer_from_bytes :: proc(glyphs: ^GlyphBuffer, data: []u8, top_line: int) {
    for &glyph in glyphs.buffer {
        glyph = Glyph{};
    }

    begin := top_line;
    rendered_col: int;
    rendered_line: int;

    for character in data {
        if character == '\r' { continue; }

        screen_line := rendered_line - begin;
        // don't render past the screen
        if rendered_line >= begin && screen_line >= glyphs.height { break; }

        screen_line = rendered_line - begin;

        if character == '\n' {
            rendered_col = 0;
            rendered_line += 1;
            continue;
        }

        if rendered_line >= begin && rendered_col < glyphs.width {
            glyphs.buffer[rendered_col + screen_line * glyphs.width] = Glyph { codepoint = character, color = .Foreground };
        }

        rendered_col += 1;
    }
}

update_glyph_buffer :: proc{update_glyph_buffer_from_file_buffer, update_glyph_buffer_from_bytes}

draw_glyph_buffer :: proc(state: ^State, glyphs: ^GlyphBuffer, x: int, y: int, top_line: int, show_line_numbers: bool = true) {
    padding := 0;
    if show_line_numbers {
        padding = state.source_font_width * 5;
    }

    for j in 0..<glyphs.height {
        text_y := y + state.source_font_height * j;

        if show_line_numbers {
            draw_text(state, fmt.tprintf("%d", top_line + j + 1), x, text_y);
        }

        line_length := 0;
        for i in 0..<glyphs.width {
            text_x := x + padding + i * state.source_font_width;
            glyph := glyphs.buffer[i + j * glyphs.width];

            if glyph.codepoint == 0 { break; }
            line_length += 1;

            draw_codepoint(state, rune(glyph.codepoint), text_x, text_y, glyph.color);
        }
    }
}