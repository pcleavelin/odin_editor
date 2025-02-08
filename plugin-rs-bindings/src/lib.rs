use std::{
    borrow::Cow,
    ffi::{c_char, c_void, CStr, CString},
    fmt::write,
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
        let Ok(c_str) = CString::new(path.as_ref().as_os_str().as_encoded_bytes()) else {
            eprintln!("grep plugin failed to open buffer");
            return;
        };
        (self.open_buffer)(c_str.as_ptr() as *const u8, line as isize, col as isize);
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

#[repr(C)]
pub struct UiInteraction {
    pub hovering: bool,
    pub clicked: bool,
}

#[repr(C)]
struct InternalUiSemanticSize {
    kind: isize,
    value: isize,
}

#[repr(isize)]
pub enum UiAxis {
    Horizontal = 0,
    Vertical,
}

pub enum UiSemanticSize {
    FitText,
    Exact(isize),
    ChildrenSum,
    Fill,
    PercentOfParent(isize),
}

impl From<UiSemanticSize> for InternalUiSemanticSize {
    fn from(value: UiSemanticSize) -> Self {
        let (kind, value) = match value {
            UiSemanticSize::FitText => (0, 0),
            UiSemanticSize::Exact(value) => (1, value),
            UiSemanticSize::ChildrenSum => (2, 0),
            UiSemanticSize::Fill => (3, 0),
            UiSemanticSize::PercentOfParent(value) => (4, value),
        };

        Self { kind, value }
    }
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct UiContext(*const c_void);

#[repr(C)]
#[derive(Clone, Copy)]
pub struct UiBox(*const c_void);

type UiPushParentProc = extern "C" fn(ui_context: UiContext, ui_box: UiBox);
type UiPopParentProc = extern "C" fn(ui_context: UiContext);
type UiFloatingProc =
    extern "C" fn(ui_context: UiContext, label: *const i8, pos: [isize; 2]) -> UiBox;
type UiRectProc = extern "C" fn(
    ui_context: UiContext,
    label: *const i8,
    border: bool,
    border: bool,
    axis: UiAxis,
    size: [InternalUiSemanticSize; 2],
) -> UiBox;
type UiSimpleProc = extern "C" fn(ui_context: UiContext, label: *const i8) -> UiInteraction;
type UiBufferProc = extern "C" fn(ui_context: UiContext, buffer: Buffer, show_line_numbers: bool);

#[repr(C)]
pub struct UiVTable {
    ui_context: UiContext,

    push_parent: UiPushParentProc,
    pop_parent: UiPopParentProc,

    spacer: UiSimpleProc,
    floating: UiFloatingProc,
    rect: UiRectProc,

    button: UiSimpleProc,
    label: UiSimpleProc,

    buffer: UiBufferProc,
    buffer_from_index: UiBufferProc,
}

impl UiVTable {
    pub fn push_parent(&self, ui_box: UiBox) {
        (self.push_parent)(self.ui_context, ui_box);
    }
    pub fn pop_parent(&self) {
        (self.pop_parent)(self.ui_context);
    }

    pub fn spacer(&self, label: &CStr) -> UiInteraction {
        (self.spacer)(self.ui_context, label.as_ptr())
    }

    pub fn push_rect(
        &self,
        label: &CStr,
        show_background: bool,
        show_border: bool,
        axis: UiAxis,
        horizontal_size: UiSemanticSize,
        vertical_size: UiSemanticSize,
        inner: impl FnOnce(&UiVTable),
    ) {
        let rect = (self.rect)(
            self.ui_context,
            label.as_ptr(),
            show_background,
            show_border,
            axis,
            [horizontal_size.into(), vertical_size.into()],
        );
        self.push_parent(rect);

        inner(self);

        self.pop_parent();
    }

    pub fn push_floating(&self, label: &CStr, x: isize, y: isize, inner: impl FnOnce(&UiVTable)) {
        let floating = (self.floating)(self.ui_context, label.as_ptr(), [x, y]);
        self.push_parent(floating);

        inner(self);

        self.pop_parent();
    }

    pub fn label(&self, label: &CStr) -> UiInteraction {
        (self.label)(self.ui_context, label.as_ptr())
    }
    pub fn button(&self, label: &CStr) -> UiInteraction {
        (self.button)(self.ui_context, label.as_ptr())
    }

    pub fn buffer(&self, buffer: Buffer, show_line_numbers: bool) {
        (self.buffer)(self.ui_context, buffer, show_line_numbers)
    }
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
    pub ui_table: UiVTable,

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
    UNKNOWN = 0,
    Enter = 13,
    ESCAPE = 27,
    BACKSPACE = 8,
    TAB = 9,
    Space = 32,
    EXCLAIM = 33,
    QUOTEDBL = 34,
    HASH = 35,
    PERCENT = 37,
    DOLLAR = 36,
    AMPERSAND = 38,
    QUOTE = 39,
    LEFTPAREN = 40,
    RIGHTPAREN = 41,
    ASTERISK = 42,
    PLUS = 43,
    COMMA = 44,
    MINUS = 45,
    PERIOD = 46,
    SLASH = 47,
    NUM0 = 48,
    NUM1 = 49,
    NUM2 = 50,
    NUM3 = 51,
    NUM4 = 52,
    NUM5 = 53,
    NUM6 = 54,
    NUM7 = 55,
    NUM8 = 56,
    NUM9 = 57,
    COLON = 58,
    SEMICOLON = 59,
    LESS = 60,
    EQUAL = 61,
    GREATER = 62,
    QUESTION = 63,
    AT = 64,
    LEFTBRACKET = 91,
    BACKSLASH = 92,
    RIGHTBRACKET = 93,
    CARET = 94,
    UNDERSCORE = 95,
    BACKQUOTE = 96,
    A = 97,
    B = 98,
    C = 99,
    D = 100,
    E = 101,
    F = 102,
    G = 103,
    H = 104,
    I = 105,
    J = 106,
    K = 107,
    L = 108,
    M = 109,
    N = 110,
    O = 111,
    P = 112,
    Q = 113,
    R = 114,
    S = 115,
    T = 116,
    U = 117,
    V = 118,
    W = 119,
    X = 120,
    Y = 121,
    Z = 122,
    CAPSLOCK = 1073741881,
    F1 = 1073741882,
    F2 = 1073741883,
    F3 = 1073741884,
    F4 = 1073741885,
    F5 = 1073741886,
    F6 = 1073741887,
    F7 = 1073741888,
    F8 = 1073741889,
    F9 = 1073741890,
    F10 = 1073741891,
    F11 = 1073741892,
    F12 = 1073741893,
    PRINTSCREEN = 1073741894,
    SCROLLLOCK = 1073741895,
    PAUSE = 1073741896,
    INSERT = 1073741897,
    HOME = 1073741898,
    PAGEUP = 1073741899,
    DELETE = 127,
    END = 1073741901,
    PAGEDOWN = 1073741902,
    RIGHT = 1073741903,
    LEFT = 1073741904,
    DOWN = 1073741905,
    UP = 1073741906,
    NUMLOCKCLEAR = 1073741907,
    KpDivide = 1073741908,
    KpMultiply = 1073741909,
    KpMinus = 1073741910,
    KpPlus = 1073741911,
    KpEnter = 1073741912,
    Kp1 = 1073741913,
    Kp2 = 1073741914,
    Kp3 = 1073741915,
    Kp4 = 1073741916,
    Kp5 = 1073741917,
    Kp6 = 1073741918,
    Kp7 = 1073741919,
    Kp8 = 1073741920,
    Kp9 = 1073741921,
    Kp0 = 1073741922,
    KpPeriod = 1073741923,
    APPLICATION = 1073741925,
    POWER = 1073741926,
    KpEquals = 1073741927,
    F13 = 1073741928,
    F14 = 1073741929,
    F15 = 1073741930,
    F16 = 1073741931,
    F17 = 1073741932,
    F18 = 1073741933,
    F19 = 1073741934,
    F20 = 1073741935,
    F21 = 1073741936,
    F22 = 1073741937,
    F23 = 1073741938,
    F24 = 1073741939,
    EXECUTE = 1073741940,
    HELP = 1073741941,
    MENU = 1073741942,
    SELECT = 1073741943,
    STOP = 1073741944,
    AGAIN = 1073741945,
    UNDO = 1073741946,
    CUT = 1073741947,
    COPY = 1073741948,
    PASTE = 1073741949,
    FIND = 1073741950,
    MUTE = 1073741951,
    VOLUMEUP = 1073741952,
    VOLUMEDOWN = 1073741953,
    KpComma = 1073741957,
    KpEqualsas400 = 1073741958,
    ALTERASE = 1073741977,
    SYSREQ = 1073741978,
    CANCEL = 1073741979,
    CLEAR = 1073741980,
    PRIOR = 1073741981,
    RETURN2 = 1073741982,
    SEPARATOR = 1073741983,
    OUT = 1073741984,
    OPER = 1073741985,
    CLEARAGAIN = 1073741986,
    CRSEL = 1073741987,
    EXSEL = 1073741988,
    Kp00 = 1073742000,
    Kp000 = 1073742001,
    THOUSANDSSEPARATOR = 1073742002,
    DECIMALSEPARATOR = 1073742003,
    CURRENCYUNIT = 1073742004,
    CURRENCYSUBUNIT = 1073742005,
    KpLeftparen = 1073742006,
    KpRightparen = 1073742007,
    KpLeftbrace = 1073742008,
    KpRightbrace = 1073742009,
    KpTab = 1073742010,
    KpBackspace = 1073742011,
    KpA = 1073742012,
    KpB = 1073742013,
    KpC = 1073742014,
    KpD = 1073742015,
    KpE = 1073742016,
    KpF = 1073742017,
    KpXor = 1073742018,
    KpPower = 1073742019,
    KpPercent = 1073742020,
    KpLess = 1073742021,
    KpGreater = 1073742022,
    KpAmpersand = 1073742023,
    KpDblampersand = 1073742024,
    KpVerticalbar = 1073742025,
    KpDblverticalbar = 1073742026,
    KpColon = 1073742027,
    KpHash = 1073742028,
    KpSpace = 1073742029,
    KpAt = 1073742030,
    KpExclam = 1073742031,
    KpMemstore = 1073742032,
    KpMemrecall = 1073742033,
    KpMemclear = 1073742034,
    KpMemadd = 1073742035,
    KpMemsubtract = 1073742036,
    KpMemmultiply = 1073742037,
    KpMemdivide = 1073742038,
    KpPlusminus = 1073742039,
    KpClear = 1073742040,
    KpClearentry = 1073742041,
    KpBinary = 1073742042,
    KpOctal = 1073742043,
    KpDecimal = 1073742044,
    KpHexadecimal = 1073742045,
    LCTRL = 1073742048,
    LSHIFT = 1073742049,
    LALT = 1073742050,
    LGUI = 1073742051,
    RCTRL = 1073742052,
    RSHIFT = 1073742053,
    RALT = 1073742054,
    RGUI = 1073742055,
    MODE = 1073742081,
    AUDIONEXT = 1073742082,
    AUDIOPREV = 1073742083,
    AUDIOSTOP = 1073742084,
    AUDIOPLAY = 1073742085,
    AUDIOMUTE = 1073742086,
    MEDIASELECT = 1073742087,
    WWW = 1073742088,
    MAIL = 1073742089,
    CALCULATOR = 1073742090,
    COMPUTER = 1073742091,
    AcSearch = 1073742092,
    AcHome = 1073742093,
    AcBack = 1073742094,
    AcForward = 1073742095,
    AcStop = 1073742096,
    AcRefresh = 1073742097,
    AcBookmarks = 1073742098,
    BRIGHTNESSDOWN = 1073742099,
    BRIGHTNESSUP = 1073742100,
    DISPLAYSWITCH = 1073742101,
    KBDILLUMTOGGLE = 1073742102,
    KBDILLUMDOWN = 1073742103,
    KBDILLUMUP = 1073742104,
    EJECT = 1073742105,
    SLEEP = 1073742106,
    APP1 = 1073742107,
    APP2 = 1073742108,
    AUDIOREWIND = 1073742109,
    AUDIOFASTFORWARD = 1073742110,
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
