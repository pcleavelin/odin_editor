package main

import "core:os"
import "core:math"
import "core:strings"
import "core:runtime"
import "core:fmt"
import "core:mem"
import "core:slice"
import "vendor:raylib"

source_font_width :: 8*2;
source_font_height :: 16*2;
line_number_padding :: 5 * source_font_width;

PaletteColor :: enum {
    Background,
    Foreground,

    Background1,
    Background2,
    Background3,
    Background4,

    Foreground1,
    Foreground2,
    Foreground3,
    Foreground4,

    Red,
    Green,
    Yellow,
    Blue,
    Purple,
    Aqua,
    Gray,

    BrightRed,
    BrightGreen,
    BrightYellow,
    BrightBlue,
    BrightPurple,
    BrightAqua,
    BrightGray,
}

// Its the gruvbox dark theme <https://github.com/morhetz/gruvbox>
palette := []u32 {
    0x282828ff,
    0xebdbb2ff,

    0x3c3836ff,
    0x504945ff,
    0x665c54ff,
    0x7c6f64ff,

    0xfbf1c7ff,
    0xebdbb2ff,
    0xd5c4a1ff,
    0xbdae93ff,

    0xcc241dff,
    0x98981aff,
    0xd79921ff,
    0x458588ff,
    0xb16286ff,
    0x689d6aff,
    0xa89984ff,

    0xfb4934ff,
    0xb8bb26ff,
    0xfabd2fff,
    0x83a598ff,
    0xd3869bff,
    0x8ec07cff,
    0x928374ff,
};

get_palette_raylib_color :: proc(palette_color: PaletteColor) -> raylib.Color {
    return raylib.GetColor(palette[palette_color]);
}

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
    index: FileBufferIndex,
}

Glyph :: struct #packed {
    codepoint: u8,
    color: PaletteColor,
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
    cursor: Cursor,
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
new_file_buffer_iter_with_cursor :: proc(file_buffer: ^FileBuffer, cursor: Cursor) -> FileBufferIter {
    return FileBufferIter { buffer = file_buffer, cursor = cursor };
}
new_file_buffer_iter :: proc{new_file_buffer_iter_from_beginning, new_file_buffer_iter_with_cursor};

iterate_file_buffer :: proc(it: ^FileBufferIter) -> (character: u8, idx: FileBufferIndex, cond: bool) {
    if it.cursor.index.slice_index >= len(it.buffer.content_slices) || it.cursor.index.content_index >= len(it.buffer.content_slices[it.cursor.index.slice_index]) {
        return;
    }
    cond = true;

    character = it.buffer.content_slices[it.cursor.index.slice_index][it.cursor.index.content_index];
    if it.cursor.index.content_index < len(it.buffer.content_slices[it.cursor.index.slice_index])-1 {
        it.cursor.index.content_index += 1;
    } else if it.cursor.index.slice_index < len(it.buffer.content_slices)-1 {
        it.cursor.index.content_index = 0;
        it.cursor.index.slice_index += 1;
    } else {
        return character, it.cursor.index, false;
    }

    if character == '\n' {
        it.cursor.col = 0;
        it.cursor.line += 1;
    } else {
        it.cursor.col += 1;
    }

    return character, it.cursor.index, true;
}
// NOTE: This give the character for the NEXT position, unlike the non-reverse version
// which gives the character for the CURRENT position.
iterate_file_buffer_reverse_mangle_cursor :: proc(it: ^FileBufferIter) -> (character: u8, idx: FileBufferIndex, cond: bool) {
    if it.cursor.index.content_index == 0 {
        if it.cursor.index.slice_index > 0 {
            it.cursor.index.slice_index -= 1;
            it.cursor.index.content_index = len(it.buffer.content_slices[it.cursor.index.slice_index])-1;
        } else {
            return 0, it.cursor.index, false;
        }
    } else {
        it.cursor.index.content_index -= 1;
    }

    return it.buffer.content_slices[it.cursor.index.slice_index][it.cursor.index.content_index], it.cursor.index, true;
}
iterate_file_buffer_reverse :: proc(it: ^FileBufferIter) -> (character: u8, idx: FileBufferIndex, cond: bool) {
    if character, idx, cond = iterate_file_buffer_reverse_mangle_cursor(it); cond {
       if character == '\n' {
           if it.cursor.line > 0 {
               line_length := file_buffer_line_length(it.buffer, it.cursor.index);
               if line_length < 0 { line_length = 0; }

               it.cursor.line -= 1;
               it.cursor.col = line_length;
           } else {
               return 0, it.cursor.index, false;
           }
       } else {
           it.cursor.col -= 1;
       }
    }

    return character, it.cursor.index, cond;
}

