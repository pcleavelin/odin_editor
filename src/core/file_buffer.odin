package core;

import "core:os"
import "core:log"
import "core:path/filepath"
import "core:mem"
import "core:fmt"
import "core:math"
import "core:slice"
import "base:runtime"
import "core:strings"

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

Selection :: struct {
    start: Cursor,
    end: Cursor,
}

FileBuffer :: struct {
    allocator: mem.Allocator,

    directory: string,
    file_path: string,
    extension: string,

    top_line: int,
    cursor: Cursor,
    selection: Maybe(Selection),

    original_content: [dynamic]u8,
    added_content: [dynamic]u8,
    content_slices: [dynamic][]u8,

    glyphs: GlyphBuffer,

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

file_buffer_end :: proc(buffer: ^FileBuffer) -> Cursor {
    return Cursor {
        col = 0,
        line = 0,
        index = FileBufferIndex {
            slice_index = len(buffer.content_slices)-1,
            content_index = len(buffer.content_slices[len(buffer.content_slices)-1])-1,
        }
    };
}

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
    if len(it.buffer.content_slices[it.cursor.index.slice_index]) < 0 {
        return character, idx, false;
    } 

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
    if len(buffer.content_slices) <= 0 do return line_length

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

move_cursor_start_of_line :: proc(buffer: ^FileBuffer, cursor: Maybe(^Cursor) = nil) {
    cursor := cursor;

    if cursor == nil {
        cursor = &buffer.cursor;
    }

    if cursor.?.col > 0 {
        it := new_file_buffer_iter_with_cursor(buffer, cursor.?^);
        for _ in iterate_file_buffer_reverse(&it) {
            if it.cursor.col <= 0 {
                break;
            }
        }

        cursor.?^ = it.cursor;
    }
}

move_cursor_end_of_line :: proc(buffer: ^FileBuffer, stop_at_end: bool = true, cursor: Maybe(^Cursor) = nil) {
    cursor := cursor;

    if cursor == nil {
        cursor = &buffer.cursor;
    }

    it := new_file_buffer_iter_with_cursor(buffer, cursor.?^);
    line_length := file_buffer_line_length(buffer, it.cursor.index);
    if stop_at_end {
        line_length -= 1;
    }

    if cursor.?.col < line_length {
        for _ in iterate_file_buffer(&it) {
            if it.cursor.col >= line_length {
                break;
            }
        }

        cursor.?^ = it.cursor;
    }
}

move_cursor_up :: proc(buffer: ^FileBuffer, amount: int = 1, cursor: Maybe(^Cursor) = nil) {
    cursor := cursor;

    if cursor == nil {
        cursor = &buffer.cursor;
    }

    if cursor.?.line > 0 {
        current_line := cursor.?.line;
        current_col := cursor.?.col;

        it := new_file_buffer_iter_with_cursor(buffer, cursor.?^);
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

        cursor.?^ = it.cursor;
    }

    update_file_buffer_scroll(buffer, cursor);
}

move_cursor_down :: proc(buffer: ^FileBuffer, amount: int = 1, cursor: Maybe(^Cursor) = nil) {
    cursor := cursor;

    if cursor == nil {
        cursor = &buffer.cursor;
    }

    current_line := cursor.?.line;
    current_col := cursor.?.col;

    it := new_file_buffer_iter_with_cursor(buffer, cursor.?^);
    for _ in iterate_file_buffer(&it) {
        if it.cursor.line >= current_line+amount {
            break;
        }
    }
    if it.hit_end {
        return
    }

    line_length := file_buffer_line_length(buffer, it.cursor.index);
    if it.cursor.col < line_length-1 && it.cursor.col < current_col {
        for _ in iterate_file_buffer(&it) {
            if it.cursor.col >= line_length-1 || it.cursor.col >= current_col {
                break;
            }
        }
    }

    cursor.?^ = it.cursor;
    update_file_buffer_scroll(buffer, cursor);
}

move_cursor_left :: proc(buffer: ^FileBuffer, cursor: Maybe(^Cursor) = nil) {
    cursor := cursor;

    if cursor == nil {
        cursor = &buffer.cursor;
    }

    if cursor.?.col > 0 {
        it := new_file_buffer_iter_with_cursor(buffer, cursor.?^);
        iterate_file_buffer_reverse(&it);
        cursor.?^ = it.cursor;
    }
}

move_cursor_right :: proc(buffer: ^FileBuffer, stop_at_end: bool = true, amt: int = 1, cursor: Maybe(^Cursor) = nil) {
    cursor := cursor;

    if cursor == nil {
        cursor = &buffer.cursor;
    }

    it := new_file_buffer_iter_with_cursor(buffer, cursor.?^);
    line_length := file_buffer_line_length(buffer, it.cursor.index);

    for _ in 0..<amt {
        if !stop_at_end || cursor.?.col < line_length-1 {
            iterate_file_buffer(&it);
            cursor.?^ = it.cursor;
        }
    }
}

move_cursor_forward_start_of_word :: proc(buffer: ^FileBuffer, cursor: Maybe(^Cursor) = nil) {
    cursor := cursor;

    if cursor == nil {
        cursor = &buffer.cursor;
    }

    it := new_file_buffer_iter_with_cursor(buffer, cursor.?^);
    iterate_file_buffer_until(&it, until_start_of_word);
    cursor.?^ = it.cursor;

    update_file_buffer_scroll(buffer, cursor);
}

move_cursor_forward_end_of_word :: proc(buffer: ^FileBuffer, cursor: Maybe(^Cursor) = nil) {
    cursor := cursor;

    if cursor == nil {
        cursor = &buffer.cursor;
    }

    it := new_file_buffer_iter_with_cursor(buffer, cursor.?^);
    iterate_file_buffer_until(&it, until_end_of_word);
    cursor.?^ = it.cursor;

    update_file_buffer_scroll(buffer, cursor);
}

move_cursor_backward_start_of_word :: proc(buffer: ^FileBuffer, cursor: Maybe(^Cursor) = nil) {
    cursor := cursor;

    if cursor == nil {
        cursor = &buffer.cursor;
    }

    it := new_file_buffer_iter_with_cursor(buffer, cursor.?^);
    iterate_file_buffer_until_reverse(&it, until_end_of_word);
    //iterate_file_buffer_until(&it, until_non_whitespace);
    cursor.?^ = it.cursor;

    update_file_buffer_scroll(buffer, cursor);
}

move_cursor_backward_end_of_word :: proc(buffer: ^FileBuffer, cursor: Maybe(^Cursor) = nil) {
    cursor := cursor;

    if cursor == nil {
        cursor = &buffer.cursor;
    }

    it := new_file_buffer_iter_with_cursor(buffer, cursor.?^);
    iterate_file_buffer_until_reverse(&it, until_start_of_word);
    cursor.?^ = it.cursor;

    update_file_buffer_scroll(buffer, cursor);
}

new_selection_zero_length :: proc(cursor: Cursor) -> Selection {
    return {
        start = cursor,
        end = cursor,
    };
}

new_selection_span :: proc(start: Cursor, end: Cursor) -> Selection {
    return {
        start = start,
        end = end,
    };
}

new_selection_current_line :: proc(buffer: ^FileBuffer, cursor: Cursor) -> Selection {
    start := cursor
    end := cursor

    move_cursor_start_of_line(buffer, &start)
    move_cursor_end_of_line(buffer, true, &end)

    return {
        start = start,
        end = end,
    }
}

new_selection :: proc{new_selection_zero_length, new_selection_span, new_selection_current_line};

swap_selections :: proc(selection: Selection) -> (swapped: Selection) {
    swapped = selection

    if is_selection_inverted(selection) {
        swapped.start = selection.end
        swapped.end = selection.start
    }

    return swapped
}

is_selection_inverted :: proc(selection: Selection) -> bool {
    return selection.start.index.slice_index > selection.end.index.slice_index ||
        (selection.start.index.slice_index == selection.end.index.slice_index
            && selection.start.index.content_index > selection.end.index.content_index)
}

selection_length :: proc(buffer: ^FileBuffer, selection: Selection) -> int {
    selection := selection
    it := new_file_buffer_iter_with_cursor(buffer, selection.start)

    length := 0

    for !it.hit_end && !is_selection_inverted(selection) {
        iterate_file_buffer(&it);

        selection.start = it.cursor
        length += 1
    }

    return length
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

        glyphs = make_glyph_buffer(width, height),
        input_buffer = make([dynamic]u8, 0, 1024),
    };

    append(&buffer.content_slices, buffer.original_content[:]);

    return buffer;
}

