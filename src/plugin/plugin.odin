package plugin;

import "core:intrinsics"
import "core:dynlib"
import "core:fmt"
import "vendor:raylib"

import "../theme"

OnInitializeProc :: proc "c" (plugin: Plugin);
OnExitProc :: proc "c" (/* probably needs some state eventually */);
OnDrawProc :: proc "c" (plugin: Plugin);
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
    should_continue: bool,
}

BufferInput :: struct {
    bytes: [^]u8,
    length: int,
}

BufferInfo :: struct {
    buffer: rawptr,
    file_path: cstring,
    input: BufferInput,

    cursor: Cursor,

    glyph_buffer_width: int,
    glyph_buffer_height: int,
    top_line: int,
}

Buffer :: struct {
    get_num_buffers: proc "c" () -> int,
    get_buffer_info: proc "c" (buffer: rawptr) -> BufferInfo,
    get_buffer_info_from_index: proc "c" (buffer_index: int) -> BufferInfo,
    color_char_at: proc "c" (buffer: rawptr, start_cursor: Cursor, end_cursor: Cursor, palette_index: i32),
    set_current_buffer: proc "c" (buffer_index: int),

    open_buffer: proc "c" (path: cstring, line: int, col: int),
    open_virtual_buffer: proc "c" () -> rawptr,
    free_virtual_buffer: proc "c" (buffer: rawptr),
}

Iterator :: struct {
    get_current_buffer_iterator: proc "c" () -> BufferIter,
    get_buffer_iterator: proc "c" (buffer: rawptr) -> BufferIter,
    get_char_at_iter: proc "c" (it: ^BufferIter) -> u8,
    get_buffer_list_iter: proc "c" (prev_buffer: ^int) -> int,

    iterate_buffer: proc "c" (it: ^BufferIter) -> IterateResult,
    iterate_buffer_reverse: proc "c" (it: ^BufferIter) -> IterateResult,
    iterate_buffer_until: proc "c" (it: ^BufferIter, until_proc: rawptr),
    iterate_buffer_until_reverse: proc "c" (it: ^BufferIter, until_proc: rawptr),
    iterate_buffer_peek: proc "c" (it: ^BufferIter) -> IterateResult,

    until_line_break: rawptr,
    until_single_quote: rawptr,
    until_double_quote: rawptr,
    until_end_of_word: rawptr,
}

OnColorBufferProc :: proc "c" (plugin: Plugin, buffer: rawptr);
InputGroupProc :: proc "c" (plugin: Plugin, input_map: rawptr);
InputActionProc :: proc "c" (plugin: Plugin);
OnHookProc :: proc "c" (plugin: Plugin, buffer: rawptr);

WindowInputProc :: proc "c" (plugin: Plugin, window: rawptr);
WindowDrawProc :: proc "c" (plugin: Plugin, window: rawptr);
WindowGetBufferProc :: proc(plugin: Plugin, window: rawptr) -> rawptr;
WindowFreeProc :: proc "c" (plugin: Plugin, window: rawptr);
Plugin :: struct {
    state: rawptr,
    iter: Iterator,
    buffer: Buffer,

    register_hook: proc "c" (hook: Hook, on_hook: OnHookProc),
    register_highlighter: proc "c" (extension: cstring, on_color_buffer: OnColorBufferProc),

    register_input_group: proc "c" (input_map: rawptr, key: Key, register_group: InputGroupProc),
    register_input: proc "c" (input_map: rawptr, key: Key, input_action: InputActionProc, description: cstring),

    create_window: proc "c" (user_data: rawptr, register_group: InputGroupProc, draw_proc: WindowDrawProc, free_window_proc: WindowFreeProc, get_buffer_proc: WindowGetBufferProc) -> rawptr,
    get_window: proc "c" () -> rawptr,

    request_window_close: proc "c" (),
    get_screen_width: proc "c" () -> int,
    get_screen_height: proc "c" () -> int,
    get_font_width: proc "c" () -> int,
    get_font_height: proc "c" () -> int,
    get_current_directory: proc "c" () -> cstring,
    enter_insert_mode: proc "c" (),

    draw_rect: proc "c" (x: i32, y: i32, width: i32, height: i32, color: theme.PaletteColor),
    draw_text: proc "c" (text: cstring, x: f32, y: f32, color: theme.PaletteColor),
    draw_buffer_from_index: proc "c" (buffer_index: int, x: int, y: int, glyph_buffer_width: int, glyph_buffer_height: int, show_line_numbers: bool),
    draw_buffer: proc "c" (buffer: rawptr, x: int, y: int, glyph_buffer_width: int, glyph_buffer_height: int, show_line_numbers: bool),
}

Hook :: enum {
    BufferInput = 0,
}

