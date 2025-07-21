package theme

PaletteColor :: enum {
    None,
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

// Its the gruvbox dark theme <https://github.com/morhetz/gruvbox>
palette := []u32 {
    0x00000000,
    0x282828ff,
    0xebdbb2ff,

    0x3c3836ff,
    0x504945ff,
    0x665c54ff,
    0x7c6f64ff,

    0xfbf1c7ff,
    0xebdbb2ff,
    0xd5c4a1ff,
    0xbdae93ff,

    0xcc241dff,
    0x98981aff,
    0xd79921ff,
    0x458588ff,
    0xb16286ff,
    0x689d6aff,
    0xa89984ff,

    0xfb4934ff,
    0xb8bb26ff,
    0xfabd2fff,
    0x83a598ff,
    0xd3869bff,
    0x8ec07cff,
    0x928374ff,
};


light_palette := []u32 {
    0x00000000,
    0xfbf1c7ff,
    0x3c3836ff,

    0xebdbb2ff,
    0xd5c4a1ff,
    0xbdae93ff,
    0xa89984ff,

    0x3c3836ff,
    0x504945ff,
    0x665c54ff,
    0x7c6f64ff,

    0xcc241dff,
    // FIXME: change this back to not e transparent
    0x98971a33,
    0xd79921ff,
    0x458588ff,
    0xb16286ff,
    0x689d6aff,
    0x7c6f64ff,

    0x9d0006ff,
    0x79740eff,
    0xb57614ff,
    0x076678ff,
    0x8f3f71ff,
    0x427b58ff,
    0x928374ff,
};

get_palette_color :: proc(palette_color: PaletteColor) -> [4]u8 {
    color: [4]u8;

    c := light_palette[palette_color];
    for i in 0..<4 {
        color[i] = u8((c >> (8*u32(3-i)))&0xff);
    }

    return color;
}