new_file_buffer :: proc(allocator: mem.Allocator, file_path: string, base_dir: string = "") -> (FileBuffer, Error) {
    context.allocator = allocator;

    fmt.eprintln("attempting to open", file_path);

    fd, err := os.open(file_path);
    if err != nil {
        return FileBuffer{}, make_error(ErrorType.FileIOError, fmt.aprintf("failed to open file: errno=%x", err));
    }
    defer os.close(fd);

    fi, fstat_err := os.fstat(fd);
    if fstat_err != nil {
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

        fmt.eprintln("file path", fi.fullpath[4:]);

        buffer := FileBuffer {
            allocator = allocator,
            directory = dir,
            file_path = fi.fullpath,
            // TODO: fix this windows issue
            // file_path = fi.fullpath[4:],
            extension = extension,

            original_content = slice.clone_to_dynamic(original_content),
            added_content = make([dynamic]u8, 0, 1024*1024),
            content_slices = make([dynamic][]u8, 0, 1024*1024),

            glyphs = make_glyph_buffer(width, height),
            input_buffer = make([dynamic]u8, 0, 1024),
        };

        if len(buffer.original_content) > 0 {
            append(&buffer.content_slices, buffer.original_content[:]);
        } else {
            append(&buffer.added_content, '\n')
            append(&buffer.content_slices, buffer.added_content[:])
        }

        return buffer, error();
    } else {
        return FileBuffer{}, error(ErrorType.FileIOError, fmt.aprintf("failed to read from file"));
    }
}

