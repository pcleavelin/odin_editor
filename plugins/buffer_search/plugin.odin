// A simple window to view/search open buffers
package buffer_search;

import "core:runtime"
import "core:fmt"
import "core:path/filepath"

import p "../../src/plugin"
import "../../src/theme"

Plugin :: p.Plugin;
Iterator :: p.Iterator;
BufferIter :: p.BufferIter;
BufferIndex :: p.BufferIndex;
Key :: p.Key;

BufferListWindow :: struct {
    selected_index: int,
}

@export
OnInitialize :: proc "c" (plugin: Plugin) {
    context = runtime.default_context();
    fmt.println("builtin buffer search plugin initialized!");

    plugin.register_input_group(nil, .SPACE, proc "c" (plugin: Plugin, input_map: rawptr) {
        plugin.register_input(input_map, .B, open_buffer_window, "show list of open buffers");
    });
}

@export
OnExit :: proc "c" (plugin: Plugin) {
    context = runtime.default_context();
}

open_buffer_window :: proc "c" (plugin: Plugin) {
    context = runtime.default_context();

    window := new(BufferListWindow);
    window^ = BufferListWindow {};

    plugin.create_window(window, proc "c" (plugin: Plugin, input_map: rawptr) {
        plugin.register_input(input_map, .K, proc "c" (plugin: Plugin) {
            context = runtime.default_context();

            win := cast(^BufferListWindow)plugin.get_window();
            if win != nil {
                if win.selected_index > 0 {
                    win.selected_index -= 1;
                } else {
                    win.selected_index = plugin.buffer.get_num_buffers()-1;
                }
            }
        }, "move selection up");
        plugin.register_input(input_map, .J, proc "c" (plugin: Plugin) {
            context = runtime.default_context();

            win := cast(^BufferListWindow)plugin.get_window();
            if win != nil {
                if win.selected_index < plugin.buffer.get_num_buffers()-1 {
                    win.selected_index += 1;
                } else {
                    win.selected_index = 0;
                }
            }
        }, "move selection down");
        plugin.register_input(input_map, .ENTER, proc "c" (plugin: Plugin) {
            context = runtime.default_context();

            win := cast(^BufferListWindow)plugin.get_window();
            if win != nil {
                plugin.buffer.set_current_buffer(win.selected_index);
            }

            plugin.request_window_close();
        }, "switch to buffer")
    }, draw_buffer_window, free_buffer_window, nil);
}

free_buffer_window :: proc "c" (plugin: Plugin, win: rawptr) {
    context = runtime.default_context();
    win := cast(^BufferListWindow)plugin.get_window();
    if win == nil {
        return;
    }

    free(win);
}

buffer_list_iter :: proc(plugin: Plugin, buffer_index: ^int) -> (int, int, bool) {
    if buffer_index^ == -1 {
        return 0, 0, false;
    }

    index := plugin.iter.get_buffer_list_iter(buffer_index);
    return index, 0, true;
}

