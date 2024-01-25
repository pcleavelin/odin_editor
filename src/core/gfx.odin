package core

import "core:fmt"
import "vendor:sdl2"
import "vendor:sdl2/ttf"

import "../theme"

scale :: 2;
start_char :: ' ';
end_char :: '~';

FontAtlas :: struct {
    texture: ^sdl2.Texture,
    font: ^ttf.Font,
    max_width: int,
    max_height: int,
}

gen_font_atlas :: proc(state: ^State, path: cstring) -> FontAtlas {
    free_font_atlas(state.font_atlas);

    font_height := i32(state.source_font_height*scale);

    atlas := FontAtlas {
        // FIXME: check if this failed
        font = ttf.OpenFont(path, font_height),
    }
    ttf.SetFontKerning(atlas.font, false);
    ttf.SetFontStyle(atlas.font, ttf.STYLE_NORMAL);
    ttf.SetFontOutline(atlas.font, 0);

    minx, maxx, miny, maxy: i32;
    advanced: i32;
    for char in start_char..=end_char {
        ttf.GlyphMetrics32(atlas.font, char, &minx, &maxx, &miny, &maxy, &advanced);

        width := maxx-minx;
        height := maxy+miny;

        if width > i32(atlas.max_width) {
            atlas.max_width = int(width);
        }
        if height > i32(atlas.max_height) {
            atlas.max_height = int(height);
        }

        // if atlas.max_width%2 != 0 {
        //     atlas.max_width += 1;
        // }
    }

    font_width := i32(atlas.max_width);
    font_height = i32(atlas.max_height);
    state.source_font_width = int(font_width/scale);// int(font_width/scale);
    state.source_font_height = int(font_height/scale);//int(font_height/scale);
    //fmt.println("font_width:", font_width, "font height:", font_height);
    //state.source_font_width = int(f32(font_width)/f32(scale));

    temp_surface: ^sdl2.Surface;
    sdl2.SetHint(sdl2.HINT_RENDER_SCALE_QUALITY, "2");
    // FIXME: check if this failed
    font_surface := sdl2.CreateRGBSurface(0, font_width * (end_char-start_char + 1), font_height, 32, 0xff000000, 0x00ff0000, 0x0000ff00, 0x000000ff);

    rect: sdl2.Rect;

    white := sdl2.Color { 0xff, 0xff, 0xff, 0xff };
    for char, index in start_char..=end_char {
        // ttf.GlyphMetrics32(atlas.font, char, &minx, &maxx, &miny, &maxy, &advanced);

        rect.x = i32(index) * font_width;
        rect.y = 0;//-font_height/8;

        // FIXME: check if this failed
        temp_surface = ttf.RenderGlyph32_Blended(atlas.font, char, white);

        src_rect := sdl2.Rect {
            0,
            0,
            temp_surface.w,
            temp_surface.h
        };
        //fmt.println("char", char, src_rect.x, src_rect.y, src_rect.w, src_rect.h, atlas.max_width, atlas.max_height);

        // FIXME: check if this failed
        sdl2.BlitSurface(temp_surface, &src_rect, font_surface, &rect);
        sdl2.FreeSurface(temp_surface);
    }

    // FIXME: check if this failed
    atlas.texture = sdl2.CreateTextureFromSurface(state.sdl_renderer, font_surface);
    sdl2.SetTextureScaleMode(atlas.texture, .Best);
    // sdl2.SetTextureAlphaMod(atlas.texture, 0xff);
    // sdl2.SetTextureBlendMode(atlas.texture, .BLEND);
    return atlas;
}

free_font_atlas :: proc(font_atlas: FontAtlas) {
    if font_atlas.font != nil {
        ttf.CloseFont(font_atlas.font);
    }
    if font_atlas.texture != nil {
        sdl2.DestroyTexture(font_atlas.texture);
    }
}

draw_rect_outline :: proc(state: ^State, x,y,w,h: int, color: theme.PaletteColor) {
    color := theme.get_palette_color(color);

    sdl2.SetRenderDrawColor(state.sdl_renderer, color.r, color.g, color.b, color.a);
    sdl2.RenderDrawRect(state.sdl_renderer, &sdl2.Rect { i32(x), i32(y), i32(w), i32(h) });
}

draw_rect :: proc(state: ^State, x,y,w,h: int, color: theme.PaletteColor) {
    color := theme.get_palette_color(color);

    sdl2.SetRenderDrawColor(state.sdl_renderer, color.r, color.g, color.b, color.a);
    sdl2.RenderFillRect(state.sdl_renderer, &sdl2.Rect { i32(x), i32(y), i32(w), i32(h) });
}

draw_codepoint :: proc(state: ^State, codepoint: rune, x,y: int, color: theme.PaletteColor) {
    color := theme.get_palette_color(color);

    if codepoint >= start_char && codepoint <= end_char {
        codepoint := codepoint - start_char;

        src_rect := sdl2.Rect {
            x = i32(codepoint) * i32(state.font_atlas.max_width),
            y = 0,
            w = i32(state.font_atlas.max_width),
            h = i32(state.font_atlas.max_height),
        };

        dest_rect := sdl2.Rect {
            x = i32(x),
            y = i32(y),
            w = i32(state.font_atlas.max_width/scale),
            h = i32(state.font_atlas.max_height/scale),
        };

        sdl2.SetTextureColorMod(state.font_atlas.texture, color.r, color.g, color.b);
        sdl2.RenderCopy(state.sdl_renderer, state.font_atlas.texture, &src_rect, &dest_rect);
    }
}

draw_text :: proc(state: ^State, text: string, x,y: int, color: theme.PaletteColor = .Foreground1) {
    for char, idx in text {
        if char < start_char || char > end_char {
            draw_codepoint(state, '?', x + idx * state.source_font_width, y, color);
        } else {
            draw_codepoint(state, char, x + idx * state.source_font_width, y, color);
        }

    }
}