get_character_at_iter :: proc(it: FileBufferIter) -> u8 {
    return it.buffer.content_slices[it.cursor.index.slice_index][it.cursor.index.content_index];
}

IterProc :: proc(it: ^FileBufferIter) -> (character: u8, idx: FileBufferIndex, cond: bool);
UntilProc :: proc(it: ^FileBufferIter, iter_proc: IterProc) -> bool;

iterate_file_buffer_until :: proc(it: ^FileBufferIter, until_proc: UntilProc) {
    for until_proc(it, iterate_file_buffer) {}
}
iterate_file_buffer_until_reverse :: proc(it: ^FileBufferIter, until_proc: UntilProc) {
    for until_proc(it, iterate_file_buffer_reverse) {}
}

until_non_whitespace :: proc(it: ^FileBufferIter, iter_proc: IterProc) -> bool {
    if character, _, cond := iter_proc(it); cond && strings.is_space(rune(character)) {
        return false;
    }

    return true;
}

until_non_alpha_num :: proc(it: ^FileBufferIter, iter_proc: IterProc) -> bool {
    // TODO: make this global
    set, _ := strings.ascii_set_make("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_");

    peek_it := it^;
    if character, _, cond := iter_proc(&peek_it); cond && strings.ascii_set_contains(set, character) {
        it^ = peek_it;
        return true;
    }

    return false;
}

until_end_of_word :: proc(it: ^FileBufferIter, iter_proc: IterProc) -> bool {
    set, _ := strings.ascii_set_make("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_");

    if character, _, cond := iter_proc(it); cond && !strings.ascii_set_contains(set, character) && !strings.is_space(rune(character)) {
        for until_non_whitespace(it, iter_proc) {}
        return false;
    }

    for until_non_alpha_num(it, iter_proc) {}
    return false;
}

until_double_quote :: proc(it: ^FileBufferIter, iter_proc: IterProc) -> bool {
    before_it := it^;
    character, _, cond := iter_proc(it);
    if !cond { return cond; }

    // skip over escaped characters
    if character == '\\' {
        _, _, cond = iter_proc(it);
    } else if character == '"' {
        it^ = before_it;
        return false;
    }

    return cond;
}

until_single_quote :: proc(it: ^FileBufferIter, iter_proc: IterProc) -> bool {
    before_it := it^;
    character, _, cond := iter_proc(it);
    if !cond { return cond; }

    // skip over escaped characters
    if character == '\\' {
        _, _, cond = iter_proc(it);
    } else if character == '\'' {
        it^ = before_it;
        return false;
    }

    return cond;
}

until_line_break :: proc(it: ^FileBufferIter, iter_proc: IterProc) -> (cond: bool) {
    if it.buffer.content_slices[it.cursor.index.slice_index][it.cursor.index.content_index] == '\n' {
        return false;
    }

    _, _, cond = iter_proc(it);
    return cond;
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

    // FIXME: just swap cursors
    buffer.cursor.index = before_it.cursor.index;
}

file_buffer_line_length :: proc(buffer: ^FileBuffer, index: FileBufferIndex) -> int {
    line_length := 0;

    left_it := new_file_buffer_iter_with_cursor(buffer, Cursor { index = index });
    for character in iterate_file_buffer_reverse_mangle_cursor(&left_it) {
        if character == '\n' {
            break;
        }

        line_length += 1;
    }

    right_it := new_file_buffer_iter_with_cursor(buffer, Cursor { index = index });
    for character in iterate_file_buffer(&right_it) {
        if character == '\n' {
            break;
        }

        line_length += 1;
    }

    return line_length;
}

move_cursor_up :: proc(buffer: ^FileBuffer) {
    if buffer.cursor.line > 0 {
        current_line := buffer.cursor.line;
        current_col := buffer.cursor.col;

        it := new_file_buffer_iter_with_cursor(buffer, buffer.cursor);
        for _ in iterate_file_buffer_reverse(&it) {
            if it.cursor.line <= current_line-1 {
                break;
            }
        }

        // the `it.cursor.col > 0` is here because after the above loop, the
        // iterator is left on the new line instead of the last character of the line
        if it.cursor.col > current_col || it.cursor.col > 0 {
            for _ in iterate_file_buffer_reverse(&it) {
                if it.cursor.col <= current_col {
                    break;
                }
            }
        }

        buffer.cursor = it.cursor;

        if buffer.cursor.line < buffer.top_line + 5 && buffer.cursor.line >= 4 {
            buffer.top_line = buffer.cursor.line - 4;
        }
    }
}

