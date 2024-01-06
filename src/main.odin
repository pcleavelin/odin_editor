package main

import "core:os"
import "core:path/filepath"
import "core:math"
import "core:strings"
import "core:runtime"
import "core:fmt"
import "core:mem"
import "core:slice"
import "vendor:raylib"

import "core"
import "theme"
import "ui"
import "plugin"

State :: core.State;
FileBuffer :: core.FileBuffer;

state := core.State {};

// TODO: use buffer list in state
do_normal_mode :: proc(state: ^State, buffer: ^FileBuffer) {
    if state.current_input_map != nil {
        if raylib.IsKeyPressed(.ESCAPE) {
            core.request_window_close(state);
        } else if raylib.IsKeyDown(.LEFT_CONTROL) {
            for key, action in &state.current_input_map.ctrl_key_actions {
                if raylib.IsKeyPressed(key) {
                    switch value in action.action {
                        case core.PluginEditorAction:
                            value(state.plugin_vtable);
                        case core.EditorAction:
                            value(state);
                        case core.InputMap:
                            state.current_input_map = &(&state.current_input_map.ctrl_key_actions[key]).action.(core.InputMap)
                    }
                }
            }
        } else {
            for key, action in state.current_input_map.key_actions {
                if raylib.IsKeyPressed(key) {
                    switch value in action.action {
                        case core.PluginEditorAction:
                            value(state.plugin_vtable);
                        case core.EditorAction:
                            value(state);
                        case core.InputMap:
                            state.current_input_map = &(&state.current_input_map.key_actions[key]).action.(core.InputMap)
                    }
                }
            }
        }
    }
}

// TODO: use buffer list in state
do_insert_mode :: proc(state: ^State, buffer: ^FileBuffer) {
    key := raylib.GetCharPressed();

    for key > 0 {
        if key >= 32 && key <= 125 && len(buffer.input_buffer) < 1024-1 {
            append(&buffer.input_buffer, u8(key));
        }

        key = raylib.GetCharPressed();
    }

    if raylib.IsKeyPressed(.ENTER) {
        append(&buffer.input_buffer, '\n');
    }

    if raylib.IsKeyPressed(.ESCAPE) {
        state.mode = .Normal;

        core.insert_content(buffer, buffer.input_buffer[:]);
        runtime.clear(&buffer.input_buffer);
        return;
    }

    if raylib.IsKeyPressed(.BACKSPACE) {
        core.delete_content(buffer, 1);
    }
}

switch_to_buffer :: proc(state: ^State, item: ^ui.MenuBarItem) {
    for buffer, index in state.buffers {
        if strings.compare(buffer.file_path, item.text) == 0 {
            state.current_buffer = index;
            break;
        }
    }
}

register_default_leader_actions :: proc(input_map: ^core.InputMap) {
    // core.register_key_action(input_map, .B, proc(state: ^State) {
    //     state.window = ui.create_buffer_list_window();
    //     state.current_input_map = &state.window.input_map;
    // }, "show list of open buffers");
    core.register_key_action(input_map, .R, proc(state: ^State) {
        state.window = ui.create_grep_window();
        state.current_input_map = &state.window.input_map;
        state.mode = .Insert;
    }, "live grep");
    core.register_key_action(input_map, .Q, proc(state: ^State) {
        state.current_input_map = &state.input_map;
    }, "close this help");
}

register_default_go_actions :: proc(input_map: ^core.InputMap) {
    core.register_key_action(input_map, .H, proc(state: ^State) {
        core.move_cursor_start_of_line(&state.buffers[state.current_buffer]);
        state.current_input_map = &state.input_map;
    }, "move to beginning of line");
    core.register_key_action(input_map, .L, proc(state: ^State) {
        core.move_cursor_end_of_line(&state.buffers[state.current_buffer]);
        state.current_input_map = &state.input_map;
    }, "move to end of line");
}

