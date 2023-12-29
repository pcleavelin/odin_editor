package core

Mode :: enum {
    Normal,
    Insert,
}

State :: struct {
    mode: Mode,
    should_close: bool,
}
