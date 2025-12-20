package core

PieceTable :: struct {
    content: [dynamic]u8,
    chunks: [dynamic]ContentIndex,
}

ContentIndex :: struct {
    start: int,
    len: int
}

PieceTableIter :: struct {
    t: ^PieceTable,
    index: PieceTableIndex,
    hit_end: bool,
}

PieceTableIndex :: struct {
    chunk_index: int,
    char_index: int,
}

@(private)
make_index :: proc{make_index_all, make_index_to_end, make_index_from_to}

@(private)
make_index_all :: proc(c: [dynamic]u8) -> ContentIndex {
    return ContentIndex {
        start = 0,
        len = len(c)
    }
}

@(private)
make_index_to_end :: proc(c: [dynamic]u8, start: int) -> ContentIndex {
    assert(start < len(c))
    assert(start > 0)

    return ContentIndex {
        start = start,
        len = len(c) - start
    }
}

@(private)
make_index_from_to :: proc(c: [dynamic]u8, start: int, length: int) -> ContentIndex {
    assert(start < len(c))
    assert(start > 0)
    assert(start+length <= len(c))

    return ContentIndex {
        start = start,
        len = length
    }
}

get_content :: proc(c: [dynamic]u8, i: ContentIndex) -> []u8 {
    return c[i.start:i.start+i.len]
}

make_empty_piece_table :: proc(starting_capacity: int = 1024*1024, allocator := context.allocator) -> PieceTable {
    context.allocator = allocator

    content := make([dynamic]u8, 0, starting_capacity)
    append(&content, '\n')

    chunks := make([dynamic]ContentIndex, 0, starting_capacity)

    append(&chunks, make_index(content))

    return PieceTable {
        content = content,
        chunks = chunks,
    }
}

make_piece_table_from_bytes :: proc(data: []u8, starting_capacity: int = 1024*1024, allocator := context.allocator) -> PieceTable {
    context.allocator = allocator

    content := make([dynamic]u8, 0, starting_capacity)
    chunks := make([dynamic]ContentIndex, 0, starting_capacity)

    if len(data) > 0 {
        append(&content, ..data)
    }

    append(&chunks, make_index(content))

    return PieceTable {
        content = content,
        chunks = chunks,
    }
}

make_piece_table :: proc{make_empty_piece_table, make_piece_table_from_bytes}

new_piece_table_iter :: proc(t: ^PieceTable) -> PieceTableIter {
    return PieceTableIter {
        t = t,
        index = PieceTableIndex {        
            chunk_index = 0,
            char_index = 0,
        }
    }
}

new_piece_table_iter_from_index :: proc(t: ^PieceTable, index: PieceTableIndex) -> PieceTableIter {
    return PieceTableIter {
        t = t,
        index = index
    }
}

new_piece_table_iter_from_byte_offset :: proc(t: ^PieceTable, byte_offset: int) -> (iter: PieceTableIter, ok: bool) {
    bytes := 0

    for chunk, chunk_index in t.chunks {
        if bytes + chunk.len > byte_offset {
            char_index := byte_offset - bytes

            return PieceTableIter {
                t = t,
                index = PieceTableIndex {
                    chunk_index = chunk_index,
                    char_index = char_index,
                }
            }, true
        } else {
            bytes += chunk.len
        }
    }

    return
}

new_piece_table_index_from_end :: proc(t: ^PieceTable) -> PieceTableIndex {
    chunk_index := len(t.chunks)-1
    char_index := t.chunks[chunk_index].len-1

    return PieceTableIndex {
        chunk_index = chunk_index,
        char_index = char_index,
    }
}

iterate_piece_table_iter :: proc(it: ^PieceTableIter) -> (character: u8, index: PieceTableIndex, cond: bool) {
    if it.index.chunk_index >= len(it.t.chunks) || it.index.char_index >= it.t.chunks[it.index.chunk_index].len {
        return
    }

    content := get_content(it.t.content, it.t.chunks[it.index.chunk_index])

    character = content[it.index.char_index]
    if it.hit_end {
        return character, it.index, false
    } 

    if it.index.char_index < it.t.chunks[it.index.chunk_index].len-1 {
        it.index.char_index += 1
    } else if it.index.chunk_index < len(it.t.chunks)-1 {
        it.index.char_index = 0
        it.index.chunk_index += 1
    } else {
        it.hit_end = true
    } 

    return character, it.index, true
}