register_default_input_actions :: proc(input_map: ^core.InputMap) {
    // Cursor Movement
    {
        core.register_key_action(input_map, .W, proc(state: ^State) {
            core.move_cursor_forward_start_of_word(&state.buffers[state.current_buffer]);
        }, "move forward one word");
        core.register_key_action(input_map, .E, proc(state: ^State) {
            core.move_cursor_forward_end_of_word(&state.buffers[state.current_buffer]);
        }, "move forward to end of word");

        core.register_key_action(input_map, .B, proc(state: ^State) {
            core.move_cursor_backward_start_of_word(&state.buffers[state.current_buffer]);
        }, "move backward one word");

        core.register_key_action(input_map, .K, proc(state: ^State) {
            core.move_cursor_up(&state.buffers[state.current_buffer]);
        }, "move up one line");
        core.register_key_action(input_map, .J, proc(state: ^State) {
            core.move_cursor_down(&state.buffers[state.current_buffer]);
        }, "move down one line");
        core.register_key_action(input_map, .H, proc(state: ^State) {
            core.move_cursor_left(&state.buffers[state.current_buffer]);
        }, "move left one char");
        core.register_key_action(input_map, .L, proc(state: ^State) {
            core.move_cursor_right(&state.buffers[state.current_buffer]);
        }, "move right one char");

        core.register_ctrl_key_action(input_map, .U, proc(state: ^State) {
            core.scroll_file_buffer(&state.buffers[state.current_buffer], .Up);
        }, "scroll buffer up");
        core.register_ctrl_key_action(input_map, .D, proc(state: ^State) {
            core.scroll_file_buffer(&state.buffers[state.current_buffer], .Down);
        }, "scroll buffer up");
    }

    // Scale font size
    {
        core.register_ctrl_key_action(input_map, .MINUS, proc(state: ^State) {
            if state.source_font_height > 16 {
                state.source_font_height -= 2;
                state.source_font_width = state.source_font_height / 2;

                state.font = raylib.LoadFontEx("/System/Library/Fonts/Supplemental/Andale Mono.ttf", i32(state.source_font_height*2), nil, 0);
                raylib.SetTextureFilter(state.font.texture, .BILINEAR);
            }
        }, "increase font size");
        core.register_ctrl_key_action(input_map, .EQUAL, proc(state: ^State) {
            state.source_font_height += 2;
            state.source_font_width = state.source_font_height / 2;

            state.font = raylib.LoadFontEx("/System/Library/Fonts/Supplemental/Andale Mono.ttf", i32(state.source_font_height*2), nil, 0);
            raylib.SetTextureFilter(state.font.texture, .BILINEAR);
        }, "decrease font size");
    }

    // Inserting Text
    {
        core.register_key_action(input_map, .I, proc(state: ^State) {
            state.mode = .Insert;
        }, "enter insert mode");
        core.register_key_action(input_map, .A, proc(state: ^State) {
            core.move_cursor_right(&state.buffers[state.current_buffer], false);
            state.mode = .Insert;
        }, "enter insert mode after character (append)");
    }

    core.register_key_action(input_map, .SPACE, core.new_input_map(), "leader commands");
    register_default_leader_actions(&(&input_map.key_actions[.SPACE]).action.(core.InputMap));

    core.register_key_action(input_map, .G, core.new_input_map(), "Go commands");
    register_default_go_actions(&(&input_map.key_actions[.G]).action.(core.InputMap));
}

load_plugin :: proc(info: os.File_Info, in_err: os.Errno, state: rawptr) -> (err: os.Errno, skip_dir: bool) {
    state := cast(^State)state;

    relative_file_path, rel_error := filepath.rel(state.directory, info.fullpath);
    extension := filepath.ext(info.fullpath);

    if extension == ".dylib" || extension == ".dll" || extension == ".so" {
        if loaded_plugin, succ := plugin.try_load_plugin(info.fullpath); succ {
            append(&state.plugins, loaded_plugin);

            if rel_error == .None {
                fmt.println("Loaded", relative_file_path);
            } else {
                fmt.println("Loaded", info.fullpath);
            }
        }
    }

    return in_err, skip_dir;
}