move_cursor_down :: proc(buffer: ^FileBuffer) {
    current_line := buffer.cursor.line;
    current_col := buffer.cursor.col;

    it := new_file_buffer_iter_with_cursor(buffer, buffer.cursor);
    for _ in iterate_file_buffer(&it) {
        if it.cursor.line >= current_line+1 {
            break;
        }
    }

    line_length := file_buffer_line_length(buffer, it.cursor.index);
    if it.cursor.col < line_length && it.cursor.col < current_col {
        for _ in iterate_file_buffer(&it) {
            if it.cursor.col >= line_length-1 || it.cursor.col >= current_col {
                break;
            }
        }
    }

    buffer.cursor = it.cursor;

    if buffer.cursor.line > buffer.top_line + (buffer.glyph_buffer_height - 5) {
        buffer.top_line = buffer.cursor.line - (buffer.glyph_buffer_height - 5);
    }
}

move_cursor_left :: proc(buffer: ^FileBuffer) {
    if buffer.cursor.col > 0 {
        buffer.cursor.col -= 1;
        update_file_buffer_index_from_cursor(buffer);
    }
}

move_cursor_right :: proc(buffer: ^FileBuffer) {
    line_length := file_buffer_line_length(buffer, buffer.cursor.index);

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
        height := 256;

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

color_character :: proc(buffer: ^FileBuffer, start: Cursor, end: Cursor, palette_index: PaletteColor) {
    start, end := start, end;

    if end.line < buffer.top_line { return; }
    if start.line < buffer.top_line {
        start.line = 0;
    } else {
        start.line -= buffer.top_line;
    }

    if end.line >= buffer.top_line + buffer.glyph_buffer_height {
        end.line = buffer.glyph_buffer_height - 1;
        end.col = buffer.glyph_buffer_width - 1;
    } else {
        end.line -= buffer.top_line;
    }

    for j in start.line..=end.line {
        start_col := start.col;
        end_col := end.col;
        if j > start.line && j < end.line {
            start_col = 0;
            end_col = buffer.glyph_buffer_width;
        } else if j < end.line {
            end_col = buffer.glyph_buffer_width;
        } else if j > start.line && j == end.line {
            start_col = 0;
        }

        for i in start_col..<math.min(end_col+1, buffer.glyph_buffer_width) {
            buffer.glyph_buffer[i + j * buffer.glyph_buffer_width].color = palette_index;
        }
    }
}

color_buffer :: proc(buffer: ^FileBuffer) {
    start_it := new_file_buffer_iter(buffer);
    it := new_file_buffer_iter(buffer);

    for character in iterate_file_buffer(&it) {
        if it.cursor.line > it.buffer.glyph_buffer_height && (it.cursor.line - it.buffer.top_line) > it.buffer.glyph_buffer_height {
            break;
        }

        if character == '/' {
            start_it = it;
            // need to go back one character because `it` is on the next character
            iterate_file_buffer_reverse(&start_it);

            character, _, succ := iterate_file_buffer(&it);
            if !succ { break; }

            if character == '/' {
                iterate_file_buffer_until(&it, until_line_break);
                color_character(buffer, start_it.cursor, it.cursor, .Foreground4);
            } else if character == '*' {
                // TODO: block comments
            }
        } else if character == '\'' {
            start_it = it;
            // need to go back one character because `it` is on the next character
            iterate_file_buffer_reverse(&start_it);

            // jump into the quoted text
            iterate_file_buffer_until(&it, until_single_quote);
            color_character(buffer, start_it.cursor, it.cursor, .Yellow);

            iterate_file_buffer(&it);
        } else if character == '"' {
            start_it = it;
            // need to go back one character because `it` is on the next character
            iterate_file_buffer_reverse(&start_it);

            // jump into the quoted text
            iterate_file_buffer_until(&it, until_double_quote);
            color_character(buffer, start_it.cursor, it.cursor, .Yellow);

            iterate_file_buffer(&it);
        } else if (character >= 'a' && character <= 'z') || (character >= 'A' && character <= 'Z') || character == '_' {
            start_it = it;
            // need to go back one character because `it` is on the next character
            iterate_file_buffer_reverse(&start_it);
            it = start_it;

            iterate_file_buffer_until(&it, until_end_of_word);

            end_of_word_it := it;
            _, _, succ := iterate_file_buffer_reverse(&end_of_word_it);
            if !succ { break; }

            // TODO: color keywords

            if character, _, cond := iterate_file_buffer(&it); cond {
                if character == '(' {
                    color_character(buffer, start_it.cursor, end_of_word_it.cursor, .Green);
                }
            } else {
                break;
            }
        }
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
                    buffer.glyph_buffer[rendered_col + screen_line * buffer.glyph_buffer_width].color = .Foreground;
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
            buffer.glyph_buffer[rendered_col + screen_line * buffer.glyph_buffer_width] = Glyph { codepoint = character, color = .Foreground };
        }

        rendered_col += 1;
    }
}

