use std::{
    borrow::Cow,
    ffi::{c_char, c_void, CStr},
    path::Path,
};

#[macro_export]
macro_rules! Closure {
    (($($arg: ident: $type: ty),+) => $body: expr) => {
        {
            extern "C" fn f($($arg: $type),+) {
                $body
            }
            f
        }
    };
    (($($arg: ident: $type: ty),+) -> $return_type: ty => $body: expr) => {
        {
            extern "C" fn f($($arg: $type),+) -> $return_type {
                $body
            }
            f
        }
    };
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct InputMap {
    internal: *const std::ffi::c_void,
}

#[repr(C)]
#[derive(Debug)]
pub struct BufferIndex {
    pub slice_index: isize,
    pub content_index: isize,
}

#[repr(C)]
#[derive(Debug)]
pub struct Cursor {
    pub col: isize,
    pub line: isize,
    pub index: BufferIndex,
}

#[repr(C)]
#[derive(Debug)]
struct InternalBufferIter {
    cursor: Cursor,
    buffer: *const c_void,
    hit_end: bool,
}

#[repr(C)]
pub struct IterateResult {
    pub char: u8,
    pub should_continue: bool,
}

#[repr(C)]
#[derive(Debug)]
pub struct BufferInput {
    bytes: *const u8,
    length: isize,
}

impl BufferInput {
    pub fn try_as_str(&self) -> Option<Cow<'_, str>> {
        if self.bytes.is_null() {
            None
        } else {
            let slice = unsafe { std::slice::from_raw_parts(self.bytes, self.length as usize) };

            Some(String::from_utf8_lossy(slice))
        }
    }
}

#[repr(C)]
#[derive(Debug)]
pub struct BufferInfo {
    pub buffer: Buffer,
    pub file_path: *const i8,
    pub input: BufferInput,

    pub cursor: Cursor,

    pub glyph_buffer_width: isize,
    pub glyph_buffer_height: isize,
    pub top_line: isize,
}

#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Buffer {
    internal: *const c_void,
}

impl Buffer {
    pub fn null() -> Buffer {
        Buffer {
            internal: std::ptr::null(),
        }
    }
}

#[repr(C)]
pub struct BufferVTable {
    pub get_num_buffers: extern "C" fn() -> isize,
    get_buffer_info: extern "C" fn(buffer: Buffer) -> BufferInfo,
    pub get_buffer_info_from_index: extern "C" fn(buffer_index: isize) -> BufferInfo,
    pub color_char_at: extern "C" fn(
        buffer: *const c_void,
        start_cursor: Cursor,
        end_cursor: Cursor,
        palette_index: i32,
    ),
    pub set_current_buffer: extern "C" fn(buffer_index: isize),

    open_buffer: extern "C" fn(path: *const u8, line: isize, col: isize),
    open_virtual_buffer: extern "C" fn() -> *const c_void,
    free_virtual_buffer: extern "C" fn(buffer: Buffer),
}

impl BufferVTable {
    pub fn get_buffer_info(&self, buffer: Buffer) -> Option<BufferInfo> {
        if buffer.internal.is_null() {
            None
        } else {
            Some((self.get_buffer_info)(buffer))
        }
    }
    pub fn open_buffer(&self, path: impl AsRef<Path>, line: i32, col: i32) {
        let c_str = path.as_ref().to_string_lossy().as_ptr();
        (self.open_buffer)(c_str, line as isize, col as isize);
    }
    pub fn open_virtual_buffer(&self) -> Buffer {
        Buffer {
            internal: (self.open_virtual_buffer)(),
        }
    }
    pub fn free_virtual_buffer(&self, buffer: Buffer) {
        (self.free_virtual_buffer)(buffer);
    }
}

#[repr(C)]
pub struct IteratorVTable {
    get_current_buffer_iterator: extern "C" fn() -> InternalBufferIter,
    get_buffer_iterator: extern "C" fn(buffer: *const c_void) -> InternalBufferIter,
    get_char_at_iter: extern "C" fn(it: *const InternalBufferIter) -> u8,
    get_buffer_list_iter: extern "C" fn(prev_buffer: *const isize) -> isize,