main :: proc() {
    state = State {
        ctx = context,
        source_font_width = 8,
        source_font_height = 16,
        input_map = core.new_input_map(),
        window = nil,
        directory = os.get_current_directory(),
        plugins = make([dynamic]plugin.Interface),
        highlighters = make(map[string]plugin.OnColorBufferProc),
    };
    state.plugin_vtable = plugin.Plugin {
        state = cast(rawptr)&state,
        register_highlighter = proc "c" (extension: cstring, on_color_buffer: plugin.OnColorBufferProc) {
            context = state.ctx;

            extension := strings.clone(string(extension));

            if _, exists := state.highlighters[extension]; exists {
                fmt.eprintln("Highlighter already registered for", extension, "files");
            } else {
                state.highlighters[extension] = on_color_buffer;
            }
        },
        register_input_group = proc "c" (input_map: rawptr, key: plugin.Key, register_group: plugin.InputGroupProc) {
            context = state.ctx;

            to_be_edited_map: ^core.InputMap = nil;
            key := raylib.KeyboardKey(int(key));

            if input_map != nil {
                to_be_edited_map = transmute(^core.InputMap)input_map;
            } else {
                to_be_edited_map = state.current_input_map;
            }

            if action, exists := to_be_edited_map.key_actions[key]; exists {
                switch value in action.action {
                    case core.PluginEditorAction:
                        fmt.eprintln("Plugin attempted to register input group on existing key action (added from Plugin)");
                    case core.EditorAction:
                        fmt.eprintln("Plugin attempted to register input group on existing key action");
                    case core.InputMap:
                        input_map := &(&to_be_edited_map.key_actions[key]).action.(core.InputMap);
                        register_group(state.plugin_vtable, transmute(rawptr)input_map);
                }
            } else {
                core.register_key_action(to_be_edited_map, key, core.new_input_map(), "PLUGIN INPUT GROUP");
                register_group(state.plugin_vtable, &(&to_be_edited_map.key_actions[key]).action.(core.InputMap));
            }
        },
        register_input = proc "c" (input_map: rawptr, key: plugin.Key, input_action: plugin.InputActionProc, description: cstring) {
            context = state.ctx;

            to_be_edited_map: ^core.InputMap = nil;
            key := raylib.KeyboardKey(int(key));
            description := strings.clone(string(description));

            if input_map != nil {
                to_be_edited_map = transmute(^core.InputMap)input_map;
            } else {
                to_be_edited_map = state.current_input_map;
            }

            if action, exists := to_be_edited_map.key_actions[key]; exists {
                switch value in action.action {
                    case core.PluginEditorAction:
                        fmt.eprintln("Plugin attempted to register key action on existing key action (added from Plugin)");
                    case core.EditorAction:
                        fmt.eprintln("Plugin attempted to register input key action on existing key action");
                    case core.InputMap:
                        fmt.eprintln("Plugin attempted to register input key action on existing input group");
                }
            } else {
                core.register_key_action(to_be_edited_map, key, input_action, description);
            }
        },
        create_window = proc "c" (register_group: plugin.InputGroupProc, draw_proc: plugin.WindowDrawProc) -> rawptr {
            context = state.ctx;
            window := new(core.Window);
            window^ = core.Window {
                input_map = core.new_input_map(),
                draw = draw_proc,
            };

            register_group(state.plugin_vtable, transmute(rawptr)&window.input_map);

            state.window = window;
            state.current_input_map = &window.input_map;

            return window;
        },
        draw_rect = raylib.DrawRectangle,
        iter = plugin.Iterator {
            get_current_buffer_iterator = proc "c" () -> plugin.BufferIter {
                context = state.ctx;

                it := core.new_file_buffer_iter(&state.buffers[state.current_buffer]);

                // TODO: make this into a function
                return plugin.BufferIter {
                    cursor = plugin.Cursor {
                        col = it.cursor.col,
                        line = it.cursor.line,
                        index = plugin.BufferIndex {
                            slice_index = it.cursor.index.slice_index,
                            content_index = it.cursor.index.content_index,
                        }
                    },
                    buffer = cast(rawptr)it.buffer,
                    hit_end = it.hit_end,
                }
            },
            get_buffer_iterator = proc "c" (buffer: rawptr) -> plugin.BufferIter {
                buffer := cast(^core.FileBuffer)buffer;
                context = state.ctx;

                it := core.new_file_buffer_iter(buffer);

                // TODO: make this into a function
                return plugin.BufferIter {
                    cursor = plugin.Cursor {
                        col = it.cursor.col,
                        line = it.cursor.line,
                        index = plugin.BufferIndex {
                            slice_index = it.cursor.index.slice_index,
                            content_index = it.cursor.index.content_index,
                        }
                    },
                    buffer = cast(rawptr)it.buffer,
                    hit_end = it.hit_end,
                }
            },
            get_char_at_iter = proc "c" (it: ^plugin.BufferIter) -> u8 {
                context = state.ctx;

                internal_it := core.FileBufferIter {
                    cursor = core.Cursor {
                        col = it.cursor.col,
                        line = it.cursor.line,
                        index = core.FileBufferIndex {
                            slice_index = it.cursor.index.slice_index,
                            content_index = it.cursor.index.content_index,
                        }
                    },
                    buffer = cast(^core.FileBuffer)it.buffer,
                    hit_end = it.hit_end,
                }

                return core.get_character_at_iter(internal_it);
            },
            iterate_buffer = proc "c" (it: ^plugin.BufferIter) -> plugin.IterateResult {
                context = state.ctx;

                // TODO: make this into a function
                internal_it := core.FileBufferIter {
                    cursor = core.Cursor {
                        col = it.cursor.col,
                        line = it.cursor.line,
                        index = core.FileBufferIndex {
                            slice_index = it.cursor.index.slice_index,
                            content_index = it.cursor.index.content_index,
                        }
                    },
                    buffer = cast(^core.FileBuffer)it.buffer,
                    hit_end = it.hit_end,
                }

                char, _, cond := core.iterate_file_buffer(&internal_it);

                it^ = plugin.BufferIter {
                    cursor = plugin.Cursor {
                        col = internal_it.cursor.col,
                        line = internal_it.cursor.line,
                        index = plugin.BufferIndex {
                            slice_index = internal_it.cursor.index.slice_index,
                            content_index = internal_it.cursor.index.content_index,
                        }
                    },
                    buffer = cast(rawptr)internal_it.buffer,
                    hit_end = internal_it.hit_end,
                };

                return plugin.IterateResult {
                    char = char,
                    should_stop = cond,
                };
            },
            iterate_buffer_reverse = proc "c" (it: ^plugin.BufferIter) -> plugin.IterateResult {
                context = state.ctx;

                // TODO: make this into a function
                internal_it := core.FileBufferIter {
                    cursor = core.Cursor {
                        col = it.cursor.col,
                        line = it.cursor.line,
                        index = core.FileBufferIndex {
                            slice_index = it.cursor.index.slice_index,
                            content_index = it.cursor.index.content_index,
                        }
                    },
                    buffer = cast(^core.FileBuffer)it.buffer,
                    hit_end = it.hit_end,
                }

                char, _, cond := core.iterate_file_buffer_reverse(&internal_it);

                it^ = plugin.BufferIter {
                    cursor = plugin.Cursor {
                        col = internal_it.cursor.col,
                        line = internal_it.cursor.line,
                        index = plugin.BufferIndex {
                            slice_index = internal_it.cursor.index.slice_index,
                            content_index = internal_it.cursor.index.content_index,
                        }
                    },
                    buffer = cast(rawptr)internal_it.buffer,
                    hit_end = internal_it.hit_end,
                };

                return plugin.IterateResult {
                    char = char,
                    should_stop = cond,
                };
            },
            iterate_buffer_until = proc "c" (it: ^plugin.BufferIter, until_proc: rawptr) {
                context = state.ctx;

                // TODO: make this into a function
                internal_it := core.FileBufferIter {
                    cursor = core.Cursor {
                        col = it.cursor.col,
                        line = it.cursor.line,
                        index = core.FileBufferIndex {
                            slice_index = it.cursor.index.slice_index,
                            content_index = it.cursor.index.content_index,
                        }
                    },
                    buffer = cast(^core.FileBuffer)it.buffer,
                    hit_end = it.hit_end,
                }

                core.iterate_file_buffer_until(&internal_it, transmute(core.UntilProc)until_proc);

                it^ = plugin.BufferIter {
                    cursor = plugin.Cursor {
                        col = internal_it.cursor.col,
                        line = internal_it.cursor.line,
                        index = plugin.BufferIndex {
                            slice_index = internal_it.cursor.index.slice_index,
                            content_index = internal_it.cursor.index.content_index,
                        }
                    },
                    buffer = cast(rawptr)internal_it.buffer,
                    hit_end = internal_it.hit_end,
                };
            },
            iterate_buffer_peek = proc "c" (it: ^plugin.BufferIter) -> plugin.IterateResult {
                context = state.ctx;

                // TODO: make this into a function
                internal_it := core.FileBufferIter {
                    cursor = core.Cursor {
                        col = it.cursor.col,
                        line = it.cursor.line,
                        index = core.FileBufferIndex {
                            slice_index = it.cursor.index.slice_index,
                            content_index = it.cursor.index.content_index,
                        }
                    },
                    buffer = cast(^core.FileBuffer)it.buffer,
                    hit_end = it.hit_end,
                }

                char, _, cond := core.iterate_peek(&internal_it, core.iterate_file_buffer);

                it^ = plugin.BufferIter {
                    cursor = plugin.Cursor {
                        col = internal_it.cursor.col,
                        line = internal_it.cursor.line,
                        index = plugin.BufferIndex {
                            slice_index = internal_it.cursor.index.slice_index,
                            content_index = internal_it.cursor.index.content_index,
                        }
                    },
                    buffer = cast(rawptr)internal_it.buffer,
                    hit_end = internal_it.hit_end,
                };

                return plugin.IterateResult {
                    char = char,
                    should_stop = cond,
                };
            },
            until_line_break = transmute(rawptr)core.until_line_break,
            until_single_quote = transmute(rawptr)core.until_single_quote,
            until_double_quote = transmute(rawptr)core.until_double_quote,
            until_end_of_word = transmute(rawptr)core.until_end_of_word,
        },
        buffer = plugin.Buffer {
            get_buffer_info = proc "c" () -> plugin.BufferInfo {
                context = state.ctx;

                buffer := &state.buffers[state.current_buffer];

                return plugin.BufferInfo {
                    glyph_buffer_width = buffer.glyph_buffer_width,
                    glyph_buffer_height = buffer.glyph_buffer_height,
                    top_line = buffer.top_line,
                };
            },
            color_char_at = proc "c" (buffer: rawptr, start_cursor: plugin.Cursor, end_cursor: plugin.Cursor, palette_index: i32) {
                buffer := cast(^core.FileBuffer)buffer;
                context = state.ctx;

                start_cursor := core.Cursor {
                    col = start_cursor.col,
                    line = start_cursor.line,
                    index = core.FileBufferIndex {
                        slice_index = start_cursor.index.slice_index,
                        content_index = start_cursor.index.content_index,
                    }
                };
                end_cursor := core.Cursor {
                    col = end_cursor.col,
                    line = end_cursor.line,
                    index = core.FileBufferIndex {
                        slice_index = end_cursor.index.slice_index,
                        content_index = end_cursor.index.content_index,
                    }
                };

                core.color_character(buffer, start_cursor, end_cursor, cast(theme.PaletteColor)palette_index);
            }
        }
    };
    state.current_input_map = &state.input_map;
    register_default_input_actions(&state.input_map);

    for arg in os.args[1:] {
        buffer, err := core.new_file_buffer(context.allocator, arg, state.directory);
        if err.type != .None {
            fmt.println("Failed to create file buffer:", err);
            continue;
        }

        runtime.append(&state.buffers, buffer);
    }
    buffer_items := make([dynamic]ui.MenuBarItem, 0, len(state.buffers));
    for buffer, index in state.buffers {
        item := ui.MenuBarItem {
            text = buffer.file_path,
            on_click = switch_to_buffer,
        };

        runtime.append(&buffer_items, item);
    }

    // Load plugins
    filepath.walk(filepath.join({ state.directory, "bin" }), load_plugin, transmute(rawptr)&state);

    for plugin in state.plugins {
        if plugin.on_initialize != nil {
            plugin.on_initialize(state.plugin_vtable);
        }
    }

    raylib.InitWindow(640, 480, "odin_editor - [back to basics]");
    raylib.SetWindowState({ .WINDOW_RESIZABLE, .VSYNC_HINT });
    raylib.SetTargetFPS(60);
    raylib.SetExitKey(.KEY_NULL);

    // TODO: don't just hard code a MacOS font path
    state.font = raylib.LoadFontEx("/System/Library/Fonts/Supplemental/Andale Mono.ttf", i32(state.source_font_height*2), nil, 0);
    raylib.SetTextureFilter(state.font.texture, .BILINEAR);
    menu_bar_state := ui.MenuBarState{
        items = []ui.MenuBarItem {
            ui.MenuBarItem {
                text = "Buffers",
                sub_items = buffer_items[:],
            }
        }
    };

    for !raylib.WindowShouldClose() && !state.should_close {
        state.screen_width = int(raylib.GetScreenWidth());
        state.screen_height = int(raylib.GetScreenHeight());
        mouse_pos := raylib.GetMousePosition();

        buffer := &state.buffers[state.current_buffer];

        buffer.glyph_buffer_height = math.min(256, int((state.screen_height - state.source_font_height*2) / state.source_font_height)) + 1;
        buffer.glyph_buffer_width = math.min(256, int((state.screen_width - state.source_font_width) / state.source_font_width));

        {
            raylib.BeginDrawing();
            defer raylib.EndDrawing();

            raylib.ClearBackground(theme.get_palette_raylib_color(.Background));

            // TODO: be more granular in /what/ is being draw by the plugin
            for plugin in state.plugins {
                if plugin.on_initialize != nil {
                    //plugin.on_draw(plugin.plugin);
                }
            }

            core.draw_file_buffer(&state, buffer, 32, state.source_font_height, state.font);
            ui.draw_menu_bar(&state, &menu_bar_state, 0, 0, i32(state.screen_width), i32(state.screen_height), state.source_font_height);

            raylib.DrawRectangle(0, i32(state.screen_height - state.source_font_height), i32(state.screen_width), i32(state.source_font_height), theme.get_palette_raylib_color(.Background2));

            line_info_text := raylib.TextFormat(
                // "Line: %d, Col: %d, Len: %d --- Slice Index: %d, Content Index: %d",
                "Line: %d, Col: %d",
                buffer.cursor.line + 1,
                buffer.cursor.col + 1,
                // core.file_buffer_line_length(buffer, buffer.cursor.index),
                // buffer.cursor.index.slice_index,
                // buffer.cursor.index.content_index
            );
            line_info_width := raylib.MeasureTextEx(state.font, line_info_text, f32(state.source_font_height), 0).x;

            switch state.mode {
                case .Normal:
                    raylib.DrawRectangle(
                        0,
                        i32(state.screen_height - state.source_font_height),
                        i32(8 + len("NORMAL")*state.source_font_width),
                        i32(state.source_font_height),
                        theme.get_palette_raylib_color(.Foreground4));
                    raylib.DrawRectangleV(
                        raylib.Vector2 { f32(state.screen_width) - line_info_width - 8, f32(state.screen_height - state.source_font_height) },
                        raylib.Vector2 { 8 + line_info_width, f32(state.source_font_height) },
                        theme.get_palette_raylib_color(.Foreground4));
                    raylib.DrawTextEx(
                        state.font,
                        "NORMAL",
                        raylib.Vector2 { 4, f32(state.screen_height - state.source_font_height) },
                        f32(state.source_font_height),
                        0,
                        theme.get_palette_raylib_color(.Background1));
                case .Insert:
                    raylib.DrawRectangle(
                        0,
                        i32(state.screen_height - state.source_font_height),
                        i32(8 + len("INSERT")*state.source_font_width),
                        i32(state.source_font_height),
                        theme.get_palette_raylib_color(.Foreground2));
                    raylib.DrawRectangleV(
                        raylib.Vector2 { f32(state.screen_width) - line_info_width - 8, f32(state.screen_height - state.source_font_height) },
                        raylib.Vector2 { 8 + line_info_width, f32(state.source_font_height) },
                        theme.get_palette_raylib_color(.Foreground2));
                    raylib.DrawTextEx(
                        state.font,
                        "INSERT",
                        raylib.Vector2 { 4, f32(state.screen_height - state.source_font_height) },
                        f32(state.source_font_height),
                        0,
                        theme.get_palette_raylib_color(.Background1));
            }

            relative_file_path, _ := filepath.rel(state.directory, buffer.file_path)
            raylib.DrawTextEx(
                state.font,
                raylib.TextFormat("%s", relative_file_path),
                raylib.Vector2 { 8 + 4 + 6 * f32(state.source_font_width), f32(state.screen_height - state.source_font_height) },
                f32(state.source_font_height),
                0,
                theme.get_palette_raylib_color(.Foreground1));
            raylib.DrawTextEx(
                state.font,
                line_info_text,
                raylib.Vector2 { f32(state.screen_width) - line_info_width - 4, f32(state.screen_height - state.source_font_height) },
                f32(state.source_font_height),
                0,
                theme.get_palette_raylib_color(.Background1));

            if state.window != nil && state.window.draw != nil {
                state.window.draw(state.plugin_vtable, state.window);
            }

            if state.current_input_map != &state.input_map {
                longest_description := 0;
                for key, action in state.current_input_map.key_actions {
                    if len(action.description) > longest_description {
                        longest_description = len(action.description);
                    }
                }
                for key, action in state.current_input_map.ctrl_key_actions {
                    if len(action.description) > longest_description {
                        longest_description = len(action.description);
                    }
                }
                longest_description += 8;

                helper_height := state.source_font_height * (len(state.current_input_map.key_actions) + len(state.current_input_map.ctrl_key_actions));
                offset_from_bottom := state.source_font_height * 2;

                raylib.DrawRectangle(
                    i32(state.screen_width - longest_description * state.source_font_width),
                    i32(state.screen_height - helper_height - offset_from_bottom),
                    i32(longest_description*state.source_font_width),
                    i32(helper_height),
                    theme.get_palette_raylib_color(.Background2));

                index := 0;
                for key, action in state.current_input_map.key_actions {
                    raylib.DrawTextEx(
                        state.font,
                        raylib.TextFormat("%s - %s", key, action.description),
                        raylib.Vector2 { f32(state.screen_width - longest_description * state.source_font_width), f32(state.screen_height - helper_height + index * state.source_font_height - offset_from_bottom) },
                        f32(state.source_font_height),
                        0,
                        theme.get_palette_raylib_color(.Foreground1));
                    index += 1;
                }
                for key, action in state.current_input_map.ctrl_key_actions {
                    raylib.DrawTextEx(
                        state.font,
                        raylib.TextFormat("<C>-%s - %s", key, action.description),
                        raylib.Vector2 { f32(state.screen_width - longest_description * state.source_font_width), f32(state.screen_height - helper_height + index * state.source_font_height - offset_from_bottom) },
                        f32(state.source_font_height),
                        0,
                        theme.get_palette_raylib_color(.Foreground1));
                    index += 1;
                }
            }
        }

        switch state.mode {
            case .Normal:
                if state.window != nil && state.window.get_buffer != nil {
                    do_normal_mode(&state, state.window->get_buffer());
                } else {
                    do_normal_mode(&state, buffer);
                }
            case .Insert:
                if state.window != nil && state.window.get_buffer != nil {
                    do_insert_mode(&state, state.window->get_buffer());
                } else {
                    do_insert_mode(&state, buffer);
                }
        }

        if state.should_close_window {
            state.should_close_window = false;
            core.close_window_and_free(&state);
        }

        ui.test_menu_bar(&state, &menu_bar_state, 0,0, mouse_pos, raylib.IsMouseButtonReleased(.LEFT), state.source_font_height);
    }

    for plugin in state.plugins {
        if plugin.on_exit != nil {
            plugin.on_exit();
        }
    }
}
