package plugin;

import "core:intrinsics"
import "core:dynlib"
import "core:fmt"

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

UiInteraction :: struct {
    hovering: bool,
    clicked: bool
}

UiAxis :: enum {
    Horizontal = 0,
    Vertical,
}

UiSemanticSize :: struct {
    kind: int,
    value: int,
}

UiBox :: rawptr;

UiPushParentProc :: proc "c" (ui_context: rawptr, box: UiBox);
UiPopParentProc :: proc "c" (ui_context: rawptr);
UiFloatingProc :: proc "c" (ui_context: rawptr, label: cstring, pos: [2]int) -> UiBox;
UiCreateBoxProc :: proc "c" (ui_context: rawptr, label: cstring) -> UiBox;
UiRectProc ::  proc "c" (ui_context: rawptr, label: cstring, background: bool, border: bool, axis: UiAxis, size: [2]UiSemanticSize) -> UiBox;
UiSimpleProc :: proc "c" (ui_context: rawptr, label: cstring) -> UiInteraction;
UiBufferProc :: proc "c" (ui_context: rawptr, buffer: rawptr, show_line_numbers: bool);
UiBufferIndexProc :: proc "c" (ui_context: rawptr, buffer: int, show_line_numbers: bool);
Ui :: struct {
    ui_context: rawptr,

    push_parent: UiPushParentProc,
    pop_parent: UiPopParentProc,

    spacer: UiSimpleProc,
    floating: UiFloatingProc,
    rect: UiRectProc,

    button: UiSimpleProc,
    label: UiSimpleProc,

    buffer: UiBufferProc,
    buffer_from_index: UiBufferIndexProc,
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
    ui: Ui,

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
    Draw = 1,
}