    iterate_buffer: extern "C" fn(it: *mut InternalBufferIter) -> IterateResult,
    iterate_buffer_reverse: extern "C" fn(it: *mut InternalBufferIter) -> IterateResult,
    iterate_buffer_until: extern "C" fn(it: *mut InternalBufferIter, until_proc: *const c_void),
    iterate_buffer_until_reverse:
        extern "C" fn(it: *mut InternalBufferIter, until_proc: *const c_void),
    iterate_buffer_peek: extern "C" fn(it: *mut InternalBufferIter) -> IterateResult,

    pub until_line_break: *const c_void,
    pub until_single_quote: *const c_void,
    pub until_double_quote: *const c_void,
    pub until_end_of_word: *const c_void,
}

type OnColorBufferProc = extern "C" fn(plugin: Plugin, buffer: *const c_void);
type OnHookProc = extern "C" fn(plugin: Plugin, buffer: Buffer);
type InputGroupProc = extern "C" fn(plugin: Plugin, input_map: InputMap);
type InputActionProc = extern "C" fn(plugin: Plugin);
type WindowDrawProc = extern "C" fn(plugin: Plugin, window: *const c_void);
type WindowFreeProc = extern "C" fn(plugin: Plugin, window: *const c_void);
type WindowGetBufferProc = extern "C" fn(plugin: Plugin, window: *const c_void) -> Buffer;
#[repr(C)]
pub struct Plugin {
    state: *const c_void,
    pub iter_table: IteratorVTable,
    pub buffer_table: BufferVTable,

    pub register_hook: extern "C" fn(hook: Hook, on_hook: OnHookProc),
    pub register_highlighter:
        extern "C" fn(extension: *const c_char, on_color_buffer: OnColorBufferProc),

    pub register_input_group:
        extern "C" fn(input_map: InputMap, key: Key, register_group: InputGroupProc),
    pub register_input: extern "C" fn(
        input_map: InputMap,
        key: Key,
        input_action: InputActionProc,
        description: *const u8,
    ),

    pub create_window: extern "C" fn(
        user_data: *const c_void,
        register_group: InputGroupProc,
        draw_proc: WindowDrawProc,
        free_window_proc: WindowFreeProc,
        get_buffer_proc: *const (),
    ) -> *const c_void,
    get_window: extern "C" fn() -> *const c_void,

    pub request_window_close: extern "C" fn(),
    pub get_screen_width: extern "C" fn() -> isize,
    pub get_screen_height: extern "C" fn() -> isize,
    pub get_font_width: extern "C" fn() -> isize,
    pub get_font_height: extern "C" fn() -> isize,
    get_current_directory: extern "C" fn() -> *const c_char,
    pub enter_insert_mode: extern "C" fn(),

    pub draw_rect: extern "C" fn(x: i32, y: i32, width: i32, height: i32, color: PaletteColor),
    pub draw_text: extern "C" fn(text: *const c_char, x: f32, y: f32, color: PaletteColor),
    pub draw_buffer_from_index: extern "C" fn(
        buffer_index: isize,
        x: isize,
        y: isize,
        glyph_buffer_width: isize,
        glyph_buffer_height: isize,
        show_line_numbers: bool,
    ),
    pub draw_buffer: extern "C" fn(
        buffer: Buffer,
        x: isize,
        y: isize,
        glyph_buffer_width: isize,
        glyph_buffer_height: isize,
        show_line_numbers: bool,
    ),
}

pub struct BufferIter {
    iter: InternalBufferIter,
    iter_table: IteratorVTable,
}

impl BufferIter {
    pub fn new(plugin: Plugin, buffer: Buffer) -> Self {
        let buffer_info = (plugin.buffer_table.get_buffer_info)(buffer);

        Self {
            iter: InternalBufferIter {
                cursor: buffer_info.cursor,
                buffer: buffer.internal,
                hit_end: false,
            },
            iter_table: plugin.iter_table,
        }
    }
}

impl Iterator for BufferIter {
    type Item = char;

