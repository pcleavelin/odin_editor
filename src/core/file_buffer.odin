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

import ts "../tree_sitter"
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

Cursor :: struct {
    col: int,
    line: int,
    index: PieceTableIndex,
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

    flags: BufferFlagSet,
    last_col: int,
    top_line: int,
    selection: Maybe(Selection),

    tree: ts.State,

    history: FileHistory,
    glyphs: GlyphBuffer,
}

BufferFlagSet :: bit_set[BufferFlags]
BufferFlags :: enum {
    UnsavedChanges,
}

FileBufferIter :: struct {
    cursor: Cursor,
    buffer: ^FileBuffer,
    piter: PieceTableIter,
    hit_end: bool,
}

// TODO: don't make this panic on nil snapshot
buffer_piece_table :: proc(file_buffer: ^FileBuffer) -> ^PieceTable {
    return &file_buffer.history.piece_table
}

new_file_buffer_iter_from_beginning :: proc(file_buffer: ^FileBuffer) -> FileBufferIter {
    return FileBufferIter {
        buffer = file_buffer,
        piter = new_piece_table_iter(buffer_piece_table(file_buffer))
    };
}
new_file_buffer_iter_with_cursor :: proc(file_buffer: ^FileBuffer, cursor: Cursor) -> FileBufferIter {
    return FileBufferIter {
        buffer = file_buffer,
        cursor = cursor,
        piter = new_piece_table_iter_from_index(buffer_piece_table(file_buffer), cursor.index)
    };
}
new_file_buffer_iter :: proc{new_file_buffer_iter_from_beginning, new_file_buffer_iter_with_cursor};

file_buffer_end :: proc(buffer: ^FileBuffer) -> Cursor {
    return Cursor {
        col = 0,
        line = 0,
        index = new_piece_table_index_from_end(buffer_piece_table(buffer))
    };
}

FileBufferIterResult :: struct {
    character: u8,
    done: bool,
}

iterate_file_buffer_c :: proc "c" (it: ^FileBufferIter) -> FileBufferIterResult {
    context = runtime.default_context()
    
    character, _, cond := iterate_file_buffer(it)
    
    return FileBufferIterResult {
        character = character,
        done = !cond,
    } 
}

iterate_file_buffer :: proc(it: ^FileBufferIter) -> (character: u8, idx: PieceTableIndex, cond: bool) {
    character, idx, cond = iterate_piece_table_iter(&it.piter)

    it.cursor.index = it.piter.index
    it.hit_end = it.piter.hit_end

    if cond && !it.hit_end {
        if character == '\n' {
            it.cursor.col = 0
            it.cursor.line += 1
        } else {
            it.cursor.col += 1
        }
    }

    return
}

// TODO: figure out how to give the first character of the buffer
iterate_file_buffer_reverse :: proc(it: ^FileBufferIter) -> (character: u8, idx: PieceTableIndex, cond: bool) {
    character, idx, cond = iterate_piece_table_iter_reverse(&it.piter)

    it.cursor.index = it.piter.index
    it.hit_end = it.piter.hit_end

    if cond && !it.hit_end {
        if it.cursor.col > 0 {
            it.cursor.col -= 1
        } else if it.cursor.line > 0 {
            line_length := file_buffer_line_length(it.buffer, it.cursor.index)
            if line_length < 0 { line_length = 0 }

            it.cursor.line -= 1
            it.cursor.col = line_length
        }
    }

    return
}

get_character_at_iter :: proc(it: FileBufferIter) -> u8 {
    return get_character_at_piece_table_index(buffer_piece_table(it.buffer), it.cursor.index);
}