save_buffer_to_disk :: proc(state: ^State, buffer: ^FileBuffer) -> (error: os.Error) {
    fd := os.open(buffer.file_path, flags = os.O_WRONLY | os.O_TRUNC | os.O_CREATE) or_return;
    defer os.close(fd);

    offset: i64 = 0
    for content_slice in buffer.content_slices {
        os.write(fd, content_slice) or_return
        
        offset += i64(len(content_slice))
    }
    os.flush(fd)

    log.infof("written %v bytes", offset)
    
    return
}

next_buffer :: proc(state: ^State, prev_buffer: ^int) -> int {
    index := prev_buffer^;

    if prev_buffer^ >= len(state.buffers)-1 {
        prev_buffer^ = -1;
    } else {
        prev_buffer^ += 1;
    }

    return index;
}

// TODO: replace this with arena for the file buffer
free_file_buffer :: proc(buffer: ^FileBuffer) {
    delete(buffer.original_content);
    delete(buffer.added_content);
    delete(buffer.content_slices);
    delete(buffer.glyphs.buffer);
    delete(buffer.input_buffer);
}

color_character :: proc(buffer: ^FileBuffer, start: Cursor, end: Cursor, palette_index: theme.PaletteColor) {
    start, end := start, end;

    if end.line < buffer.top_line { return; }
    if start.line < buffer.top_line {
        start.line = 0;
    } else {
        start.line -= buffer.top_line;
    }

    if end.line >= buffer.top_line + buffer.glyphs.height {
        end.line = buffer.glyphs.height - 1;
        end.col = buffer.glyphs.width - 1;
    } else {
        end.line -= buffer.top_line;
    }

    for j in start.line..=end.line {
        start_col := start.col;
        end_col := end.col;
        if j > start.line && j < end.line {
            start_col = 0;
            end_col = buffer.glyphs.width;
        } else if j < end.line {
            end_col = buffer.glyphs.width;
        } else if j > start.line && j == end.line {
            start_col = 0;
        }

        for i in start_col..<math.min(end_col+1, buffer.glyphs.width) {
            buffer.glyphs.buffer[i + j * buffer.glyphs.width].color = palette_index;
        }
    }
}