    fn next(&mut self) -> Option<Self::Item> {
        let iter_ptr = (&mut self.iter) as *mut InternalBufferIter;

        let result = (self.iter_table.iterate_buffer)(iter_ptr);
        if result.should_continue {
            Some(result.char as char)
        } else {
            None
        }
    }
}

pub struct BufferListIter {
    index: isize,
    next_fn: extern "C" fn(prev_buffer: *const isize) -> isize,
}

impl From<&Plugin> for BufferListIter {
    fn from(value: &Plugin) -> Self {
        BufferListIter {
            index: 0,
            next_fn: value.iter_table.get_buffer_list_iter,
        }
    }
}

impl Iterator for BufferListIter {
    type Item = isize;

    fn next(&mut self) -> Option<Self::Item> {
        if self.index == -1 {
            return None;
        }

        Some((self.next_fn)(&mut self.index))
    }
}

impl Plugin {
    pub fn get_current_directory(&self) -> Cow<str> {
        unsafe {
            let c_str = CStr::from_ptr((self.get_current_directory)());

            c_str.to_string_lossy()
        }
    }

    /// # Safety
    /// If `W` is not the same type as given in `self.create_window`, it will result in undefined
    /// behavior. `W` can also be a different type if another plugin has created a window.
    pub unsafe fn get_window<'a, W>(&self) -> Option<&'a mut W> {
        let window_ptr = (self.get_window)() as *mut W;

        if window_ptr.is_null() {
            None
        } else {
            let window = Box::from_raw(window_ptr);
            Some(Box::leak(window))
        }
    }

    pub fn create_window<W>(
        &self,
        window: W,
        register_group: InputGroupProc,
        draw_proc: WindowDrawProc,
        free_window_proc: WindowFreeProc,
        get_buffer_proc: Option<WindowGetBufferProc>,
    ) {
        let boxed = Box::new(window);
        (self.create_window)(
            Box::into_raw(boxed) as *const std::ffi::c_void,
            register_group,
            draw_proc,
            free_window_proc,
            if let Some(proc) = get_buffer_proc {
                proc as *const ()
            } else {
                std::ptr::null()
            },
        );
    }
    pub fn register_hook(&self, hook: Hook, on_hook: OnHookProc) {
        (self.register_hook)(hook, on_hook)
    }
    pub fn register_input_group(
        &self,
        input_map: Option<InputMap>,
        key: Key,
        register_group: InputGroupProc,
    ) {
        let input_map = match input_map {
            Some(input_map) => input_map,
            None => InputMap {
                internal: std::ptr::null(),
            },
        };

        (self.register_input_group)(input_map, key, register_group);
    }
}

#[repr(i32)]
pub enum Hook {
    BufferInput,
}

