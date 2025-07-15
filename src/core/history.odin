package core

FileHistory :: struct {
   snapshots: []Snapshot,
   current: int
}

Snapshot :: union {
    PieceTable,
}

make_history_with_data :: proc(initial_data: []u8, starting_capacity: int = 1024, allocator := context.allocator) -> FileHistory {
    context.allocator = allocator

    snapshots := make([]Snapshot, starting_capacity)
    snapshots[0] = make_piece_table_from_bytes(initial_data, starting_capacity)

    return FileHistory {
        snapshots = snapshots,
        current = 0
    }
}

make_history_empty :: proc(starting_capacity: int = 1024, allocator := context.allocator) -> FileHistory {
    context.allocator = allocator

    snapshots := make([]Snapshot, starting_capacity)
    snapshots[0] = make_piece_table(starting_capacity = starting_capacity)

    return FileHistory {
        snapshots = snapshots,
        current = 0
    }
}

make_history :: proc{make_history_with_data, make_history_empty}

free_history :: proc(history: ^FileHistory) {
    for snapshot in &history.snapshots {
        if piece_table, ok := snapshot.(PieceTable); ok {
            delete(piece_table.original_content);
            delete(piece_table.added_content);
            delete(piece_table.chunks);
        }
    }

    delete(history.snapshots)
}