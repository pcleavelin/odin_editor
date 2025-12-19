package core

PieceTable :: struct {
    original_content: []u8,
    added_content: [dynamic]u8,

    // TODO: don't actually reference `added_content` and `original_content` via pointers, since they can be re-allocated
    chunks: [dynamic][]u8,
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

make_empty_piece_table :: proc(starting_capacity: int = 1024*1024, allocator := context.allocator) -> PieceTable {
    context.allocator = allocator

    original_content := transmute([]u8)string("\n")
    chunks := make([dynamic][]u8, 0, starting_capacity)

    append(&chunks, original_content[:])

    return PieceTable {
        original_content = original_content,
        added_content = make([dynamic]u8, 0, starting_capacity),
        chunks = chunks,
    }
}

make_piece_table_from_bytes :: proc(data: []u8, starting_capacity: int = 1024*1024, allocator := context.allocator) -> PieceTable {
    context.allocator = allocator

    added_content := make([dynamic]u8, 0, starting_capacity)
    chunks := make([dynamic][]u8, 0, starting_capacity)

    if len(data) > 0 {
        append(&chunks, data[:])
    } else {
        append(&added_content, '\n')
        append(&chunks, added_content[:])
    }

    return PieceTable {
        original_content = data,
        added_content = added_content,
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
        if bytes + len(chunk) > byte_offset {
            char_index := byte_offset - bytes

            return PieceTableIter {
                t = t,
                index = PieceTableIndex {
                    chunk_index = chunk_index,
                    char_index = char_index,
                }
            }, true
        } else {
            bytes += len(chunk)
        }
    }

    return
}

new_piece_table_index_from_end :: proc(t: ^PieceTable) -> PieceTableIndex {
    chunk_index := len(t.chunks)-1
    char_index := len(t.chunks[chunk_index])-1

    return PieceTableIndex {
        chunk_index = chunk_index,
        char_index = char_index,
    }
}

iterate_piece_table_iter :: proc(it: ^PieceTableIter) -> (character: u8, index: PieceTableIndex, cond: bool) {
    if it.index.chunk_index >= len(it.t.chunks) || it.index.char_index >= len(it.t.chunks[it.index.chunk_index]) {
        return
    }

    character = it.t.chunks[it.index.chunk_index][it.index.char_index]
    if it.hit_end {
        return character, it.index, false
    } 

    if it.index.char_index < len(it.t.chunks[it.index.chunk_index])-1 {
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
    if it.index.chunk_index >= len(it.t.chunks) || it.index.char_index >= len(it.t.chunks[it.index.chunk_index]) {
        return
    }

    character = it.t.chunks[it.index.chunk_index][it.index.char_index]
    if it.hit_end {
        return character, it.index, false
    }

    if it.index.char_index > 0 {
        it.index.char_index -= 1
    } else if it.index.chunk_index > 0 {
        it.index.chunk_index -= 1
        it.index.char_index = len(it.t.chunks[it.index.chunk_index])-1
    } else {
        it.hit_end = true
    }

    return character, it.index, true
}

get_character_at_piece_table_index :: proc(t: ^PieceTable, index: PieceTableIndex) -> u8 {
    // FIXME: up the call chain (particularly with pasting over selections) these can be out of bounds
    return t.chunks[index.chunk_index][index.char_index]
}

insert_text :: proc(t: ^PieceTable, to_be_inserted: []u8, index: PieceTableIndex) {
    length := append(&t.added_content, ..to_be_inserted);
    inserted_slice: []u8 = t.added_content[len(t.added_content)-length:];

    if index.char_index == 0 {
        // insertion happening in beginning of content slice

        if len(t.chunks) > 1 && index.chunk_index > 0 {
            last_chunk_index := len(t.chunks[index.chunk_index-1])-1

            // FIXME:                                                                 [this can be negative?          ]
            if (&t.chunks[index.chunk_index-1][last_chunk_index]) == (&t.added_content[len(t.added_content)-1 - length]) {
                start := len(t.added_content)-1 - last_chunk_index - length
                
                t.chunks[index.chunk_index-1] = t.added_content[start:]
            } else {
                inject_at(&t.chunks, index.chunk_index, inserted_slice);
            }
        } else {
            inject_at(&t.chunks, index.chunk_index, inserted_slice);
        }
    }
    else {
        // insertion is happening in middle of content slice

        // cut current slice
        end_slice := t.chunks[index.chunk_index][index.char_index:];
        t.chunks[index.chunk_index] = t.chunks[index.chunk_index][:index.char_index];

        inject_at(&t.chunks, index.chunk_index+1, inserted_slice);
        inject_at(&t.chunks, index.chunk_index+2, end_slice);
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
    chunk_len := len(chunk_ptr^);

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
        chunk_ptr^ = chunk_ptr^[:len(chunk_ptr^)-1];
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

    end_slice := t.chunks[index.chunk_index][index.char_index:];
    t.chunks[index.chunk_index] = t.chunks[index.chunk_index][:index.char_index];

    inject_at(&t.chunks, index.chunk_index+1, end_slice);

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