iterate_piece_table_iter_reverse :: proc(it: ^PieceTableIter) -> (character: u8, index: PieceTableIndex, cond: bool) {
    if it.index.chunk_index >= len(it.t.chunks) || it.index.char_index >= it.t.chunks[it.index.chunk_index].len {
        return
    }

    content := get_content(it.t.content, it.t.chunks[it.index.chunk_index])

    character = content[it.index.char_index]
    if it.hit_end {
        return character, it.index, false
    }

    if it.index.char_index > 0 {
        it.index.char_index -= 1
    } else if it.index.chunk_index > 0 {
        it.index.chunk_index -= 1
        it.index.char_index = it.t.chunks[it.index.chunk_index].len-1
    } else {
        it.hit_end = true
    }

    return character, it.index, true
}

get_character_at_piece_table_index :: proc(t: ^PieceTable, index: PieceTableIndex) -> u8 {
    // FIXME: up the call chain (particularly with pasting over selections) these can be out of bounds
    return get_content(t.content, t.chunks[index.chunk_index])[index.char_index]
}

insert_text :: proc(t: ^PieceTable, to_be_inserted: []u8, index: PieceTableIndex) {
    length := append(&t.content, ..to_be_inserted);
    inserted_index := make_index(t.content, len(t.content)-length)

    index := index

    if split_from_index(t, &index) {
        inject_at(&t.chunks, index.chunk_index, inserted_index);
    } else if index.chunk_index > 0 {
        // if the previous chunk points to the last chunk of `content` just update
        // the length of that chunk instead of injecting a new one, this avoids
        // single character insertions at the same cursor location (plus one)
        // creating new chunks
        i := t.chunks[index.chunk_index-1]
        if i.start + i.len == len(t.content)-length  {
            t.chunks[index.chunk_index-1].len += length
        } else {
            inject_at(&t.chunks, index.chunk_index, inserted_index);
        }
    } else {
        inject_at(&t.chunks, index.chunk_index, inserted_index);
    }
}

delete_text :: proc(t: ^PieceTable, index: ^PieceTableIndex) {
    if len(t.chunks) < 1 {
        return;
    }

    split_from_index(t, index);

    it := new_piece_table_iter_from_index(t, index^);

    // go back one (to be at the end of the chunk)
    iterate_piece_table_iter_reverse(&it);

    chunk_ptr := &t.chunks[it.index.chunk_index];
    chunk_len := chunk_ptr.len;

    if chunk_len == 1 {
        // move cursor to previous chunk so we can delete the current one
        iterate_piece_table_iter_reverse(&it);

        if it.hit_end {
            if len(t.chunks) > 1 {
                ordered_remove(&t.chunks, it.index.chunk_index);
            }
        } else {
            ordered_remove(&t.chunks, it.index.chunk_index+1);
        }
    } else if !it.hit_end {
        iterate_piece_table_iter_reverse(&it);
        chunk_ptr.len -= 1
    }
    

    if !it.hit_end {
        iterate_piece_table_iter(&it);
    }

    index^ = it.index
}

// Assumes end >= start
delete_text_in_span :: proc(t: ^PieceTable, start: ^PieceTableIndex, end: ^PieceTableIndex) {
    assert(len(t.chunks) >= 1);

    split_from_span(t, start, end);

    it := new_piece_table_iter_from_index(t, start^);

    // go back one (to be at the end of the content slice)
    iterate_piece_table_iter_reverse(&it);

    for _ in start.chunk_index..<end.chunk_index {
        ordered_remove(&t.chunks, start.chunk_index);
    }

    if !it.hit_end {
        iterate_piece_table_iter(&it);
    }

    start^ = it.index
    end^ = it.index
}

split_from_index :: proc(t: ^PieceTable, index: ^PieceTableIndex) -> (did_split: bool) {
    if index.char_index == 0 {
        return;
    }

    // set end index to the current chunk's start offset by the split point, whilst keeping the same end point
    end_index := t.chunks[index.chunk_index]
    end_index.start += index.char_index
    end_index.len -= index.char_index

    t.chunks[index.chunk_index].len -= end_index.len

    inject_at(&t.chunks, index.chunk_index+1, end_index);

    index.chunk_index += 1;
    index.char_index = 0;

    return true
}

split_from_span :: proc(t: ^PieceTable, start: ^PieceTableIndex, end: ^PieceTableIndex) {
    // move the end cursor forward one (we want the splitting to be exclusive, not inclusive)
    it := new_piece_table_iter_from_index(t, end^);
    iterate_piece_table_iter(&it);
    end^ = it.index;

    split_from_index(t, end);
    if split_from_index(t, start) {
        end.chunk_index += 1;
    }
}