Key :: enum {
    UNKNOWN            = 0,
    ENTER              = 13,
    ESCAPE             = 27,
    BACKSPACE          = 8,
    TAB                = 9,
    SPACE              = 32,
    EXCLAIM            = 33,
    QUOTEDBL           = 34,
    HASH               = 35,
    PERCENT            = 37,
    DOLLAR             = 36,
    AMPERSAND          = 38,
    QUOTE              = 39,
    LEFTPAREN          = 40,
    RIGHTPAREN         = 41,
    ASTERISK           = 42,
    PLUS               = 43,
    COMMA              = 44,
    MINUS              = 45,
    PERIOD             = 46,
    SLASH              = 47,
    NUM0               = 48,
    NUM1               = 49,
    NUM2               = 50,
    NUM3               = 51,
    NUM4               = 52,
    NUM5               = 53,
    NUM6               = 54,
    NUM7               = 55,
    NUM8               = 56,
    NUM9               = 57,
    COLON              = 58,
    SEMICOLON          = 59,
    LESS               = 60,
    EQUAL              = 61,
    GREATER            = 62,
    QUESTION           = 63,
    AT                 = 64,
    LEFTBRACKET        = 91,
    BACKSLASH          = 92,
    RIGHTBRACKET       = 93,
    CARET              = 94,
    UNDERSCORE         = 95,
    BACKQUOTE          = 96,
    A                  = 97,
    B                  = 98,
    C                  = 99,
    D                  = 100,
    E                  = 101,
    F                  = 102,
    G                  = 103,
    H                  = 104,
    I                  = 105,
    J                  = 106,
    K                  = 107,
    L                  = 108,
    M                  = 109,
    N                  = 110,
    O                  = 111,
    P                  = 112,
    Q                  = 113,
    R                  = 114,
    S                  = 115,
    T                  = 116,
    U                  = 117,
    V                  = 118,
    W                  = 119,
    X                  = 120,
    Y                  = 121,
    Z                  = 122,
    CAPSLOCK           = 1073741881,
    F1                 = 1073741882,
    F2                 = 1073741883,
    F3                 = 1073741884,
    F4                 = 1073741885,
    F5                 = 1073741886,
    F6                 = 1073741887,
    F7                 = 1073741888,
    F8                 = 1073741889,
    F9                 = 1073741890,
    F10                = 1073741891,
    F11                = 1073741892,
    F12                = 1073741893,
    PRINTSCREEN        = 1073741894,
    SCROLLLOCK         = 1073741895,
    PAUSE              = 1073741896,
    INSERT             = 1073741897,
    HOME               = 1073741898,
    PAGEUP             = 1073741899,
    DELETE             = 127,
    END                = 1073741901,
    PAGEDOWN           = 1073741902,
    RIGHT              = 1073741903,
    LEFT               = 1073741904,
    DOWN               = 1073741905,
    UP                 = 1073741906,
    NUMLOCKCLEAR       = 1073741907,
    KP_DIVIDE          = 1073741908,
    KP_MULTIPLY        = 1073741909,
    KP_MINUS           = 1073741910,
    KP_PLUS            = 1073741911,
    KP_ENTER           = 1073741912,
    KP_1               = 1073741913,
    KP_2               = 1073741914,
    KP_3               = 1073741915,
    KP_4               = 1073741916,
    KP_5               = 1073741917,
    KP_6               = 1073741918,
    KP_7               = 1073741919,
    KP_8               = 1073741920,
    KP_9               = 1073741921,
    KP_0               = 1073741922,
    KP_PERIOD          = 1073741923,
    APPLICATION        = 1073741925,
    POWER              = 1073741926,
    KP_EQUALS          = 1073741927,
    F13                = 1073741928,
    F14                = 1073741929,
    F15                = 1073741930,
    F16                = 1073741931,
    F17                = 1073741932,
    F18                = 1073741933,
    F19                = 1073741934,
    F20                = 1073741935,
    F21                = 1073741936,
    F22                = 1073741937,
    F23                = 1073741938,
    F24                = 1073741939,
    EXECUTE            = 1073741940,
    HELP               = 1073741941,
    MENU               = 1073741942,
    SELECT             = 1073741943,
    STOP               = 1073741944,
    AGAIN              = 1073741945,
    UNDO               = 1073741946,
    CUT                = 1073741947,
    COPY               = 1073741948,
    PASTE              = 1073741949,
    FIND               = 1073741950,
    MUTE               = 1073741951,
    VOLUMEUP           = 1073741952,
    VOLUMEDOWN         = 1073741953,
    KP_COMMA           = 1073741957,
    KP_EQUALSAS400     = 1073741958,
    ALTERASE           = 1073741977,
    SYSREQ             = 1073741978,
    CANCEL             = 1073741979,
    CLEAR              = 1073741980,
    PRIOR              = 1073741981,
    RETURN2            = 1073741982,
    SEPARATOR          = 1073741983,
    OUT                = 1073741984,
    OPER               = 1073741985,
    CLEARAGAIN         = 1073741986,
    CRSEL              = 1073741987,
    EXSEL              = 1073741988,
    KP_00              = 1073742000,
    KP_000             = 1073742001,
    THOUSANDSSEPARATOR = 1073742002,
    DECIMALSEPARATOR   = 1073742003,
    CURRENCYUNIT       = 1073742004,
    CURRENCYSUBUNIT    = 1073742005,
    KP_LEFTPAREN       = 1073742006,
    KP_RIGHTPAREN      = 1073742007,
    KP_LEFTBRACE       = 1073742008,
    KP_RIGHTBRACE      = 1073742009,
    KP_TAB             = 1073742010,
    KP_BACKSPACE       = 1073742011,
    KP_A               = 1073742012,
    KP_B               = 1073742013,
    KP_C               = 1073742014,
    KP_D               = 1073742015,
    KP_E               = 1073742016,
    KP_F               = 1073742017,
    KP_XOR             = 1073742018,
    KP_POWER           = 1073742019,
    KP_PERCENT         = 1073742020,
    KP_LESS            = 1073742021,
    KP_GREATER         = 1073742022,
    KP_AMPERSAND       = 1073742023,
    KP_DBLAMPERSAND    = 1073742024,
    KP_VERTICALBAR     = 1073742025,
    KP_DBLVERTICALBAR  = 1073742026,
    KP_COLON           = 1073742027,
    KP_HASH            = 1073742028,
    KP_SPACE           = 1073742029,
    KP_AT              = 1073742030,
    KP_EXCLAM          = 1073742031,
    KP_MEMSTORE        = 1073742032,
    KP_MEMRECALL       = 1073742033,
    KP_MEMCLEAR        = 1073742034,
    KP_MEMADD          = 1073742035,
    KP_MEMSUBTRACT     = 1073742036,
    KP_MEMMULTIPLY     = 1073742037,
    KP_MEMDIVIDE       = 1073742038,
    KP_PLUSMINUS       = 1073742039,
    KP_CLEAR           = 1073742040,
    KP_CLEARENTRY      = 1073742041,
    KP_BINARY          = 1073742042,
    KP_OCTAL           = 1073742043,
    KP_DECIMAL         = 1073742044,
    KP_HEXADECIMAL     = 1073742045,
    LCTRL              = 1073742048,
    LSHIFT             = 1073742049,
    LALT               = 1073742050,
    LGUI               = 1073742051,
    RCTRL              = 1073742052,
    RSHIFT             = 1073742053,
    RALT               = 1073742054,
    RGUI               = 1073742055,
    MODE               = 1073742081,
    AUDIONEXT          = 1073742082,
    AUDIOPREV          = 1073742083,
    AUDIOSTOP          = 1073742084,
    AUDIOPLAY          = 1073742085,
    AUDIOMUTE          = 1073742086,
    MEDIASELECT        = 1073742087,
    WWW                = 1073742088,
    MAIL               = 1073742089,
    CALCULATOR         = 1073742090,
    COMPUTER           = 1073742091,
    AC_SEARCH          = 1073742092,
    AC_HOME            = 1073742093,
    AC_BACK            = 1073742094,
    AC_FORWARD         = 1073742095,
    AC_STOP            = 1073742096,
    AC_REFRESH         = 1073742097,
    AC_BOOKMARKS       = 1073742098,
    BRIGHTNESSDOWN     = 1073742099,
    BRIGHTNESSUP       = 1073742100,
    DISPLAYSWITCH      = 1073742101,
    KBDILLUMTOGGLE     = 1073742102,
    KBDILLUMDOWN       = 1073742103,
    KBDILLUMUP         = 1073742104,
    EJECT              = 1073742105,
    SLEEP              = 1073742106,
    APP1               = 1073742107,
    APP2               = 1073742108,
    AUDIOREWIND        = 1073742109,
    AUDIOFASTFORWARD   = 1073742110,
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