Key :: enum {
    KEY_NULL      = 0,   // Key: NULL, used for no key pressed
    // Alphanumeric keys
    APOSTROPHE    = 39,  // Key: '
    COMMA         = 44,  // Key: ,
    MINUS         = 45,  // Key: -
    PERIOD        = 46,  // Key: .
    SLASH         = 47,  // Key: /
    ZERO          = 48,  // Key: 0
    ONE           = 49,  // Key: 1
    TWO           = 50,  // Key: 2
    THREE         = 51,  // Key: 3
    FOUR          = 52,  // Key: 4
    FIVE          = 53,  // Key: 5
    SIX           = 54,  // Key: 6
    SEVEN         = 55,  // Key: 7
    EIGHT         = 56,  // Key: 8
    NINE          = 57,  // Key: 9
    SEMICOLON     = 59,  // Key: ;
    EQUAL         = 61,  // Key: =
    A             = 65,  // Key: A | a
    B             = 66,  // Key: B | b
    C             = 67,  // Key: C | c
    D             = 68,  // Key: D | d
    E             = 69,  // Key: E | e
    F             = 70,  // Key: F | f
    G             = 71,  // Key: G | g
    H             = 72,  // Key: H | h
    I             = 73,  // Key: I | i
    J             = 74,  // Key: J | j
    K             = 75,  // Key: K | k
    L             = 76,  // Key: L | l
    M             = 77,  // Key: M | m
    N             = 78,  // Key: N | n
    O             = 79,  // Key: O | o
    P             = 80,  // Key: P | p
    Q             = 81,  // Key: Q | q
    R             = 82,  // Key: R | r
    S             = 83,  // Key: S | s
    T             = 84,  // Key: T | t
    U             = 85,  // Key: U | u
    V             = 86,  // Key: V | v
    W             = 87,  // Key: W | w
    X             = 88,  // Key: X | x
    Y             = 89,  // Key: Y | y
    Z             = 90,  // Key: Z | z
    LEFT_BRACKET  = 91,  // Key: [
    BACKSLASH     = 92,  // Key: '\'
    RIGHT_BRACKET = 93,  // Key: ]
    GRAVE         = 96,  // Key: `
    // Function keys
    SPACE         = 32,  // Key: Space
    ESCAPE        = 256, // Key: Esc
    ENTER         = 257, // Key: Enter
    TAB           = 258, // Key: Tab
    BACKSPACE     = 259, // Key: Backspace
    INSERT        = 260, // Key: Ins
    DELETE        = 261, // Key: Del
    RIGHT         = 262, // Key: Cursor right
    LEFT          = 263, // Key: Cursor left
    DOWN          = 264, // Key: Cursor down
    UP            = 265, // Key: Cursor up
    PAGE_UP       = 266, // Key: Page up
    PAGE_DOWN     = 267, // Key: Page down
    HOME          = 268, // Key: Home
    END           = 269, // Key: End
    CAPS_LOCK     = 280, // Key: Caps lock
    SCROLL_LOCK   = 281, // Key: Scroll down
    NUM_LOCK      = 282, // Key: Num lock
    PRINT_SCREEN  = 283, // Key: Print screen
    PAUSE         = 284, // Key: Pause
    F1            = 290, // Key: F1
    F2            = 291, // Key: F2
    F3            = 292, // Key: F3
    F4            = 293, // Key: F4
    F5            = 294, // Key: F5
    F6            = 295, // Key: F6
    F7            = 296, // Key: F7
    F8            = 297, // Key: F8
    F9            = 298, // Key: F9
    F10           = 299, // Key: F10
    F11           = 300, // Key: F11
    F12           = 301, // Key: F12
    LEFT_SHIFT    = 340, // Key: Shift left
    LEFT_CONTROL  = 341, // Key: Control left
    LEFT_ALT      = 342, // Key: Alt left
    LEFT_SUPER    = 343, // Key: Super left
    RIGHT_SHIFT   = 344, // Key: Shift right
    RIGHT_CONTROL = 345, // Key: Control right
    RIGHT_ALT     = 346, // Key: Alt right
    RIGHT_SUPER   = 347, // Key: Super right
    KB_MENU       = 348, // Key: KB menu
    // Keypad keys
    KP_0          = 320, // Key: Keypad 0
    KP_1          = 321, // Key: Keypad 1
    KP_2          = 322, // Key: Keypad 2
    KP_3          = 323, // Key: Keypad 3
    KP_4          = 324, // Key: Keypad 4
    KP_5          = 325, // Key: Keypad 5
    KP_6          = 326, // Key: Keypad 6
    KP_7          = 327, // Key: Keypad 7
    KP_8          = 328, // Key: Keypad 8
    KP_9          = 329, // Key: Keypad 9
    KP_DECIMAL    = 330, // Key: Keypad .
    KP_DIVIDE     = 331, // Key: Keypad /
    KP_MULTIPLY   = 332, // Key: Keypad *
    KP_SUBTRACT   = 333, // Key: Keypad -
    KP_ADD        = 334, // Key: Keypad +
    KP_ENTER      = 335, // Key: Keypad Enter
    KP_EQUAL      = 336, // Key: Keypad =
    // Android key buttons
    BACK          = 4,   // Key: Android back button
    MENU          = 82,  // Key: Android menu button
    VOLUME_UP     = 24,  // Key: Android volume up button
    VOLUME_DOWN   = 25,  // Key: Android volume down button
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
