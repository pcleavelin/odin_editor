package util_ring_buffer

import "core:mem"
import "core:log"

Queue :: struct {
    num_items: int,
    items: []QueueItem,
    buffer: RingBuffer,
}

QueueItem :: struct {
    data: rawptr,
    handler: rawptr,
    pop_proc: PopProc,
}

make_queue :: proc(size: int, allocator := context.allocator) -> (q: Queue) {
    context.allocator = allocator

    q.items = make([]QueueItem, size)
    q.buffer = make_ring_buffer(1024*size, allocator = allocator)

    return
}

queue_push :: proc(q: ^Queue, data: []u8, handler: rawptr, push_proc: PushProc, pop_proc: PopProc) {
    if q.num_items >= len(q.items) {
        log.error("queue full")
        return
    }

    item_data := push(&q.buffer, data, push_proc)

    q.items[q.num_items] = QueueItem {
        data = item_data,
        handler = handler,
        pop_proc = pop_proc,
    }
    q.num_items += 1
}

queue_pop :: proc(q: ^Queue, allocator: mem.Allocator) -> (item: QueueItem, ok: bool) {
    if q.num_items < 1 {
        return
    }

    q.num_items -= 1
    item = q.items[q.num_items]

    data := pop_front(&q.buffer, item.pop_proc, allocator)
    item.data = data

    return item, true
}
