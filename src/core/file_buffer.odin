package core;

import "core:os"
import "core:path/filepath"
import "core:mem"
import "core:fmt"
import "core:math"
import "core:slice"
import "core:runtime"
import "core:strings"
import "vendor:raylib"

import "../theme"

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
    color: theme.PaletteColor,
}

FileBuffer :: struct {
    allocator: mem.Allocator,

    directory: string,
    file_path: string,
    extension: string,

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
    hit_end: bool,
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
    } else if it.hit_end {
        return character, it.cursor.index, false;
    } else {
        it.hit_end = true;
        return character, it.cursor.index, true;
    }

    if character == '\n' {
        it.cursor.col = 0;
        it.cursor.line += 1;
    } else {
        it.cursor.col += 1;
    }

    return character, it.cursor.index, true;
}
iterate_file_buffer_reverse_mangle_cursor :: proc(it: ^FileBufferIter) -> (character: u8, idx: FileBufferIndex, cond: bool) {
    character = it.buffer.content_slices[it.cursor.index.slice_index][it.cursor.index.content_index];
    if it.cursor.index.content_index == 0 {
        if it.cursor.index.slice_index > 0 {
            it.cursor.index.slice_index -= 1;
            it.cursor.index.content_index = len(it.buffer.content_slices[it.cursor.index.slice_index])-1;
        } else if it.hit_end {
            return character, it.cursor.index, false;
        } else {
            it.hit_end = true;
            return character, it.cursor.index, true;
        }
    } else {
        it.cursor.index.content_index -= 1;
    }

    return character, it.cursor.index, true;
}
// TODO: figure out how to give the first character of the buffer
iterate_file_buffer_reverse :: proc(it: ^FileBufferIter) -> (character: u8, idx: FileBufferIndex, cond: bool) {
    if character, idx, cond = iterate_file_buffer_reverse_mangle_cursor(it); cond {
       if it.cursor.col < 1 {
           if it.cursor.line > 0 {
               line_length := file_buffer_line_length(it.buffer, it.cursor.index);
               if line_length < 0 { line_length = 0; }

               it.cursor.line -= 1;
               it.cursor.col = line_length;
           } else {
               return character, it.cursor.index, false;
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

iterate_peek :: proc(it: ^FileBufferIter, iter_proc: IterProc) -> (character: u8, peek_it: FileBufferIter, cond: bool) {
    peek_it = it^;
    character, _, cond = iter_proc(&peek_it);
    if !cond {
        return character, peek_it, cond;
    }

    character = get_character_at_iter(peek_it);
    return character, peek_it, cond;
}

until_non_whitespace :: proc(it: ^FileBufferIter, iter_proc: IterProc) -> bool {
    before_it := it^;

    if character, _, cond := iter_proc(it); cond && strings.is_space(rune(character)) {
        return cond;
    }

    it^ = before_it;
    return false;
}

until_before_non_whitespace :: proc(it: ^FileBufferIter, iter_proc: IterProc) -> bool {
    if character, peek_it, cond := iterate_peek(it, iter_proc); cond && strings.is_space(rune(character)) {
        it^ = peek_it;
        return true;
    }

    return false;
}

until_non_alpha_num :: proc(it: ^FileBufferIter, iter_proc: IterProc) -> bool {
    // TODO: make this global
    set, _ := strings.ascii_set_make("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_");
    before_it := it^;

    if character, _, cond := iter_proc(it); cond && strings.ascii_set_contains(set, character) {
        return cond;
    }

    it^ = before_it;
    return false;
}

until_before_non_alpha_num :: proc(it: ^FileBufferIter, iter_proc: IterProc) -> bool {
    // TODO: make this global
    set, _ := strings.ascii_set_make("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_");

    if character, peek_it, cond := iterate_peek(it, iter_proc); cond && strings.ascii_set_contains(set, character) {
        it^ = peek_it;
        return cond;
    }

    return false;
}

until_alpha_num :: proc(it: ^FileBufferIter, iter_proc: IterProc) -> bool {
    set, _ := strings.ascii_set_make("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_");
    before_it := it^;

    if character, _, cond := iter_proc(it); cond && !strings.ascii_set_contains(set, character) {
        return cond;
    }

    it^ = before_it;
    return false;
}

until_before_alpha_num :: proc(it: ^FileBufferIter, iter_proc: IterProc) -> bool {
    set, _ := strings.ascii_set_make("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_");

    if character, peek_it, cond := iterate_peek(it, iter_proc); cond && !strings.ascii_set_contains(set, character) {
        it^ = peek_it;
        return cond;
    }

    return false;
}

until_before_alpha_num_or_whitespace :: proc(it: ^FileBufferIter, iter_proc: IterProc) -> bool {
    set, _ := strings.ascii_set_make("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_");

    if character, peek_it, cond := iterate_peek(it, iter_proc); cond && (!strings.ascii_set_contains(set, character) && !strings.is_space(rune(character))) {
        it^ = peek_it;
        return cond;
    }

    return false;
}

until_start_of_word :: proc(it: ^FileBufferIter, iter_proc: IterProc) -> bool {
    set, _ := strings.ascii_set_make("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_");

    // if on a symbol go to next symbol or word
    current_character := get_character_at_iter(it^);
    if !strings.ascii_set_contains(set, current_character) && !strings.is_space(rune(current_character)) {
        _, _, cond := iter_proc(it);
        if !cond { return false; }

        for until_alpha_num(it, iter_proc) {}
        return false;
    }

    for until_non_alpha_num(it, iter_proc) {}
    for until_non_whitespace(it, iter_proc) {}

    return false;
}

until_end_of_word :: proc(it: ^FileBufferIter, iter_proc: IterProc) -> bool {
    set, _ := strings.ascii_set_make("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_");

    current_character := get_character_at_iter(it^);
    if character, peek_it, cond := iterate_peek(it, iter_proc); strings.ascii_set_contains(set, current_character) {
        // if current charater is a word

        if strings.is_space(rune(character)) {
            it^ = peek_it;
            for until_non_whitespace(it, iter_proc) {}
        }

        if strings.ascii_set_contains(set, character) {
            // we are within a word
            for until_before_non_alpha_num(it, iter_proc) {}
        } else {
            // we are at the start of a word
            for until_before_alpha_num_or_whitespace(it, iter_proc) {}
        }
    } else if character, peek_it, cond := iterate_peek(it, iter_proc); !strings.ascii_set_contains(set, current_character)  {
        // if current charater is a symbol

        if strings.is_space(rune(character)) {
            it^ = peek_it;
            for until_non_whitespace(it, iter_proc) {}

            character = get_character_at_iter(it^);
        }

        if !strings.ascii_set_contains(set, character) {
            // we are within a run of symbols
            for until_before_alpha_num_or_whitespace(it, iter_proc) {}
        } else {
            // we are at the start of a run of symbols
            for until_before_non_alpha_num(it, iter_proc) {}
        }
    }

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

    update_file_buffer_scroll(buffer);
}

file_buffer_line_length :: proc(buffer: ^FileBuffer, index: FileBufferIndex) -> int {
    line_length := 0;
    first_character := buffer.content_slices[index.slice_index][index.content_index];

    left_it := new_file_buffer_iter_with_cursor(buffer, Cursor { index = index });
    if first_character == '\n' {
        iterate_file_buffer_reverse_mangle_cursor(&left_it);
    }

    for character in iterate_file_buffer_reverse_mangle_cursor(&left_it) {
        if character == '\n' {
            break;
        }

        line_length += 1;
    }

    right_it := new_file_buffer_iter_with_cursor(buffer, Cursor { index = index });
    first := true;
    for character in iterate_file_buffer(&right_it) {
        if character == '\n' {
            break;
        }

        if !first {
            line_length += 1;
        }
        first = false;
    }

    return line_length;
}

move_cursor_start_of_line :: proc(buffer: ^FileBuffer) {
    if buffer.cursor.col > 0 {
        it := new_file_buffer_iter_with_cursor(buffer, buffer.cursor);
        for _ in iterate_file_buffer_reverse(&it) {
            if it.cursor.col <= 0 {
                break;
            }
        }

        buffer.cursor = it.cursor;
    }
}

move_cursor_end_of_line :: proc(buffer: ^FileBuffer) {
    it := new_file_buffer_iter_with_cursor(buffer, buffer.cursor);
    line_length := file_buffer_line_length(buffer, it.cursor.index);

    if buffer.cursor.col < line_length-1 {
        for _ in iterate_file_buffer(&it) {
            if it.cursor.col >= line_length-1 {
                break;
            }
        }

        buffer.cursor = it.cursor;
    }
}

move_cursor_up :: proc(buffer: ^FileBuffer, amount: int = 1) {
    if buffer.cursor.line > 0 {
        current_line := buffer.cursor.line;
        current_col := buffer.cursor.col;

        it := new_file_buffer_iter_with_cursor(buffer, buffer.cursor);
        for _ in iterate_file_buffer_reverse(&it) {
            if it.cursor.line <= current_line-amount || it.cursor.line < 1 {
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
    }

    update_file_buffer_scroll(buffer);
}

move_cursor_down :: proc(buffer: ^FileBuffer, amount: int = 1) {
    current_line := buffer.cursor.line;
    current_col := buffer.cursor.col;

    it := new_file_buffer_iter_with_cursor(buffer, buffer.cursor);
    for _ in iterate_file_buffer(&it) {
        if it.cursor.line >= current_line+amount {
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
    update_file_buffer_scroll(buffer);
}

move_cursor_left :: proc(buffer: ^FileBuffer) {
    if buffer.cursor.col > 0 {
        buffer.cursor.col -= 1;
        update_file_buffer_index_from_cursor(buffer);
    }
}

move_cursor_right :: proc(buffer: ^FileBuffer, stop_at_end: bool = true) {
    line_length := file_buffer_line_length(buffer, buffer.cursor.index);

    if !stop_at_end || (line_length > 0 && buffer.cursor.col < line_length-1) {
        buffer.cursor.col += 1;
        update_file_buffer_index_from_cursor(buffer);
    }
}

move_cursor_forward_start_of_word :: proc(buffer: ^FileBuffer) {
    it := new_file_buffer_iter_with_cursor(buffer, buffer.cursor);
    iterate_file_buffer_until(&it, until_start_of_word);
    buffer.cursor = it.cursor;

    update_file_buffer_scroll(buffer);
}

move_cursor_forward_end_of_word :: proc(buffer: ^FileBuffer) {
    it := new_file_buffer_iter_with_cursor(buffer, buffer.cursor);
    iterate_file_buffer_until(&it, until_end_of_word);
    buffer.cursor = it.cursor;

    update_file_buffer_scroll(buffer);
}

move_cursor_backward_start_of_word :: proc(buffer: ^FileBuffer) {
    it := new_file_buffer_iter_with_cursor(buffer, buffer.cursor);
    iterate_file_buffer_until_reverse(&it, until_end_of_word);
    //iterate_file_buffer_until(&it, until_non_whitespace);
    buffer.cursor = it.cursor;

    update_file_buffer_scroll(buffer);
}

move_cursor_backward_end_of_word :: proc(buffer: ^FileBuffer) {
    it := new_file_buffer_iter_with_cursor(buffer, buffer.cursor);
    iterate_file_buffer_until_reverse(&it, until_start_of_word);
    buffer.cursor = it.cursor;

    update_file_buffer_scroll(buffer);
}

new_virtual_file_buffer :: proc(allocator: mem.Allocator) -> FileBuffer {
    context.allocator = allocator;
    width := 256;
    height := 256;

    buffer := FileBuffer {
        allocator = allocator,
        file_path = "virtual_buffer",

        original_content = slice.clone_to_dynamic([]u8{'\n'}),
        added_content = make([dynamic]u8, 0, 1024*1024),
        content_slices = make([dynamic][]u8, 0, 1024*1024),

        glyph_buffer_width = width,
        glyph_buffer_height = height,
        glyph_buffer = make([dynamic]Glyph, width*height, width*height),

        input_buffer = make([dynamic]u8, 0, 1024),
    };

    append(&buffer.content_slices, buffer.original_content[:]);

    return buffer;
}

new_file_buffer :: proc(allocator: mem.Allocator, file_path: string, base_dir: string = "") -> (FileBuffer, Error) {
    context.allocator = allocator;

    fd, err := os.open(file_path);
    if err != os.ERROR_NONE {
        return FileBuffer{}, make_error(ErrorType.FileIOError, fmt.aprintf("failed to open file: errno=%x", err));
    }
    defer os.close(fd);

    fi, fstat_err := os.fstat(fd);
    if fstat_err > 0 {
        return FileBuffer{}, make_error(ErrorType.FileIOError, fmt.aprintf("failed to get file info: errno=%x", fstat_err));
    }

    dir: string;
    if base_dir != "" {
        dir = base_dir;
    } else {
        dir = filepath.dir(fi.fullpath);
    }

    extension := filepath.ext(fi.fullpath);

    if original_content, success := os.read_entire_file_from_handle(fd); success {
        width := 256;
        height := 256;

        buffer := FileBuffer {
            allocator = allocator,
            directory = dir,
            file_path = fi.fullpath,
            extension = extension,

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

free_file_buffer :: proc(buffer: ^FileBuffer) {
    delete(buffer.original_content);
    delete(buffer.added_content);
    delete(buffer.content_slices);
    delete(buffer.glyph_buffer);
    delete(buffer.input_buffer);
}

is_keyword :: proc(start: FileBufferIter, end: FileBufferIter) -> (matches: bool) {
    keywords := []string {
        "using",
        "transmute",
        "cast",
        "distinct",
        "opaque",
        "where",
        "struct",
        "enum",
        "union",
        "bit_field",
        "bit_set",
        "if",
        "when",
        "else",
        "do",
        "for",
        "switch",
        "case",
        "continue",
        "break",
        "size_of",
        "offset_of",
        "type_info_of",
        "typeid_of",
        "type_of",
        "align_of",
        "or_return",
        "or_else",
        "inline",
        "no_inline",
        "string",
        "cstring",
        "bool",
        "b8",
        "b16",
        "b32",
        "b64",
        "rune",
        "any",
        "rawptr",
        "f16",
        "f32",
        "f64",
        "f16le",
        "f16be",
        "f32le",
        "f32be",
        "f64le",
        "f64be",
        "u8",
        "u16",
        "u32",
        "u64",
        "u128",
        "u16le",
        "u32le",
        "u64le",
        "u128le",
        "u16be",
        "u32be",
        "u64be",
        "u128be",
        "uint",
        "uintptr",
        "i8",
        "i16",
        "i32",
        "i64",
        "i128",
        "i16le",
        "i32le",
        "i64le",
        "i128le",
        "i16be",
        "i32be",
        "i64be",
        "i128be",
        "int",
        "complex",
        "complex32",
        "complex64",
        "complex128",
        "quaternion",
        "quaternion64",
        "quaternion128",
        "quaternion256",
        "matrix",
        "typeid",
        "true",
        "false",
        "nil",
        "dynamic",
        "map",
        "proc",
        "in",
        "notin",
        "not_in",
        "import",
        "export",
        "foreign",
        "const",
        "package",
        "return",
        "defer",
    };

    for keyword in keywords {
        it := start;
        keyword_index := 0;

        for character in iterate_file_buffer(&it) {
            if character != keyword[keyword_index] {
                break;
            }

            keyword_index += 1;
            if keyword_index >= len(keyword)-1 && it == end {
                if get_character_at_iter(it) == keyword[keyword_index] {
                    matches = true;
                }

                break;
            } else if keyword_index >= len(keyword)-1 {
                break;
            } else if it == end {
                break;
            }
        }

        if matches {
            break;
        }
    }

    return;
}

color_character :: proc(buffer: ^FileBuffer, start: Cursor, end: Cursor, palette_index: theme.PaletteColor) {
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

            // TODO: color keywords
            if is_keyword(start_it, it) {
                color_character(buffer, start_it.cursor, it.cursor, .Blue);
            } else if character, _, cond := iterate_peek(&it, iterate_file_buffer); cond {
                if character == '(' {
                    color_character(buffer, start_it.cursor, it.cursor, .Green);
                }
            } else {
                break;
            }

            iterate_file_buffer(&it);
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

draw_file_buffer :: proc(state: ^State, buffer: ^FileBuffer, x: int, y: int, font: raylib.Font, show_line_numbers: bool = true) {
    update_glyph_buffer(buffer);
    if highlighter, exists := state.highlighters[buffer.extension]; exists {
        highlighter(state.plugin_vtable, buffer);
    }

    padding := 0;
    if show_line_numbers {
        padding = state.source_font_width * 5;
    }

    begin := buffer.top_line;
    cursor_x := x + padding + buffer.cursor.col * state.source_font_width;
    cursor_y := y + buffer.cursor.line * state.source_font_height;

    cursor_y -= begin * state.source_font_height;

    // draw cursor
    if state.mode == .Normal {
        raylib.DrawRectangle(i32(cursor_x), i32(cursor_y), i32(state.source_font_width), i32(state.source_font_height), theme.get_palette_raylib_color(.Background4));
    } else if state.mode == .Insert {
        raylib.DrawRectangle(i32(cursor_x), i32(cursor_y), i32(state.source_font_width), i32(state.source_font_height), theme.get_palette_raylib_color(.Green));

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
            cursor_x = x + padding + line_length * state.source_font_width;
            cursor_y = cursor_y + num_line_break * state.source_font_height;
        } else {
            cursor_x += line_length * state.source_font_width;
        }

        raylib.DrawRectangle(i32(cursor_x), i32(cursor_y), i32(state.source_font_width), i32(state.source_font_height), theme.get_palette_raylib_color(.Blue));
    }

    for j in 0..<buffer.glyph_buffer_height {
        text_y := y + state.source_font_height * j;

        if show_line_numbers {
            raylib.DrawTextEx(font, raylib.TextFormat("%d", begin + j + 1), raylib.Vector2 { f32(x), f32(text_y) }, f32(state.source_font_height), 0, theme.get_palette_raylib_color(.Background3));
        }

        for i in 0..<buffer.glyph_buffer_width {
            text_x := x + padding + i * state.source_font_width;
            glyph := buffer.glyph_buffer[i + j * buffer.glyph_buffer_width];

            if glyph.codepoint == 0 { break; }

            raylib.DrawTextCodepoint(font, rune(glyph.codepoint), raylib.Vector2 { f32(text_x), f32(text_y) }, f32(state.source_font_height), theme.get_palette_raylib_color(glyph.color));
        }
    }
}

update_file_buffer_scroll :: proc(buffer: ^FileBuffer) {
    if buffer.cursor.line > (buffer.top_line + buffer.glyph_buffer_height - 5) {
        buffer.top_line = math.max(buffer.cursor.line - buffer.glyph_buffer_height + 5, 0);
    } else if buffer.cursor.line < (buffer.top_line + 5) {
        buffer.top_line = math.max(buffer.cursor.line - 5, 0);
    }
}

// TODO: don't mangle cursor
scroll_file_buffer :: proc(buffer: ^FileBuffer, dir: ScrollDir) {
    switch dir {
        case .Up:
        {
            move_cursor_up(buffer, 20);
        }
        case .Down:
        {
            move_cursor_down(buffer, 20);
        }
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

