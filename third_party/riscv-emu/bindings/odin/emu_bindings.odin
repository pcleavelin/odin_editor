package emu_bindings

import "base:runtime"
import "core:mem"
import "core:slice"
import "core:strings"

foreign import emu_stdlib "system:emu_stdlib"

@(default_calling_convention = "c")
foreign emu_stdlib {
    emu_syscall :: proc() ---
    emu_out_call_host_fn :: proc(buf: ^u8, len: int) ---

    emu_out_push_u32 :: proc(val: u32) ---
    emu_out_push_u64 :: proc(val: u64) ---

    emu_out_pop_u32 :: proc() -> u32 ---
    emu_out_pop_u64 :: proc() -> u64 ---

    emu_in_read_line :: proc(buf: ^^u8, len: ^u64) -> u8 ---
}

MainProc :: proc()

EMU_ARENA: mem.Arena
EMU_ALLOCATOR: mem.Allocator
EMU_CONTEXT: runtime.Context

@(export)
_start :: proc() {
    data := slice.bytes_from_ptr(rawptr(uintptr(0x4000)), 1024 * 4)
    mem.arena_init(&EMU_ARENA, data)

    EMU_ALLOCATOR = mem.arena_allocator(&EMU_ARENA)
    EMU_CONTEXT.allocator = EMU_ALLOCATOR

    print("_start called\n")

    emu_out_push_u64(0xBADBEEF)
}

push_string :: proc(str: string) {
    emu_out_push_u32(u32(len(str)))
    emu_out_push_u64(u64(uintptr(transmute(^u8)raw_data(str))))
}

pop_string :: proc() -> string {
    str_addr := emu_out_pop_u64()
    str_len := emu_out_pop_u32()

    return strings.string_from_ptr(transmute(^u8)uintptr(str_addr), int(str_len))
}

print :: proc(str: string) {
    emu_out_push_u32(u32(len(str)))
    emu_out_push_u64(u64(uintptr(transmute(^u8)raw_data(str))))

    func_str := "core::println"
    emu_out_call_host_fn(transmute(^u8)raw_data(func_str), len(func_str))
}

readln :: proc() -> (val: string) {
    buf: ^u8
    len: u64

    if emu_in_read_line(&buf, &len) > 0 do return

    return string(slice.bytes_from_ptr(buf, int(len)))
}