IterProc :: proc(it: ^FileBufferIter) -> (character: u8, idx: PieceTableIndex, cond: bool);
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
    if get_character_at_piece_table_index(buffer_piece_table(it.buffer), it.cursor.index) == '\n' {
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
        if line_length == buffer.history.cursor.col && rendered_line == buffer.history.cursor.line {
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
    buffer.history.cursor.index = before_it.cursor.index;

    update_file_buffer_scroll(buffer);
}

file_buffer_line_length :: proc(buffer: ^FileBuffer, index: PieceTableIndex) -> int {
    line_length := 0;
    // if len(buffer.content_slices) <= 0 do return line_length

    first_character := get_character_at_piece_table_index(buffer_piece_table(buffer), index);
    left_it := new_piece_table_iter_from_index(buffer_piece_table(buffer), index);

    if first_character == '\n' {
        iterate_piece_table_iter_reverse(&left_it);
    }

    for character in iterate_piece_table_iter_reverse(&left_it) {
        if character == '\n' {
            break;
        }

        line_length += 1;
    }

    right_it := new_piece_table_iter_from_index(buffer_piece_table(buffer), index);
    first := true;
    for character in iterate_piece_table_iter(&right_it) {
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

move_cursor_to_location :: proc(buffer: ^FileBuffer, line, col: int, cursor: Maybe(^Cursor) = nil) {
    cursor := cursor;

    if cursor == nil {
        cursor = &buffer.history.cursor;
    }

    it := new_file_buffer_iter(buffer);
    for _ in iterate_file_buffer(&it) {
        if (it.cursor.line == line && it.cursor.col >= col) || it.cursor.line > line {
            break;
        }
    }

    cursor.?^ = it.cursor

    update_file_buffer_scroll(buffer, cursor)

    buffer.last_col = cursor.?.col
}

move_cursor_start_of_line :: proc(buffer: ^FileBuffer, cursor: Maybe(^Cursor) = nil) {
    cursor := cursor;

    if cursor == nil {
        cursor = &buffer.history.cursor;
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

    buffer.last_col = cursor.?.col
}

move_cursor_end_of_line :: proc(buffer: ^FileBuffer, stop_at_end: bool = true, cursor: Maybe(^Cursor) = nil) {
    cursor := cursor;

    if cursor == nil {
        cursor = &buffer.history.cursor;
    }

    buffer.last_col = cursor.?.col

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

    buffer.last_col = cursor.?.col
}

move_cursor_up :: proc(buffer: ^FileBuffer, amount: int = 1, cursor: Maybe(^Cursor) = nil) {
    cursor := cursor;

    if cursor == nil {
        cursor = &buffer.history.cursor;
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

    if cursor.?.col < buffer.last_col && file_buffer_line_length(buffer, cursor.?.index)-1 >= cursor.?.col {
        last_col := buffer.last_col
        move_cursor_right(buffer, amt = buffer.last_col - cursor.?.col, cursor = cursor)
        buffer.last_col = last_col
    }

    update_file_buffer_scroll(buffer, cursor);
}

move_cursor_down :: proc(buffer: ^FileBuffer, amount: int = 1, cursor: Maybe(^Cursor) = nil) {
    cursor := cursor;

    if cursor == nil {
        cursor = &buffer.history.cursor;
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

    if cursor.?.col < buffer.last_col && file_buffer_line_length(buffer, cursor.?.index)-1 >= cursor.?.col {
        last_col := buffer.last_col
        move_cursor_right(buffer, amt = buffer.last_col - cursor.?.col, cursor = cursor)
        buffer.last_col = last_col
    }

    update_file_buffer_scroll(buffer, cursor);
}

move_cursor_left :: proc(buffer: ^FileBuffer, cursor: Maybe(^Cursor) = nil) {
    cursor := cursor;

    if cursor == nil {
        cursor = &buffer.history.cursor;
    }

    if cursor.?.col > 0 {
        it := new_file_buffer_iter_with_cursor(buffer, cursor.?^);
        iterate_file_buffer_reverse(&it);
        cursor.?^ = it.cursor;
    }

    buffer.last_col = cursor.?.col
}

move_cursor_right :: proc(buffer: ^FileBuffer, stop_at_end: bool = true, amt: int = 1, cursor: Maybe(^Cursor) = nil) {
    cursor := cursor;

    if cursor == nil {
        cursor = &buffer.history.cursor;
    }

    it := new_file_buffer_iter_with_cursor(buffer, cursor.?^);
    line_length := file_buffer_line_length(buffer, it.cursor.index);

    for _ in 0..<amt {
        if !stop_at_end || cursor.?.col < line_length-1 {
            iterate_file_buffer(&it);
            cursor.?^ = it.cursor;
        }
    }

    buffer.last_col = cursor.?.col
}

move_cursor_forward_start_of_word :: proc(buffer: ^FileBuffer, cursor: Maybe(^Cursor) = nil) {
    cursor := cursor;

    if cursor == nil {
        cursor = &buffer.history.cursor;
    }

    it := new_file_buffer_iter_with_cursor(buffer, cursor.?^);
    iterate_file_buffer_until(&it, until_start_of_word);
    cursor.?^ = it.cursor;

    buffer.last_col = cursor.?.col

    update_file_buffer_scroll(buffer, cursor);
}

move_cursor_forward_end_of_word :: proc(buffer: ^FileBuffer, cursor: Maybe(^Cursor) = nil) {
    cursor := cursor;

    if cursor == nil {
        cursor = &buffer.history.cursor;
    }

    it := new_file_buffer_iter_with_cursor(buffer, cursor.?^);
    iterate_file_buffer_until(&it, until_end_of_word);
    cursor.?^ = it.cursor;

    buffer.last_col = cursor.?.col

    update_file_buffer_scroll(buffer, cursor);
}

move_cursor_backward_start_of_word :: proc(buffer: ^FileBuffer, cursor: Maybe(^Cursor) = nil) {
    cursor := cursor;

    if cursor == nil {
        cursor = &buffer.history.cursor;
    }

    it := new_file_buffer_iter_with_cursor(buffer, cursor.?^);
    iterate_file_buffer_until_reverse(&it, until_end_of_word);
    //iterate_file_buffer_until(&it, until_non_whitespace);
    cursor.?^ = it.cursor;

    buffer.last_col = cursor.?.col

    update_file_buffer_scroll(buffer, cursor);
}

move_cursor_backward_end_of_word :: proc(buffer: ^FileBuffer, cursor: Maybe(^Cursor) = nil) {
    cursor := cursor;

    if cursor == nil {
        cursor = &buffer.history.cursor;
    }

    it := new_file_buffer_iter_with_cursor(buffer, cursor.?^);
    iterate_file_buffer_until_reverse(&it, until_start_of_word);
    cursor.?^ = it.cursor;

    buffer.last_col = cursor.?.col

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

// TODO: don't access PieceTableIndex directly
is_selection_inverted :: proc(selection: Selection) -> bool {
    return selection.start.index.chunk_index > selection.end.index.chunk_index ||
        (selection.start.index.chunk_index == selection.end.index.chunk_index &&
            selection.start.index.char_index > selection.end.index.char_index)
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

new_virtual_file_buffer :: proc(allocator := context.allocator) -> FileBuffer {
    context.allocator = allocator;
    width := 256;
    height := 256;

    buffer := FileBuffer {
        allocator = allocator,
        file_path = "virtual_buffer",

        history = make_history(),

        glyphs = make_glyph_buffer(width, height),
    };

    push_new_snapshot(&buffer.history)

    return buffer;
}

make_file_buffer :: proc(allocator: mem.Allocator, file_path: string, base_dir: string = "") -> (FileBuffer, Error) {
    context.allocator = allocator;

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

    file_type: ts.LanguageType = .None
    if extension == ".odin" {
        file_type = .Odin
    } else if extension == ".rs" {
        file_type = .Rust
    } else if extension == ".json" {
        file_type = .Json
    }

    if original_content, success := os.read_entire_file_from_handle(fd); success {
        defer delete(original_content)

        content := make([]u8, len(original_content))
        copy_slice(content, original_content)

        width := 256;
        height := 256;

        // fmt.eprintln("file path", fi.fullpath[:]);

        buffer := FileBuffer {
            allocator = allocator,
            directory = dir,
            file_path = fi.fullpath,
            // TODO: fix this windows issue
            // file_path = fi.fullpath[4:],
            extension = extension,

            tree = ts.make_state(file_type),
            history = make_history(content),

            glyphs = make_glyph_buffer(width, height),
        };

        push_new_snapshot(&buffer.history)
        ts.parse_buffer(&buffer.tree, tree_sitter_file_buffer_input(&buffer))

        return buffer, error();
    } else {
        return FileBuffer{}, error(ErrorType.FileIOError, fmt.aprintf("failed to read from file"));
    }
}

tree_sitter_file_buffer_input :: proc(buffer: ^FileBuffer) -> ts.Input {
    read :: proc "c" (payload: rawptr, byte_index: u32, position: ts.Point, bytes_read: ^u32) -> ^u8 {
        context = runtime.default_context()

        buffer := transmute(^FileBuffer)payload

        if iter, ok := new_piece_table_iter_from_byte_offset(&buffer.history.piece_table, int(byte_index)); ok {
            bytes := get_content(iter.t.content, iter.t.chunks[iter.index.chunk_index])[iter.index.char_index:]
            bytes_read^ = u32(len(bytes))

            return raw_data(bytes)
        } else {
            bytes_read^ = 0
            return nil
        }
    }

    return ts.Input {
        payload = buffer,
        read = read,
        encoding = .UTF8,
    }
}

save_buffer_to_disk :: proc(state: ^State, buffer: ^FileBuffer) -> (error: os.Error) {
    fd := os.open(buffer.file_path, flags = os.O_WRONLY | os.O_TRUNC | os.O_CREATE) or_return;
    defer os.close(fd);

    t := buffer_piece_table(buffer)

    offset: i64 = 0
    for chunk in t.chunks {
        os.write(fd, get_content(t.content, chunk)) or_return
        
        offset += i64(chunk.len)
    }
    os.flush(fd)

    log.infof("written %v bytes", offset)
    buffer.flags -= { .UnsavedChanges }
    
    return
}

// TODO: replace this with arena for the file buffer
free_file_buffer :: proc(buffer: ^FileBuffer) {
    ts.delete_state(&buffer.tree)
    free_history(&buffer.history)
    delete(buffer.glyphs.buffer)
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

draw_file_buffer :: proc(state: ^State, buffer: ^FileBuffer, x, y, w, h: int, show_line_numbers: bool = true, show_cursor: bool = true) {
    glyph_width := math.max(math.min(256, int(w / state.source_font_width)), 1);
    glyph_height := math.max(math.min(256, int(h / state.source_font_height)) + 1, 1);

    update_glyph_buffer(buffer, glyph_width, glyph_height);

    padding := 0;
    if show_line_numbers {
        padding = state.source_font_width * 5;
    }

    begin := buffer.top_line;
    cursor_x := x + padding + buffer.history.cursor.col * state.source_font_width;
    cursor_y := y + buffer.history.cursor.line * state.source_font_height;

    cursor_y -= begin * state.source_font_height;

    // draw cursor
    if show_cursor {
        if state.mode == .Normal {
            draw_rect(state, cursor_x, cursor_y, state.source_font_width, state.source_font_height, .Background4);
        } else if state.mode == .Visual && buffer.selection != nil {
            start_sel_x := x + padding + buffer.selection.?.start.col * state.source_font_width;
            start_sel_y := y + buffer.selection.?.start.line * state.source_font_height;

            end_sel_x := x + padding + buffer.selection.?.end.col * state.source_font_width;
            end_sel_y := y + buffer.selection.?.end.line * state.source_font_height;

            start_sel_y -= begin * state.source_font_height;
            end_sel_y -= begin * state.source_font_height;

            draw_rect(state, start_sel_x, start_sel_y, state.source_font_width, state.source_font_height, .Green);
            draw_rect(state, end_sel_x, end_sel_y, state.source_font_width, state.source_font_height, .Blue);
        } else if state.mode == .Insert {
            draw_rect(state, cursor_x, cursor_y, state.source_font_width, state.source_font_height, .Blue);
        }
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
        if state.mode == .Visual && buffer.selection != nil {
            selection := swap_selections(buffer.selection.?)

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
        cursor = &buffer.history.cursor;
    }

    if buffer.glyphs.height <= 5 {
        buffer.top_line = cursor.?.line
    } else if cursor.?.line > (buffer.top_line + buffer.glyphs.height - 5) {
        buffer.top_line = math.max(cursor.?.line - buffer.glyphs.height + 5, 0);
    } else if cursor.?.line < (buffer.top_line + 5) {
        buffer.top_line = math.max(cursor.?.line - 5, 0);
    }
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

insert_content :: proc(buffer: ^FileBuffer, to_be_inserted: []u8, reparse_buffer: bool = false) {
    if len(to_be_inserted) == 0 {
        return;
    }
    buffer.flags += { .UnsavedChanges }

    index := buffer.history.cursor.index

    insert_text(buffer_piece_table(buffer), to_be_inserted, buffer.history.cursor.index)

    update_file_buffer_index_from_cursor(buffer);
    move_cursor_right(buffer, false, amt = len(to_be_inserted));

    if reparse_buffer {
        ts.parse_buffer(&buffer.tree, tree_sitter_file_buffer_input(buffer))
    }
}

delete_content_from_buffer_cursor :: proc(buffer: ^FileBuffer, amount: int, reparse_buffer: bool = false) {
    buffer.flags += { .UnsavedChanges }

    // Calculate proper line/col values
    it := new_file_buffer_iter_with_cursor(buffer, buffer.history.cursor);
    iterate_file_buffer_reverse(&it)

    delete_text(buffer_piece_table(buffer), &buffer.history.cursor.index)

    buffer.history.cursor.line = it.cursor.line
    buffer.history.cursor.col = it.cursor.col

    if reparse_buffer {
        ts.parse_buffer(&buffer.tree, tree_sitter_file_buffer_input(buffer))
    }
}

delete_content_from_selection :: proc(buffer: ^FileBuffer, selection: ^Selection, reparse_buffer: bool = false) {
    buffer.flags += { .UnsavedChanges }

    selection^ = swap_selections(selection^)
    delete_text_in_span(buffer_piece_table(buffer), &selection.start.index, &selection.end.index)

    buffer.history.cursor.line = selection.start.line
    buffer.history.cursor.col = selection.start.col

    buffer.history.cursor.index = selection.start.index

    if get_character_at_piece_table_index(buffer_piece_table(buffer), selection.start.index) == '\n' {
        move_cursor_left(buffer)
    }

    if reparse_buffer {
        ts.parse_buffer(&buffer.tree, tree_sitter_file_buffer_input(buffer))
    }
}

delete_content :: proc{delete_content_from_buffer_cursor, delete_content_from_selection};

clear_file_buffer :: proc(buffer: ^FileBuffer) {
    clear_piece_table(buffer_piece_table(buffer)) 
    buffer.history.cursor = Cursor{}
    buffer.last_col = 0
    buffer.top_line = 0
    buffer.selection = nil
    buffer.flags += { .UnsavedChanges }
}

get_buffer_indent :: proc(buffer: ^FileBuffer, cursor: Maybe(Cursor) = nil) -> int {
    cursor := cursor;

    if cursor == nil {
        cursor = buffer.history.cursor;
    }

    ptr_cursor := &cursor.?

    move_cursor_start_of_line(buffer, ptr_cursor)

    it := new_file_buffer_iter_with_cursor(buffer, ptr_cursor^);
    iterate_file_buffer_until(&it, until_non_whitespace)

    return it.cursor.col
}

buffer_to_string :: proc(buffer: ^FileBuffer, allocator := context.allocator) -> string {
    context.allocator = allocator

    t := buffer_piece_table(buffer)

    length := 0
    for chunk in t.chunks {
        length += chunk.len
    }

    buffer_contents := make([]u8, length)

    offset := 0
    for chunk in t.chunks {
        for c in get_content(t.content, chunk) {
            buffer_contents[offset] = c
            offset += 1
        }
    }

    return string(buffer_contents[:len(buffer_contents)-1])
}

buffer_append_new_line :: proc(buffer: ^FileBuffer) {

}
