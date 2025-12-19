package util_ring_buffer

import "core:mem"
import "core:log"
import "core:slice"

import "core:fmt"

RingBuffer :: struct {
    data: []u8,

    head: uintptr,
    tail: uintptr,
}

WriteVTable :: struct {
    write_bytes: proc(cursor: ^WriteCursor, data: []u8),
    write_string: proc(cursor: ^WriteCursor, data: string),
    // write_cstring: proc(cursor: ^WriteCursor, data: cstring),
    write_int: proc(cursor: ^WriteCursor, data: int),
}
ReadVTable :: struct {
    read_bytes: proc(cursor: ^ReadCursor, allocator: mem.Allocator) -> []u8,
    read_string: proc(cursor: ^ReadCursor, allocator: mem.Allocator) -> string,
    // read_cstring: proc(cursor: ^WriteCursor, data: cstring),
    read_int: proc(cursor: ^ReadCursor, allocator: mem.Allocator) -> int,
}

WriteCursor :: struct {
    rb: ^RingBuffer,
}
ReadCursor :: struct {
    rb: ^RingBuffer,
    cursor: uintptr,
}

PushProc :: proc(cursor: ^WriteCursor, data: []u8, w: WriteVTable)
PopProc :: proc(cursor: ^ReadCursor, r: ReadVTable, allocator: mem.Allocator) -> rawptr

@(private)
write_bytes :: proc(cursor: ^WriteCursor, data: []u8) {
    _tail := cursor.rb.tail

    primary, primary_size, ok := _push(cursor.rb, len(data))
    assert(ok)
    assert(primary == &cursor.rb.data[_tail])

    mem.copy_non_overlapping(primary, &data[0], primary_size)

    if primary_size < len(data) {
        remaining := len(data) - primary_size
        mem.copy_non_overlapping(&cursor.rb.data[0], &data[primary_size], remaining)
    }
}

@(private)
write_string :: proc(cursor: ^WriteCursor, data: string) {
    write_int(cursor, len(data))
    write_bytes(cursor, transmute([]u8)data)
}

@(private)
write_int :: proc(cursor: ^WriteCursor, data: int) {
    data := data
    array := [1]int{data}
    bytes := slice.to_bytes(array[:])

    write_bytes(cursor, bytes)
}

@(private)
copy_bytes :: proc(cursor: ^ReadCursor, dest: []u8) {
    if len(dest) == 0 {
        return
    }

    next_cursor := _next_cursor(cursor.cursor, len(dest), len(cursor.rb.data))

    if next_cursor > cursor.cursor {
        assert(int(next_cursor - cursor.cursor) == len(dest))

        mem.copy_non_overlapping(&dest[0], &cursor.rb.data[cursor.cursor], len(dest))
    } else {
        primary_size := len(cursor.rb.data) - int(cursor.cursor)
        remaining := len(dest) - primary_size
        assert(remaining == int(next_cursor))

        mem.copy_non_overlapping(&dest[0], &cursor.rb.data[cursor.cursor], primary_size)
        mem.copy_non_overlapping(&dest[primary_size], &cursor.rb.data[0], remaining)
    }

    cursor.cursor = next_cursor
}

@(private)
read_string :: proc(cursor: ^ReadCursor, allocator: mem.Allocator) -> string {
    size := read_int(cursor, allocator)

    data := make([]u8, size, allocator)
    copy_bytes(cursor, data)

    return string(data)
}

@(private)
read_int :: proc(cursor: ^ReadCursor, allocator: mem.Allocator) -> int {
    next_cursor := _next_cursor(cursor.cursor, size_of(int), len(cursor.rb.data))

    val: [size_of(int)]u8

    if next_cursor > cursor.cursor {
        assert(next_cursor - cursor.cursor == size_of(int))
        mem.copy_non_overlapping(&val[0], &cursor.rb.data[cursor.cursor], size_of(int))
    } else {
        primary_size := len(cursor.rb.data) - int(cursor.cursor)
        remaining := size_of(int) - primary_size

        assert(remaining == int(next_cursor))

        mem.copy_non_overlapping(&val[0], &cursor.rb.data[cursor.cursor], primary_size)
        mem.copy_non_overlapping(&val[primary_size], &cursor.rb.data[0], remaining)
    }

    cursor.cursor = next_cursor

    return (transmute(^int)&val[0])^
}

make_ring_buffer :: proc(size: int, allocator := context.allocator) -> (rb: RingBuffer) {
    context.allocator = allocator

    data, err := mem.make([]u8, size)
    if err != .None {
        log.errorf("failed to allocate ring buffer: %v\n", err)
        return
    }

    rb.data = data

    return
}

push :: proc(rb: ^RingBuffer, data: []u8, copy_proc: PushProc) -> (queue_item: rawptr) {
    queue_item = rawptr(uintptr(&rb.data[0]) + rb.tail)

    cursor := WriteCursor { rb = rb }
    copy_proc(&cursor, data, WriteVTable {
        write_bytes = write_bytes,
        write_string = write_string,
        write_int = write_int,
    })

    return
}

pop_front :: proc(rb: ^RingBuffer, copy_proc: PopProc, allocator: mem.Allocator) -> rawptr {
    cursor := ReadCursor { rb = rb, cursor = rb.head }

    data := copy_proc(&cursor, ReadVTable {
        read_int = read_int,
        read_string = read_string,
    }, allocator)

    rb.head = cursor.cursor

    return data
}

@(private)
_push :: proc(rb: ^RingBuffer, size: int) -> (primary: rawptr, primary_size: int, ok: bool) {
    num_free := _free_space(rb)
    if num_free < size {
        log.error("ring buffer underflow")
        return
    }

    new_tail := _next_cursor(rb.tail, size, len(rb.data))

    if new_tail < rb.tail {
        primary = &rb.data[rb.tail]
        primary_size = len(rb.data) - int(rb.tail)
    } else {
        primary = &rb.data[rb.tail]
        primary_size = size
    }

    rb.tail = new_tail
    ok = true

    return
}

@(private)
_next_cursor :: proc(cursor: uintptr, size: int, rb_size: int) -> uintptr {
    cursor := cursor

    cursor += uintptr(size)

    if cursor >= uintptr(rb_size) {
        cursor -= uintptr(rb_size) 
    }

    return cursor
}

@(private)
_free_space :: proc(rb: ^RingBuffer) -> int {
    if rb.head > rb.tail {
        return int(rb.head - rb.tail)
    }

    return len(rb.data) - int(rb.tail - rb.head)
}