draw_buffer_window :: proc "c" (plugin: Plugin, win: rawptr) {
    context = runtime.default_context();
    runtime.free_all(context.temp_allocator);

    win := cast(^BufferListWindow)win;
    if win == nil {
        return;
    }

    screen_width := plugin.get_screen_width();
    screen_height := plugin.get_screen_height();
    directory := string(plugin.get_current_directory());

    canvas := plugin.ui.floating(plugin.ui.ui_context, "buffer search canvas", {0,0});

    plugin.ui.push_parent(plugin.ui.ui_context, canvas);
    {
        defer plugin.ui.pop_parent(plugin.ui.ui_context);

        plugin.ui.spacer(plugin.ui.ui_context, "left spacer");
        centered_container := plugin.ui.rect(plugin.ui.ui_context, "centered container", false, false, .Vertical, {{4, 75}, {3, 0}});
        plugin.ui.push_parent(plugin.ui.ui_context, centered_container);
        {
            defer plugin.ui.pop_parent(plugin.ui.ui_context);

            plugin.ui.spacer(plugin.ui.ui_context, "top spacer");
            ui_window := plugin.ui.rect(plugin.ui.ui_context, "buffer search window", true, true, .Horizontal, {{3, 0}, {4, 75}});
            plugin.ui.push_parent(plugin.ui.ui_context, ui_window);
            {
                defer plugin.ui.pop_parent(plugin.ui.ui_context);

                buffer_list_view := plugin.ui.rect(plugin.ui.ui_context, "buffer list view", false, false, .Vertical, {{4, 60}, {3, 0}});
                plugin.ui.push_parent(plugin.ui.ui_context, buffer_list_view);
                {
                    defer plugin.ui.pop_parent(plugin.ui.ui_context);

                    _buffer_index := 0;
                    for index in buffer_list_iter(plugin, &_buffer_index) {
                        buffer := plugin.buffer.get_buffer_info_from_index(index);
                        relative_file_path, _ := filepath.rel(directory, string(buffer.file_path), context.temp_allocator)
                        text := fmt.ctprintf("%s:%d", relative_file_path, buffer.cursor.line+1);

                        if index == win.selected_index {
                            plugin.ui.button(plugin.ui.ui_context, text);
                        } else {
                            plugin.ui.label(plugin.ui.ui_context, text);
                        }
                    }
                }

                buffer_preview := plugin.ui.rect(plugin.ui.ui_context, "buffer preview", true, false, .Horizontal, {{3, 0}, {3, 0}});
                plugin.ui.push_parent(plugin.ui.ui_context, buffer_preview);
                {
                    defer plugin.ui.pop_parent(plugin.ui.ui_context);

                    plugin.ui.buffer_from_index(plugin.ui.ui_context, win.selected_index, false);
                }
            }
            plugin.ui.spacer(plugin.ui.ui_context, "bottom spacer");
        }
        plugin.ui.spacer(plugin.ui.ui_context, "right spacer");
    }

    /*
    screen_width := plugin.get_screen_width();
    screen_height := plugin.get_screen_height();
    source_font_width := plugin.get_font_width();
    source_font_height := plugin.get_font_height();

    win_rec := [4]f32 {
        f32(screen_width/8),
        f32(screen_height/8),
        f32(screen_width - screen_width/4),
        f32(screen_height - screen_height/4),
    };
    plugin.draw_rect(
        i32(win_rec.x),
        i32(win_rec.y),
        i32(win_rec.z),
        i32(win_rec.w),
        .Background4
    );

    win_margin := [2]f32 { f32(source_font_width), f32(source_font_height) };

    buffer_prev_width := (win_rec.z - win_margin.x*2) / 2;
    buffer_prev_height := win_rec.w - win_margin.y*2;

    glyph_buffer_width := int(buffer_prev_width) / source_font_width - 1;
    glyph_buffer_height := int(buffer_prev_height) / source_font_height;

    directory := string(plugin.get_current_directory());

    plugin.draw_rect(
        i32(win_rec.x + win_rec.z / 2),
        i32(win_rec.y + win_margin.y),
        i32(buffer_prev_width),
        i32(buffer_prev_height),
        .Background2,
    );

    _buffer_index := 0;
    for index in buffer_list_iter(plugin, &_buffer_index) {
        buffer := plugin.buffer.get_buffer_info_from_index(index);
        relative_file_path, _ := filepath.rel(directory, string(buffer.file_path), context.temp_allocator)
        text := fmt.ctprintf("%s:%d", relative_file_path, buffer.cursor.line+1);
        text_width := len(text) * source_font_width;

        if index == win.selected_index {
            plugin.draw_buffer_from_index(
                index,
                int(win_rec.x + win_margin.x + win_rec.z / 2),
                int(win_rec.y + win_margin.y),
                glyph_buffer_width,
                glyph_buffer_height,
                false);

            plugin.draw_rect(
                i32(win_rec.x + win_margin.x),
                i32(win_rec.y + win_margin.y) + i32(index * source_font_height),
                i32(text_width),
                i32(source_font_height),
                .Background2,
            );
        }

        plugin.draw_text(
            text,
            win_rec.x + win_margin.x, win_rec.y + win_margin.y + f32(index * source_font_height),
            .Foreground2
        );

        runtime.free_all(context.temp_allocator);
    }
    */
}
