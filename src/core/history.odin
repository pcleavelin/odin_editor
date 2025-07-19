package core

import "core:log"
import "core:mem"

FileHistory :: struct {
    allocator: mem.Allocator,

    piece_table: PieceTable,
    cursor: Cursor,

    snapshots: []Snapshot,
    next: int,
    first: int
}

Snapshot :: struct {
    chunks: [dynamic][]u8,
    cursor: Cursor,
}

make_history_with_data :: proc(initial_data: []u8, starting_capacity: int = 1024, allocator := context.allocator) -> FileHistory {
    context.allocator = allocator

    return FileHistory {
        allocator = allocator,
        piece_table = make_piece_table(initial_data, starting_capacity = starting_capacity),
        snapshots = make([]Snapshot, starting_capacity),
        next = 0,
        first = 0,
    }
}

make_history_empty :: proc(starting_capacity: int = 1024, allocator := context.allocator) -> FileHistory {
    context.allocator = allocator

    return FileHistory {
        allocator = allocator,
        piece_table = make_piece_table(starting_capacity = starting_capacity),
        snapshots = make([]Snapshot, starting_capacity),
        next = 0,
        first = 0,
    }
}

make_history :: proc{make_history_with_data, make_history_empty}

free_history :: proc(history: ^FileHistory) {
    for snapshot in &history.snapshots {
        if snapshot.chunks != nil {
            delete(snapshot.chunks);
        }
    }
    delete(history.snapshots)

    delete(history.piece_table.original_content)
    delete(history.piece_table.added_content)
    delete(history.piece_table.chunks)
}

push_new_snapshot :: proc(history: ^FileHistory) {
    context.allocator = history.allocator

    if history.snapshots[history.next].chunks != nil {
        delete(history.snapshots[history.next].chunks)
    }

    history.snapshots[history.next].chunks = clone_chunk(history.piece_table.chunks)
    history.snapshots[history.next].cursor = history.cursor

    history.next, history.first = next_indexes(history)
}

pop_snapshot :: proc(history: ^FileHistory, make_new_snapshot: bool = false) {
    context.allocator = history.allocator

    new_next, _ := next_indexes(history, backward = true)
    if new_next == history.next do return

    if make_new_snapshot {
        push_new_snapshot(history)
    }

    history.next = new_next

    delete(history.piece_table.chunks)

    history.piece_table.chunks = clone_chunk(history.snapshots[history.next].chunks)
    history.cursor = history.snapshots[history.next].cursor
}

recover_snapshot :: proc(history: ^FileHistory) {
    context.allocator = history.allocator

    new_next, _ := next_indexes(history)
    if history.snapshots[new_next].chunks == nil do return
    history.next = new_next

    delete(history.piece_table.chunks)

    history.piece_table.chunks = clone_chunk(history.snapshots[history.next].chunks)
    history.cursor = history.snapshots[history.next].cursor
}

clone_chunk :: proc(chunks: [dynamic][]u8) -> [dynamic][]u8 {
    new_chunks := make([dynamic][]u8, len(chunks), len(chunks))

    for ptr, i in chunks {
        new_chunks[i] = ptr
    }

    return new_chunks
}

next_indexes :: proc(history: ^FileHistory, backward: bool = false) -> (next: int, first: int) {
    next = history.next
    first = history.first

    if backward {
        if history.next == history.first {
            return
        }

        next = history.next - 1

        if next < 0 {
            next = len(history.snapshots) - 1
        }
    } else {
        next = history.next + 1

        if next >= len(history.snapshots) {
            next = 0
        }

        if next == first {
            first += 1
        }

        if first >= len(history.snapshots) {
            first = 0
        }
    }

    return
}