draw_file_buffer :: proc(state: ^State, buffer: ^FileBuffer, x: int, y: int, font: raylib.Font) {
    update_glyph_buffer(buffer);
    color_buffer(buffer);

    begin := buffer.top_line;
    cursor_x := x + line_number_padding + buffer.cursor.col * source_font_width;
    cursor_y := y + buffer.cursor.line * source_font_height;

    cursor_y -= begin * source_font_height;

    // draw cursor
    if state.mode == .Normal {
        raylib.DrawRectangle(i32(cursor_x), i32(cursor_y), source_font_width, source_font_height, raylib.BLUE);
    } else if state.mode == .Insert {
        raylib.DrawRectangle(i32(cursor_x), i32(cursor_y), source_font_width, source_font_height, raylib.GREEN);

        num_line_break := 0;
        line_length := 0;
        for c in buffer.input_buffer {
            if c == '\n' {
                num_line_break += 1;
                line_length = 0;
            } else {
                line_length += 1;
            }
        }

        if num_line_break > 0 {
            cursor_x = x + line_number_padding + line_length * source_font_width;
            cursor_y = cursor_y + num_line_break * source_font_height;
        } else {
            cursor_x += line_length * source_font_width;
        }

        raylib.DrawRectangle(i32(cursor_x), i32(cursor_y), source_font_width, source_font_height, raylib.BLUE);
    }

    for j in 0..<buffer.glyph_buffer_height {
        text_y := y + source_font_height * j;

        // Line Numbers
        raylib.DrawTextEx(font, raylib.TextFormat("%d", begin + j + 1), raylib.Vector2 { f32(x), f32(text_y) }, source_font_height, 0, raylib.DARKGRAY);

        for i in 0..<buffer.glyph_buffer_width {
            text_x := x + line_number_padding + i * source_font_width;
            glyph := buffer.glyph_buffer[i + j * buffer.glyph_buffer_width];

            if glyph.codepoint == 0 { break; }

            raylib.DrawTextCodepoint(font, rune(glyph.codepoint), raylib.Vector2 { f32(text_x), f32(text_y) }, source_font_height, raylib.GetColor(palette[glyph.color]));
        }
    }
}

// TODO: don't mangle cursor
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

    update_file_buffer_index_from_cursor(buffer);
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
    it := new_file_buffer_iter(buffer, buffer.cursor);

    length := append(&buffer.added_content, ..to_be_inserted);
    inserted_slice: []u8 = buffer.added_content[len(buffer.added_content)-length:];

    if it.cursor.index.content_index == 0 {
        // insertion happening in beginning of content slice

        inject_at(&buffer.content_slices, buffer.cursor.index.slice_index, inserted_slice);
    }
    else {
        // insertion is happening in middle of content slice

        // cut current slice
        end_slice := buffer.content_slices[it.cursor.index.slice_index][it.cursor.index.content_index:];
        buffer.content_slices[it.cursor.index.slice_index] = buffer.content_slices[it.cursor.index.slice_index][:it.cursor.index.content_index];

        inject_at(&buffer.content_slices, it.cursor.index.slice_index+1, inserted_slice);
        inject_at(&buffer.content_slices, it.cursor.index.slice_index+2, end_slice);
    }

    update_file_buffer_index_from_cursor(buffer);
}

// TODO: potentially add FileBufferIndex as parameter
split_content_slice :: proc(buffer: ^FileBuffer) {
    if buffer.cursor.index.content_index == 0 {
        return;
    }

    end_slice := buffer.content_slices[buffer.cursor.index.slice_index][buffer.cursor.index.content_index:];
    buffer.content_slices[buffer.cursor.index.slice_index] = buffer.content_slices[buffer.cursor.index.slice_index][:buffer.cursor.index.content_index];

    inject_at(&buffer.content_slices, buffer.cursor.index.slice_index+1, end_slice);

    // TODO: maybe move this out of this function
    buffer.cursor.index.slice_index += 1;
    buffer.cursor.index.content_index = 0;
}

