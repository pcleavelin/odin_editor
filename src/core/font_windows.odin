package core

import strings "core:strings"
import win "core:sys/windows"
import fmt "core:fmt"
import runtime "base:runtime"
import mem "core:mem"
import log "core:log"

import sdl2 "vendor:sdl2"
import ttf "vendor:sdl2/ttf"

foreign import gdi "system:gdi32.lib"

foreign gdi {
    GetFontData :: proc "stdcall" (hdc: win.HDC, dwTable: int, dwOffset: int, pvBuffer: [^]u8, cjBuffer: i32) -> i32 ---
}

SystemFont :: struct {
    display_name: string,
    file_path: string,
    font_w: win.LOGFONTW,
}

FontContext :: struct {
    c: runtime.Context,
    num_fonts: int,
    fonts: []SystemFont,
}

load_default_system_font :: proc(state: ^State, font_height: int) -> FontAtlas {
    fontw := win.LOGFONTW {
        lfHeight = i32(font_height),
        lfWidth = i32(font_height/2),
    }

    c := FontContext {
        c = context,
        fonts = make([]SystemFont, 128),
    }

    hdc := get_hdc_from_sdl_window(state.sdl_window)

    font_data := get_font_data(hdc, fontw)
    rw_ops := sdl2.RWFromMem(raw_data(font_data), i32(len(font_data)))
    font := ttf.OpenFontRW(rw_ops, true, i32(font_height*scale))

    return gen_font_atlas(state, font)
}

load_font :: proc(state: ^State, system_font: SystemFont) -> FontAtlas {
    hdc := get_hdc_from_sdl_window(state.sdl_window)
    font_data := get_font_data(hdc, system_font.font_w)
    if font_data == nil {
        log.error("failed to load font data")
        return state.font_atlas
    }

    free_font_atlas(state.font_atlas);

    rw_ops := sdl2.RWFromMem(raw_data(font_data), i32(len(font_data)))
    font_height := i32(state.source_font_height*scale);

    font := ttf.OpenFontRW(rw_ops, true, font_height)
    atlas := gen_font_atlas(state, font)

    // FIXME: guarantee lifetime of strings inside `system_font`
    state.font = system_font

    return atlas
}

load_system_font_list :: proc(state: ^State, allocator := context.temp_allocator) -> []SystemFont {
    context.allocator = allocator

    fontw := win.LOGFONTW { }

    c := FontContext {
        c = context,
        fonts = make([]SystemFont, 128),
    }

    hdc := get_hdc_from_sdl_window(state.sdl_window)
    win.EnumFontFamiliesExW(hdc, &fontw, check_font_odin, transmute(int)&c, 0)

    return c.fonts
}

get_hdc_from_sdl_window :: proc (window: ^sdl2.Window) -> win.HDC {
    info: sdl2.SysWMinfo
    sdl2.VERSION(&info.version)
    if !sdl2.GetWindowWMInfo(window, &info) {
        return nil
    }

    return win.HDC(info.info.win.hdc)
}

get_font_data :: proc(hdc: win.HDC, fontw: win.LOGFONTW) -> []u8 {
    fontw := fontw
    font := win.CreateFontIndirectW(&fontw)
    win.SelectObject(hdc, transmute(win.HGDIOBJ)font)

    font_size := GetFontData(hdc, 0, 0, nil, 0)
    if font_size < 0 {
        fmt.eprintln("error geting font data size")
        return nil
    }

    buf := make([]u8, font_size)
    r := GetFontData(hdc, 0, 0, raw_data(buf), font_size)
    if r < 0 {
        fmt.eprintln("error loading font")
        return nil
    }

    win.DeleteObject(transmute(win.HGDIOBJ)font)

    return buf
}

@(private)
check_font_odin :: proc (lpelf: ^win.ENUMLOGFONTW, lpntm: ^win.NEWTEXTMETRICW, FontType: u32, lParam: int) -> i32 {
    return check_font(lpelf, lpntm, FontType, lParam)
}

@(private)
check_font :: proc "stdcall" (lpelf: ^win.ENUMLOGFONTW, lpntm: ^win.NEWTEXTMETRICW, FontType: u32, lParam: int) -> i32 {
    c := transmute(^FontContext)lParam
    context = c.c

    name, err := win.wstring_to_utf8(raw_data(lpelf.elfFullName[:]), -1, allocator = c.c.allocator)
    // name, err := win.wstring_to_utf8(raw_data(lpelf.elfLogFont.lfFaceName[:]), -1, allocator = c.c.allocator)
    if err != nil {
        fmt.eprintf("ERROR: %v\n", err)
        return 0
    }

    if c.num_fonts >= len(c.fonts) {
        return 0
    }

    c.fonts[c.num_fonts] = SystemFont {
        display_name = name,
        file_path = name,
        font_w = lpelf.elfLogFont,
    }
    c.num_fonts += 1

    return 1
}