#[repr(i32)]
pub enum Key {
    KeyNull = 0, // Key: NULL, used for no key pressed
    // Alphanumeric keys
    Apostrophe = 39,   // key: '
    Comma = 44,        // Key: ,
    Minus = 45,        // Key: -
    Period = 46,       // Key: .
    Slash = 47,        // Key: /
    Zero = 48,         // Key: 0
    One = 49,          // Key: 1
    Two = 50,          // Key: 2
    Three = 51,        // Key: 3
    Four = 52,         // Key: 4
    Five = 53,         // Key: 5
    Six = 54,          // Key: 6
    Seven = 55,        // Key: 7
    Eight = 56,        // Key: 8
    Nine = 57,         // Key: 9
    Semicolon = 59,    // Key: ;
    Equal = 61,        // Key: =
    A = 65,            // Key: A | a
    B = 66,            // Key: B | b
    C = 67,            // Key: C | c
    D = 68,            // Key: D | d
    E = 69,            // Key: E | e
    F = 70,            // Key: F | f
    G = 71,            // Key: G | g
    H = 72,            // Key: H | h
    I = 73,            // Key: I | i
    J = 74,            // Key: J | j
    K = 75,            // Key: K | k
    L = 76,            // Key: L | l
    M = 77,            // Key: M | m
    N = 78,            // Key: N | n
    O = 79,            // Key: O | o
    P = 80,            // Key: P | p
    Q = 81,            // Key: Q | q
    R = 82,            // Key: R | r
    S = 83,            // Key: S | s
    T = 84,            // Key: T | t
    U = 85,            // Key: U | u
    V = 86,            // Key: V | v
    W = 87,            // Key: W | w
    X = 88,            // Key: X | x
    Y = 89,            // Key: Y | y
    Z = 90,            // Key: Z | z
    LeftBracket = 91,  // Key: [
    Backslash = 92,    // Key: '\'
    RightBracket = 93, // Key: ]
    Grave = 96,        // Key: `
    // Function keys
    Space = 32,         // Key: Space
    Escape = 256,       // Key: Esc
    Enter = 257,        // Key: Enter
    Tab = 258,          // Key: Tab
    Backspace = 259,    // Key: Backspace
    Insert = 260,       // Key: Ins
    Delete = 261,       // Key: Del
    Right = 262,        // Key: Cursor right
    Left = 263,         // Key: Cursor left
    Down = 264,         // Key: Cursor down
    Up = 265,           // Key: Cursor up
    PageUp = 266,       // Key: Page up
    PageDown = 267,     // Key: Page down
    Home = 268,         // Key: Home
    End = 269,          // Key: End
    CapsLock = 280,     // Key: Caps lock
    ScrollLock = 281,   // Key: Scroll down
    NumLock = 282,      // Key: Num lock
    PrintScreen = 283,  // Key: Print screen
    Pause = 284,        // Key: Pause
    F1 = 290,           // Key: F1
    F2 = 291,           // Key: F2
    F3 = 292,           // Key: F3
    F4 = 293,           // Key: F4
    F5 = 294,           // Key: F5
    F6 = 295,           // Key: F6
    F7 = 296,           // Key: F7
    F8 = 297,           // Key: F8
    F9 = 298,           // Key: F9
    F10 = 299,          // Key: F10
    F11 = 300,          // Key: F11
    F12 = 301,          // Key: F12
    LeftShift = 340,    // Key: Shift left
    LeftControl = 341,  // Key: Control left
    LeftAlt = 342,      // Key: Alt left
    LeftSuper = 343,    // Key: Super left
    RightShift = 344,   // Key: Shift right
    RightControl = 345, // Key: Control right
    RightAlt = 346,     // Key: Alt right
    RightSuper = 347,   // Key: Super right
    KbMenu = 348,       // Key: KB menu
    // Keypad keys
    Kp0 = 320,        // Key: Keypad 0
    Kp1 = 321,        // Key: Keypad 1
    Kp2 = 322,        // Key: Keypad 2
    Kp3 = 323,        // Key: Keypad 3
    Kp4 = 324,        // Key: Keypad 4
    Kp5 = 325,        // Key: Keypad 5
    Kp6 = 326,        // Key: Keypad 6
    Kp7 = 327,        // Key: Keypad 7
    Kp8 = 328,        // Key: Keypad 8
    Kp9 = 329,        // Key: Keypad 9
    KpDecimal = 330,  // Key: Keypad .
    KpDivide = 331,   // Key: Keypad /
    KpMultiply = 332, // Key: Keypad *
    KpSubtract = 333, // Key: Keypad -
    KpAdd = 334,      // Key: Keypad +
    KpEnter = 335,    // Key: Keypad Enter
    KpEqual = 336,    // Key: Keypad =
    // Android key buttons
    Back = 4,        // Key: Android back button
    VolumeUp = 24,   // Key: Android volume up button
    VolumeDown = 25, // Key: Android volume down button
}

#[repr(i32)]
pub enum PaletteColor {
    Background,
    Foreground,

    Background1,
    Background2,
    Background3,
    Background4,

    Foreground1,
    Foreground2,
    Foreground3,
    Foreground4,

    Red,
    Green,
    Yellow,
    Blue,
    Purple,
    Aqua,
    Gray,

    BrightRed,
    BrightGreen,
    BrightYellow,
    BrightBlue,
    BrightPurple,
    BrightAqua,
    BrightGray,
}