delete_content :: proc(buffer: ^FileBuffer, amount: int) {
    if amount <= len(buffer.input_buffer) {
        runtime.resize(&buffer.input_buffer, len(buffer.input_buffer)-amount);
    } else {
        amount := amount - len(buffer.input_buffer);
        runtime.clear(&buffer.input_buffer);

        split_content_slice(buffer);

        it := new_file_buffer_iter_with_cursor(buffer, buffer.cursor);

        // go back one (to be at the end of the content slice)
        iterate_file_buffer_reverse(&it);

        for i in 0..<amount {
            content_slice_ptr := &buffer.content_slices[it.cursor.index.slice_index];

            if len(content_slice_ptr^) == 1 {
                // move cursor to previous content_slice so we can delete the current one
                iterate_file_buffer_reverse(&it);
                runtime.ordered_remove(&buffer.content_slices, it.cursor.index.slice_index+1);
            } else {
                iterate_file_buffer_reverse(&it);
                content_slice_ptr^ = content_slice_ptr^[:len(content_slice_ptr^)-1];
            }
        }

        iterate_file_buffer(&it);
        buffer.cursor = it.cursor;
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

        insert_content(buffer, buffer.input_buffer[:]);
        runtime.clear(&buffer.input_buffer);
        return;
    }

    if raylib.IsKeyPressed(.BACKSPACE) {
        delete_content(buffer, 1);
    }
}

main :: proc() {
    raylib.InitWindow(640, 480, "odin_editor - [back to basics]");
    raylib.SetWindowState({ .WINDOW_RESIZABLE, .VSYNC_HINT });
    raylib.SetTargetFPS(60);
    raylib.SetExitKey(.KEY_NULL);

    font := raylib.LoadFont("../c_editor/Mx437_ToshibaSat_8x16.ttf");
    state: State;
    buffer, err := new_file_buffer(context.allocator, os.args[1]);
    if err.type != .None {
        fmt.println("Failed to create file buffer:", err);
        os.exit(1);
    }

    for !raylib.WindowShouldClose() {
        screen_width := raylib.GetScreenWidth();
        screen_height := raylib.GetScreenHeight();
        buffer.glyph_buffer_height = math.min(256, int((screen_height - 32 - source_font_height) / source_font_height));

        {
            raylib.BeginDrawing();
            defer raylib.EndDrawing();

            raylib.ClearBackground(get_palette_raylib_color(.Background));
            draw_file_buffer(&state, &buffer, 32, 32, font);

            raylib.DrawRectangle(0, screen_height - source_font_height, screen_width, source_font_height, get_palette_raylib_color(.Background2));

            line_info_text := raylib.TextFormat("Line: %d, Col: %d --- Slice Index: %d, Content Index: %d", buffer.cursor.line + 1, buffer.cursor.col + 1, buffer.cursor.index.slice_index, buffer.cursor.index.content_index);
            line_info_width := raylib.MeasureTextEx(font, line_info_text, source_font_height, 0).x;

            switch state.mode {
                case .Normal:
                    raylib.DrawRectangle(0, screen_height - source_font_height, 8 + len("NORMAL")*source_font_width, source_font_height, get_palette_raylib_color(.Foreground4));
                    raylib.DrawRectangleV(raylib.Vector2 { f32(screen_width) - line_info_width - 8 , f32(screen_height - source_font_height) }, raylib.Vector2 { 8 + line_info_width, f32(source_font_height) }, get_palette_raylib_color(.Foreground4));

                    raylib.DrawTextEx(font, "NORMAL", raylib.Vector2 { 4, f32(screen_height - source_font_height) }, source_font_height, 0, get_palette_raylib_color(.Background1));
                case .Insert:
                    raylib.DrawRectangle(0, screen_height - source_font_height, 8 + len("INSERT")*source_font_width, source_font_height, raylib.SKYBLUE);
                    raylib.DrawRectangleV(raylib.Vector2 { f32(screen_width) - line_info_width - 8 , f32(screen_height - source_font_height) }, raylib.Vector2 { 8 + line_info_width, f32(source_font_height) }, raylib.SKYBLUE);

                    raylib.DrawTextEx(font, "INSERT", raylib.Vector2 { 4, f32(screen_height - source_font_height) }, source_font_height, 0, raylib.DARKBLUE);
            }


            raylib.DrawTextEx(font, line_info_text, raylib.Vector2 { f32(screen_width) - line_info_width - 4, f32(screen_height - source_font_height) }, source_font_height, 0, get_palette_raylib_color(.Background1));
        }

        switch state.mode {
            case .Normal:
                do_normal_mode(&state, &buffer);
            case .Insert:
                do_insert_mode(&state, &buffer);
        }
    }
}
