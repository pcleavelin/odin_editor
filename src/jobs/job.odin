package job

import "core:thread"
import "core:sync"
import "core:mem"
import "core:slice"
import "core:strings"
import "core:log"
import "base:intrinsics"
import "core:fmt"

import "base:runtime"

import ring "../util/ring_buffer"

Job :: struct {
    queue: ^JobQueue,

    input: rawptr,
    output: rawptr,

    mutex: sync.Mutex,
    finished_sema: sync.Sema,
    finished: bool,

    arena: mem.Arena,
    allocator: mem.Allocator,
    handler: JobHandler,

    name: string,
}

JobQueue :: struct {
    arena: ^mem.Arena,
    allocator: mem.Allocator,
    num_threads: int,
    is_running: bool,

    available_threads: sync.Sema,
    queue_mutex: sync.Mutex,
    task_queue: ring.Queue,

    threads: []^thread.Thread,
    job_data: []Job,
}

JobHandler :: proc(job: ^Job)

make_job_queue :: proc(allocator: mem.Allocator, num_threads: int, q: ^JobQueue) {
    raw_arena, _ := mem.alloc(size_of(mem.Arena), allocator = allocator)
    q.arena = cast(^mem.Arena)raw_arena

    arena_bytes, err := mem.make([]u8, 1024*1024*16*num_threads, allocator = allocator)
    if err != .None {
        log.error("failed to allocate arena for job queue")
        return
    }

    mem.arena_init(q.arena, arena_bytes)
    q.allocator = mem.arena_allocator(q.arena)


    q.num_threads = num_threads
    q.task_queue = ring.make_queue(10, allocator = q.allocator)
    threads, err3 := mem.make([]^thread.Thread, q.num_threads, allocator = q.allocator)
    job_data, err4 := mem.make([]Job, q.num_threads, allocator = q.allocator)

    if err3 != .None {
        log.error("failed to allocate job queue threads")
    }
    if err4 != .None {
        log.error("failed to allocate job queue data")
    }

    q.threads = threads
    q.job_data = job_data
    q.is_running = true

    for i in 0..<len(threads) {
        job_buffer, err := mem.make([]u8, 1024*1024, allocator = q.allocator)
        assert(err == .None)

        mem.arena_init(&q.job_data[i].arena, job_buffer)
        q.job_data[i].allocator = mem.arena_allocator(&q.job_data[i].arena)
        q.job_data[i].queue = q

        sync.post(&q.job_data[i].finished_sema)

        t := thread.create(job_queue_thread_handler)
        t.data = &q.job_data[i]

        q.threads[i] = t

        thread.start(t)
    }

    return
}

add :: proc($T: typeid, q: ^JobQueue, handler: JobHandler, data: T, push_proc: ring.PushProc, pop_proc: ring.PopProc, name: string = "unamed job") {
    context.allocator = q.allocator

    data := data
    bytes := [1]T{data}
    byte_slice := slice.to_bytes(bytes[:])

    if sync.guard(&q.queue_mutex) {
        ring.queue_push(&q.task_queue, byte_slice, rawptr(handler), push_proc, pop_proc)
        sync.post(&q.available_threads)
    }
}

pop :: proc(q: ^JobQueue) -> (job: ^Job, did_pop: bool) {
    for i in 0..<len(q.job_data) {
        if sync.guard(&q.job_data[i].mutex) && q.job_data[i].finished {
            return &q.job_data[i], true
        }
    }

    return
}

destroy_job :: proc(q: ^JobQueue, job: ^Job) {
    if sync.guard(&job.mutex) && job.finished {
        mem.arena_free_all(&job.arena)

        job.finished = false
        sync.post(&job.finished_sema)
    }
}

// FIXME: deallocate arena (just in case this isn't called by a panel)
destroy_job_queue :: proc(q: ^JobQueue) {
    intrinsics.atomic_store(&q.is_running, false)

    sync.post(&q.available_threads, q.num_threads)

    for i in 0..<len(q.threads) {
        thread.join(q.threads[i])
    }
}

@(private)
job_queue_thread_handler :: proc(t: ^thread.Thread) {
    job := cast(^Job)t.data;

    for intrinsics.atomic_load(&job.queue.is_running) {
        sync.wait(&job.finished_sema)
        sync.wait(&job.queue.available_threads)

        if sync.guard(&job.queue.queue_mutex) {
            item, ok := ring.queue_pop(&job.queue.task_queue, job.allocator)
            if !ok {
                log.error("failed to pop job from queue")
                sync.post(&job.finished_sema)
                continue
            }

            job.input = item.data
            job.handler = transmute(JobHandler)item.handler
        }

        job->handler()

        if sync.guard(&job.mutex) {
            job.finished = true
        }
    }
}