draw_file_buffer :: proc(state: ^State, buffer: ^FileBuffer, x: int, y: int, show_line_numbers: bool = true) {
    update_glyph_buffer(buffer);

    // TODO: syntax highlighting

    padding := 0;
    if show_line_numbers {
        padding = state.source_font_width * 5;
    }

    begin := buffer.top_line;
    cursor_x := x + padding + buffer.cursor.col * state.source_font_width;
    cursor_y := y + buffer.cursor.line * state.source_font_height;

    cursor_y -= begin * state.source_font_height;

    // draw cursor
    if state.mode == .Normal || current_buffer(state) != buffer {
        draw_rect(state, cursor_x, cursor_y, state.source_font_width, state.source_font_height, .Background4);
    } else if state.mode == .Visual {
        start_sel_x := x + padding + buffer.selection.?.start.col * state.source_font_width;
        start_sel_y := y + buffer.selection.?.start.line * state.source_font_height;

        end_sel_x := x + padding + buffer.selection.?.end.col * state.source_font_width;
        end_sel_y := y + buffer.selection.?.end.line * state.source_font_height;

        start_sel_y -= begin * state.source_font_height;
        end_sel_y -= begin * state.source_font_height;

        draw_rect(state, start_sel_x, start_sel_y, state.source_font_width, state.source_font_height, .Green);
        draw_rect(state, end_sel_x, end_sel_y, state.source_font_width, state.source_font_height, .Blue);
    }
    else if state.mode == .Insert {
        draw_rect(state, cursor_x, cursor_y, state.source_font_width, state.source_font_height, .Green);

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

        draw_rect(state, cursor_x, cursor_y, state.source_font_width, state.source_font_height, .Blue);
    }

    // TODO: replace with glyph_buffer.draw_glyph_buffer
    for j in 0..<buffer.glyphs.height {
        text_y := y + state.source_font_height * j;

        if show_line_numbers {
            draw_text(state, fmt.tprintf("%d", begin + j + 1), x, text_y);
        }

        line_length := 0;
        for i in 0..<buffer.glyphs.width {
            text_x := x + padding + i * state.source_font_width;
            glyph := buffer.glyphs.buffer[i + j * buffer.glyphs.width];

            if glyph.codepoint == 0 { break; }
            line_length += 1;

            draw_codepoint(state, rune(glyph.codepoint), text_x, text_y, glyph.color);
        }

        // NOTE: this requires transparent background color because it renders after the text
        // and its after the text because the line length needs to be calculated
        if state.mode == .Visual && current_buffer(state) == buffer {
            selection := swap_selections(buffer.selection.?)
            // selection := buffer.selection.?

            sel_x := x + padding;
            width: int

            if begin+j >= selection.start.line && begin+j <= selection.end.line {
                if begin+j == selection.start.line && selection.start.line == selection.end.line {
                    width = (selection.end.col - selection.start.col) * state.source_font_width;
                    sel_x += selection.start.col * state.source_font_width;
                } else if begin+j == selection.end.line {
                    width = selection.end.col * state.source_font_width;
                } else {
                    if begin+j == selection.start.line {
                        width = (line_length - selection.start.col) * state.source_font_width;
                        sel_x += selection.start.col * state.source_font_width;
                    } else {
                        width = line_length * state.source_font_width;
                    }
                }
            }

            draw_rect(state, sel_x, text_y, width, state.source_font_height, .Green);
        }
    }
}

update_file_buffer_scroll :: proc(buffer: ^FileBuffer, cursor: Maybe(^Cursor) = nil) {
    cursor := cursor;
    if cursor == nil {
        cursor = &buffer.cursor;
    }

    if cursor.?.line > (buffer.top_line + buffer.glyphs.height - 5) {
        buffer.top_line = math.max(cursor.?.line - buffer.glyphs.height + 5, 0);
    } else if cursor.?.line < (buffer.top_line + 5) {
        buffer.top_line = math.max(cursor.?.line - 5, 0);
    }

    // if buffer.cursor.line > (buffer.top_line + buffer.glyphs.height - 5) {
    //     buffer.top_line = math.max(buffer.cursor.line - buffer.glyphs.height + 5, 0);
    // } else if buffer.cursor.line < (buffer.top_line + 5) {
    //     buffer.top_line = math.max(buffer.cursor.line - 5, 0);
    // }
}

// TODO: don't mangle cursor
scroll_file_buffer :: proc(buffer: ^FileBuffer, dir: ScrollDir, cursor: Maybe(^Cursor) = nil) {

    switch dir {
        case .Up:
        {
            move_cursor_up(buffer, 20, cursor);
        }
        case .Down:
        {
            move_cursor_down(buffer, 20, cursor);
        }
    }
}

insert_content :: proc(buffer: ^FileBuffer, to_be_inserted: []u8, append_to_end: bool = false) {
    if len(to_be_inserted) == 0 {
        return;
    }

    // TODO: is this even needed? would mean that the cursor isn't always in a valid state.
    // update_file_buffer_index_from_cursor(buffer);
    it := new_file_buffer_iter_with_cursor(buffer, buffer.cursor) if !append_to_end else new_file_buffer_iter_with_cursor(buffer, file_buffer_end(buffer));

    length := append(&buffer.added_content, ..to_be_inserted);
    inserted_slice: []u8 = buffer.added_content[len(buffer.added_content)-length:];

    if it.cursor.index.content_index == 0 {
        // insertion happening in beginning of content slice

        inject_at(&buffer.content_slices, it.cursor.index.slice_index, inserted_slice);
    }
    else {
        // insertion is happening in middle of content slice

        // cut current slice
        end_slice := buffer.content_slices[it.cursor.index.slice_index][it.cursor.index.content_index:];
        buffer.content_slices[it.cursor.index.slice_index] = buffer.content_slices[it.cursor.index.slice_index][:it.cursor.index.content_index];

        inject_at(&buffer.content_slices, it.cursor.index.slice_index+1, inserted_slice);
        inject_at(&buffer.content_slices, it.cursor.index.slice_index+2, end_slice);
    }

    if !append_to_end {
        update_file_buffer_index_from_cursor(buffer);
        move_cursor_right(buffer, false, amt = len(to_be_inserted) - 1);
    }
}

