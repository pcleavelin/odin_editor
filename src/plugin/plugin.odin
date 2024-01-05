package plugin;

import "core:intrinsics"
import "core:dynlib"
import "core:fmt"

OnInitializeProc :: proc "c" (plugin: Plugin);
OnExitProc :: proc "c" (/* probably needs some state eventually */);
OnDrawProc :: proc "c" (plugin: Plugin);
OnColorBufferProc :: proc "c" (plugin: Plugin, buffer: rawptr);
Interface :: struct {
    on_initialize: OnInitializeProc,
    on_exit: OnExitProc,
    on_draw: OnDrawProc,
}

BufferIndex :: struct {
    slice_index: int,
    content_index: int,
}

Cursor :: struct {
    col: int,
    line: int,
    index: BufferIndex,
}

BufferIter :: struct {
    cursor: Cursor,
    buffer: rawptr,
    hit_end: bool,
}

IterateResult :: struct {
    char: u8,
    should_stop: bool,
}

BufferInfo :: struct {
    glyph_buffer_width: int,
    glyph_buffer_height: int,
    top_line: int,
}

Buffer :: struct {
    get_buffer_info: proc "c" (state: rawptr) -> BufferInfo,
    color_char_at: proc "c" (state: rawptr, buffer: rawptr, start_cursor: Cursor, end_cursor: Cursor, palette_index: i32),
}

Iterator :: struct {
    get_current_buffer_iterator: proc "c" (state: rawptr) -> BufferIter,
    get_buffer_iterator: proc "c" (state: rawptr, buffer: rawptr) -> BufferIter,
    get_char_at_iter: proc "c" (state: rawptr, it: ^BufferIter) -> u8,

    iterate_buffer: proc "c" (state: rawptr, it: ^BufferIter) -> IterateResult,
    iterate_buffer_reverse: proc "c" (state: rawptr, it: ^BufferIter) -> IterateResult,
    iterate_buffer_until: proc "c" (state: rawptr, it: ^BufferIter, until_proc: rawptr),
    iterate_buffer_until_reverse: proc "c" (state: rawptr, it: ^BufferIter, until_proc: rawptr),
    iterate_buffer_peek: proc "c" (state: rawptr, it: ^BufferIter) -> IterateResult,

    until_line_break: rawptr,
    until_single_quote: rawptr,
    until_double_quote: rawptr,
    until_end_of_word: rawptr,
}

Plugin :: struct {
    state: rawptr,
    iter: Iterator,
    buffer: Buffer,

    register_highlighter: proc "c" (state: rawptr, extension: cstring, on_color_buffer: OnColorBufferProc),
}

load_proc_address :: proc(lib_path: string, library: dynlib.Library, symbol: string, $ProcType: typeid) -> ProcType
    where intrinsics.type_is_proc(ProcType)
{
    if address, found := dynlib.symbol_address(library, symbol); found {
        return transmute(ProcType)address;
    } else {
        fmt.println("Could not find symbol", symbol, "in library", lib_path);
    }

    return nil;
}

try_load_plugin :: proc(lib_path: string) -> (plugin: Interface, success: bool) {
    library, ok := dynlib.load_library(lib_path)
    if !ok {
        return {}, false;
    }

    interface := Interface {
        on_initialize = load_proc_address(lib_path, library, "OnInitialize", OnInitializeProc),
        on_exit = load_proc_address(lib_path, library, "OnExit", OnExitProc),
        on_draw = load_proc_address(lib_path, library, "OnDraw", OnDrawProc),
    };

    if interface.on_initialize == nil do return interface, false;
    if interface.on_exit == nil do return interface, false;

    return interface, true
}
