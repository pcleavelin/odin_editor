package core

import "vendor:raylib"

Mode :: enum {
    Normal,
    Insert,
}

State :: struct {
    mode: Mode,
    should_close: bool,
    screen_height: i32,
    screen_width: i32,
    font: raylib.Font,

    current_buffer: int,
    buffers: [dynamic]FileBuffer,

    buffer_list_window_is_visible: bool,
    buffer_list_window_selected_buffer: int,
}
