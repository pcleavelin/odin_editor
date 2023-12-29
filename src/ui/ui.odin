package ui

import "core:math"
import "vendor:raylib"

import "../core"
import "../theme"

MenuBarItemOnClick :: proc(state: ^core.State, item: ^MenuBarItem);

text_padding :: 4;

MenuBarItem :: struct {
    text: string,
    selected: bool,
    sub_items: []MenuBarItem,
    on_click: MenuBarItemOnClick,
}

MenuBarState :: struct {
    items: []MenuBarItem,
}

draw_menu_bar_item :: proc(item: ^MenuBarItem, x, y: i32, parent_width, parent_height: i32, font: raylib.Font, font_height: int, horizontal: bool = false) {
    foreground_color := theme.PaletteColor.Foreground3;
    if horizontal {
        if item.selected {
            foreground_color = theme.PaletteColor.Background4;
        } else {
            foreground_color = theme.PaletteColor.Foreground4;
        }
    }

    item_text := raylib.TextFormat("%s", item.text);
    item_width := raylib.MeasureTextEx(font, item_text, f32(font_height), 0).x;

    raylib.DrawRectangle(x, y, parent_width, i32(font_height), theme.get_palette_raylib_color(foreground_color));
     raylib.DrawTextEx(font, item_text, raylib.Vector2 { f32(x + text_padding), f32(y) }, f32(font_height), 0, theme.get_palette_raylib_color(.Background1));

    //raylib.DrawRectangle(x, y, i32(item_width) + text_padding*2, i32(1 * font_height), theme.get_palette_raylib_color(.Foreground3));

    if item.selected {
        // TODO: change to parent_width
        largest_sub_item: int
        for sub_item in item.sub_items {
            largest_sub_item = math.max(len(sub_item.text), largest_sub_item);
        }

        this_width := i32(largest_sub_item) * 8 + text_padding*2;
        sub_list_x := x;
        if horizontal {
            //sub_list_x += i32(largest_sub_item) * 8;
            sub_list_x += parent_width;
        }
        for _, index in item.sub_items {
            sub_item := &item.sub_items[index];
            item_text := raylib.TextFormat("%s", sub_item.text);
            item_width := raylib.MeasureTextEx(font, item_text, f32(font_height), 0).x;

            index_offset := 1;
            if horizontal {
                index_offset = 0;
            }
            item_y := y + i32(font_height * (index+index_offset));
            draw_menu_bar_item(sub_item, sub_list_x, item_y, this_width, 0, font, font_height, true);
        }
    }
}

draw_menu_bar :: proc(data: ^MenuBarState, x, y: i32, parent_width, parent_height: i32, font: raylib.Font, font_height: int) {
    raylib.DrawRectangle(x, y, parent_width, i32(font_height), theme.get_palette_raylib_color(.Background3));

    for _, index in data.items {
        item := &data.items[index];
        item_text := raylib.TextFormat("%s", item.text);
        item_width := raylib.MeasureTextEx(font, item_text, f32(font_height), 0).x;

        item_x := x + (i32(item_width) + text_padding*2) * i32(index);
        draw_menu_bar_item(item, item_x, y, i32(item_width + text_padding*2), i32(font_height), font, font_height);
    }
}

test_menu_item :: proc(state: ^core.State, item: ^MenuBarItem, rect: raylib.Rectangle, mouse_pos: raylib.Vector2, mouse_has_clicked: bool, font: raylib.Font, font_height: int, horizontal: bool) -> bool {
    if raylib.CheckCollisionPointRec(mouse_pos, rect) {
        item.selected = true;

        if item.on_click != nil && mouse_has_clicked {
            item.on_click(state, item);
        }
    } else if item.selected {
        largest_sub_item: int
        for sub_item in item.sub_items {
            largest_sub_item = math.max(len(sub_item.text), largest_sub_item);
        }

        this_width := i32(largest_sub_item) * 8 + text_padding*2;
        sub_list_x := rect.x;
        if horizontal {
            sub_list_x += rect.width;
        }

        has_sub_item_selected := false;
        for _, index in item.sub_items {
            sub_item := &item.sub_items[index];
            item_text := raylib.TextFormat("%s", sub_item.text);
            item_width := raylib.MeasureTextEx(font, item_text, f32(font_height), 0).x;

            index_offset := 1;
            if horizontal {
                index_offset = 0;
            }
            item_y := rect.y + f32(font_height * (index+index_offset));

            sub_rec := raylib.Rectangle {
                x = sub_list_x,
                y = item_y,
                width = f32(this_width),
                height = f32(font_height),
            };

           if test_menu_item(state, sub_item, sub_rec, mouse_pos, mouse_has_clicked, font, font_height, true) {
               has_sub_item_selected = true;
           }
        }

        item.selected = has_sub_item_selected;
    } else {
        item.selected = false;
    }

    return item.selected;
}

test_menu_bar :: proc(state: ^core.State, menu_bar: ^MenuBarState, x, y: i32, mouse_pos: raylib.Vector2, mouse_has_clicked: bool, font: raylib.Font, font_height: int) {
    for _, index in menu_bar.items {
        item := &menu_bar.items[index];
        item_text := raylib.TextFormat("%s", item.text);
        item_width := raylib.MeasureTextEx(font, item_text, f32(font_height), 0).x;

        item_rec := raylib.Rectangle {
            x = f32(x) + (item_width + f32(text_padding*2)) * f32(index),
            y = f32(y),
            width = f32(item_width + text_padding*2),
            height = f32(font_height),
        };

        test_menu_item(state, item, item_rec, mouse_pos, mouse_has_clicked, font, font_height, false);
    }
}