// TODO: potentially add FileBufferIndex as parameter
split_content_slice_from_cursor :: proc(buffer: ^FileBuffer, cursor: ^Cursor) -> (did_split: bool) {
    if cursor.index.content_index == 0 {
        return;
    }

    end_slice := buffer.content_slices[cursor.index.slice_index][cursor.index.content_index:];
    buffer.content_slices[cursor.index.slice_index] = buffer.content_slices[cursor.index.slice_index][:cursor.index.content_index];

    inject_at(&buffer.content_slices, cursor.index.slice_index+1, end_slice);

    // TODO: maybe move this out of this function
    cursor.index.slice_index += 1;
    cursor.index.content_index = 0;

    return true
}

split_content_slice_from_selection :: proc(buffer: ^FileBuffer, selection: ^Selection) {
    // TODO: swap selections

    log.info("start:", selection.start, "- end:", selection.end);

    // move the end cursor forward one (we want the splitting to be exclusive, not inclusive)
    it := new_file_buffer_iter_with_cursor(buffer, selection.end);
    iterate_file_buffer(&it);
    selection.end = it.cursor;

    split_content_slice_from_cursor(buffer, &selection.end);
    if split_content_slice_from_cursor(buffer, &selection.start) {
        selection.end.index.slice_index += 1;
    }

    log.info("start:", selection.start, "- end:", selection.end);
}

split_content_slice :: proc{split_content_slice_from_cursor, split_content_slice_from_selection};

delete_content_from_buffer_cursor :: proc(buffer: ^FileBuffer, amount: int) {
    if amount <= len(buffer.input_buffer) {
        runtime.resize(&buffer.input_buffer, len(buffer.input_buffer)-amount);
    } else {
        amount := amount - len(buffer.input_buffer);
        runtime.clear(&buffer.input_buffer);

        if len(buffer.content_slices) < 1 {
            return;
        }

        split_content_slice(buffer, &buffer.cursor);

        it := new_file_buffer_iter_with_cursor(buffer, buffer.cursor);

        // go back one (to be at the end of the content slice)
        iterate_file_buffer_reverse(&it);

        for i in 0..<amount {
            content_slice_ptr := &buffer.content_slices[it.cursor.index.slice_index];
            content_slice_len := len(content_slice_ptr^);

            if content_slice_len == 1 {
                // move cursor to previous content_slice so we can delete the current one
                iterate_file_buffer_reverse(&it);

                if it.hit_end {
                    runtime.ordered_remove(&buffer.content_slices, it.cursor.index.slice_index);
                } else {
                    runtime.ordered_remove(&buffer.content_slices, it.cursor.index.slice_index+1);
                }
            } else if !it.hit_end {
                iterate_file_buffer_reverse(&it);
                content_slice_ptr^ = content_slice_ptr^[:len(content_slice_ptr^)-1];
            }
        }

        if !it.hit_end {
            iterate_file_buffer(&it);
        }
        buffer.cursor = it.cursor;
    }
}

delete_content_from_selection :: proc(buffer: ^FileBuffer, selection: ^Selection) {
    assert(len(buffer.content_slices) >= 1);

    selection^ = swap_selections(selection^)

    split_content_slice(buffer, selection);

    it := new_file_buffer_iter_with_cursor(buffer, selection.start);

    // go back one (to be at the end of the content slice)
    iterate_file_buffer_reverse(&it);

    for _ in selection.start.index.slice_index..<selection.end.index.slice_index {
        runtime.ordered_remove(&buffer.content_slices, selection.start.index.slice_index);
    }

    if !it.hit_end {
        iterate_file_buffer(&it);
    }
    buffer.cursor = it.cursor;
}

delete_content :: proc{delete_content_from_buffer_cursor, delete_content_from_selection};

