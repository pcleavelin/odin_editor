package main

import "core:os"
import "core:path/filepath"
import "core:math"
import "core:strings"
import "core:runtime"
import "core:fmt"
import "core:mem"
import "core:slice"
import "vendor:sdl2"
import "vendor:sdl2/ttf"

import "core"
import "theme"
import "ui"
import "plugin"

State :: core.State;
FileBuffer :: core.FileBuffer;

state := core.State {};

StateWithUi :: struct {
    state: ^State,
    ui_context: ^ui.Context,
}

// TODO: use buffer list in state
do_normal_mode :: proc(state: ^State, buffer: ^FileBuffer) {
    if state.current_input_map != nil {
        // if raylib.IsKeyPressed(.ESCAPE) {
        //     core.request_window_close(state);
        // } else if raylib.IsKeyDown(.LEFT_CONTROL) {
        //     for key, action in &state.current_input_map.ctrl_key_actions {
        //         if raylib.IsKeyPressed(key) {
        //             switch value in action.action {
        //                 case core.PluginEditorAction:
        //                     value(state.plugin_vtable);
        //                 case core.EditorAction:
        //                     value(state);
        //                 case core.InputMap:
        //                     state.current_input_map = &(&state.current_input_map.ctrl_key_actions[key]).action.(core.InputMap)
        //             }
        //         }
        //     }
        // } else {
        //     for key, action in state.current_input_map.key_actions {
        //         if raylib.IsKeyPressed(key) {
        //             switch value in action.action {
        //                 case core.PluginEditorAction:
        //                     value(state.plugin_vtable);
        //                 case core.EditorAction:
        //                     value(state);
        //                 case core.InputMap:
        //                     state.current_input_map = &(&state.current_input_map.key_actions[key]).action.(core.InputMap)
        //             }
        //         }
        //     }
        // }
    }
}

// TODO: use buffer list in state
do_insert_mode :: proc(state: ^State, buffer: ^FileBuffer) {
    key := 0; // raylib.GetCharPressed();

    for key > 0 {
        if key >= 32 && key <= 125 && len(buffer.input_buffer) < 1024-1 {
            append(&buffer.input_buffer, u8(key));

            for hook_proc in state.hooks[plugin.Hook.BufferInput] {
                hook_proc(state.plugin_vtable, buffer);
            }
        }

        key = 0; // raylib.GetCharPressed();
    }

    // if raylib.IsKeyPressed(.ENTER) {
    //     append(&buffer.input_buffer, '\n');
    // }

    // if raylib.IsKeyPressed(.ESCAPE) {
    //     state.mode = .Normal;

    //     core.insert_content(buffer, buffer.input_buffer[:]);
    //     runtime.clear(&buffer.input_buffer);
    //     return;
    // }

    // if raylib.IsKeyPressed(.BACKSPACE) {
    //     core.delete_content(buffer, 1);

    //     for hook_proc in state.hooks[plugin.Hook.BufferInput] {
    //         hook_proc(state.plugin_vtable, buffer);
    //     }
    // }
}

// switch_to_buffer :: proc(state: ^State, item: ^ui.MenuBarItem) {
//     for buffer, index in state.buffers {
//         if strings.compare(buffer.file_path, item.text) == 0 {
//             state.current_buffer = index;
//             break;
//         }
//     }
// }

register_default_leader_actions :: proc(input_map: ^core.InputMap) {
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
            fmt.print("You pressed <C>-MINUS", state.source_font_height, " ");
            if state.source_font_height > 16 {
                state.source_font_height -= 2;
                state.source_font_width = state.source_font_height / 2;

                state.font_atlas = core.gen_font_atlas(state, "/System/Library/Fonts/Supplemental/Andale Mono.ttf");
                //state.font = raylib.LoadFontEx("/System/Library/Fonts/Supplemental/Andale Mono.ttf", i32(state.source_font_height*2), nil, 0);
                //raylib.SetTextureFilter(state.font.texture, .BILINEAR);
            }
            fmt.println(state.source_font_height);
        }, "increase font size");
        core.register_ctrl_key_action(input_map, .EQUAL, proc(state: ^State) {
            fmt.println("You pressed <C>-EQUAL");

            state.source_font_height += 2;
            state.source_font_width = state.source_font_height / 2;

            state.font_atlas = core.gen_font_atlas(state, "/System/Library/Fonts/Supplemental/Andale Mono.ttf");
            //state.font = raylib.LoadFontEx("/System/Library/Fonts/Supplemental/Andale Mono.ttf", i32(state.source_font_height*2), nil, 0);
            //raylib.SetTextureFilter(state.font.texture, .BILINEAR);
        }, "decrease font size");
    }

    // Inserting Text
    {
        core.register_key_action(input_map, .I, proc(state: ^State) {
            state.mode = .Insert;
            sdl2.StartTextInput();
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

ui_font_width :: proc() -> i32 {
    return i32(state.source_font_width);
}
ui_font_height :: proc() -> i32 {
    return i32(state.source_font_height);
}

draw :: proc(state_with_ui: ^StateWithUi) {
    buffer := &state_with_ui.state.buffers[state_with_ui.state.current_buffer];

    buffer.glyph_buffer_height = math.min(256, int((state_with_ui.state.screen_height - state_with_ui.state.source_font_height*2) / state_with_ui.state.source_font_height)) + 1;
    buffer.glyph_buffer_width = math.min(256, int((state_with_ui.state.screen_width - state_with_ui.state.source_font_width) / state_with_ui.state.source_font_width));

    // raylib.BeginDrawing();
    // defer raylib.EndDrawing();

    render_color := theme.get_palette_color(.Background);
    sdl2.SetRenderDrawColor(state_with_ui.state.sdl_renderer, render_color.r, render_color.g, render_color.b, render_color.a);
    sdl2.RenderClear(state_with_ui.state.sdl_renderer);

    // if state_with_ui.state.window != nil && state_with_ui.state.window.draw != nil {
    //     state_with_ui.state.window.draw(state_with_ui.state.plugin_vtable, state_with_ui.state.window.user_data);
    // }

    ui.compute_layout(state_with_ui.ui_context, { state_with_ui.state.screen_width, state_with_ui.state.screen_height }, state_with_ui.state.source_font_width, state_with_ui.state.source_font_height, state_with_ui.ui_context.root);
    ui.draw(state_with_ui.ui_context, state_with_ui.state, state_with_ui.state.source_font_width, state_with_ui.state.source_font_height, state_with_ui.ui_context.root);

    if state_with_ui.state.current_input_map != &state_with_ui.state.input_map {
        longest_description := 0;
        for key, action in state_with_ui.state.current_input_map.key_actions {
            if len(action.description) > longest_description {
                longest_description = len(action.description);
            }
        }
        for key, action in state_with_ui.state.current_input_map.ctrl_key_actions {
            if len(action.description) > longest_description {
                longest_description = len(action.description);
            }
        }
        longest_description += 8;

        helper_height := state_with_ui.state.source_font_height * (len(state_with_ui.state.current_input_map.key_actions) + len(state_with_ui.state.current_input_map.ctrl_key_actions));
        offset_from_bottom := state_with_ui.state.source_font_height * 2;

        core.draw_rect(
            state_with_ui.state,
            state_with_ui.state.screen_width - longest_description * state_with_ui.state.source_font_width,
            state_with_ui.state.screen_height - helper_height - offset_from_bottom,
            longest_description*state_with_ui.state.source_font_width,
            helper_height,
            .Background2
        );
        //raylib.DrawRectangle(
        //    i32(state_with_ui.state.screen_width - longest_description * state_with_ui.state.source_font_width),
        //    i32(state_with_ui.state.screen_height - helper_height - offset_from_bottom),
        //    i32(longest_description*state_with_ui.state.source_font_width),
        //    i32(helper_height),
        //    theme.get_palette_raylib_color(.Background2)
        //);

        index := 0;
        for key, action in state_with_ui.state.current_input_map.key_actions {
            core.draw_text(
                state_with_ui.state,
                fmt.tprintf("%s - %s", key, action.description),
                state_with_ui.state.screen_width - longest_description * state_with_ui.state.source_font_width,
                state_with_ui.state.screen_height - helper_height + index * state_with_ui.state.source_font_height - offset_from_bottom
            );

            // raylib.DrawTextEx(
            //     state_with_ui.state.font,
            //     raylib.TextFormat("%s - %s", key, action.description),
            //     raylib.Vector2 { f32(state_with_ui.state.screen_width - longest_description * state_with_ui.state.source_font_width), f32(state_with_ui.state.screen_height - helper_height + index * state_with_ui.state.source_font_height - offset_from_bottom) },
            //     f32(state_with_ui.state.source_font_height),
            //     0,
            //     theme.get_palette_raylib_color(.Foreground1)
            // );
            index += 1;
        }
        for key, action in state_with_ui.state.current_input_map.ctrl_key_actions {
            core.draw_text(
                state_with_ui.state,
                fmt.tprintf("<C>-%s - %s", key, action.description),
                state_with_ui.state.screen_width - longest_description * state_with_ui.state.source_font_width,
                state_with_ui.state.screen_height - helper_height + index * state_with_ui.state.source_font_height - offset_from_bottom
            );
            // raylib.DrawTextEx(
            //     state_with_ui.state.font,
            //     raylib.TextFormat("<C>-%s - %s", key, action.description),
            //     raylib.Vector2 { f32(state_with_ui.state.screen_width - longest_description * state_with_ui.state.source_font_width), f32(state_with_ui.state.screen_height - helper_height + index * state_with_ui.state.source_font_height - offset_from_bottom) },
            //     f32(state_with_ui.state.source_font_height),
            //     0,
            //     theme.get_palette_raylib_color(.Foreground1)
            // );
            index += 1;
        }
    }

    sdl2.RenderPresent(state_with_ui.state.sdl_renderer);
}

// TODO: need to wrap state and ui context into one structure so that it can be used in this function
expose_event_watcher :: proc "c" (state: rawptr, event: ^sdl2.Event) -> i32 {
    if event.type == .WINDOWEVENT {
        state := transmute(^StateWithUi)state;
        context = state.state.ctx;

        if event.window.event == .EXPOSED {
            //draw(state);
        } else if event.window.event == .SIZE_CHANGED {
            w,h: i32;

            sdl2.GetRendererOutputSize(state.state.sdl_renderer, &w, &h);

            state.state.screen_width = int(w);
            state.state.screen_height = int(h);
            draw(state);
        }
    }

    return 0;
}

ui_file_buffer :: proc(ctx: ^ui.Context, buffer: ^FileBuffer) -> ui.Interaction {
    draw_func := proc(state: ^State, box: ^ui.Box, user_data: rawptr) {
        buffer := transmute(^FileBuffer)user_data;
        buffer.glyph_buffer_width = box.computed_size.x / state.source_font_width;
        buffer.glyph_buffer_height = box.computed_size.y / state.source_font_height + 1;

        core.draw_file_buffer(state, buffer, box.computed_pos.x, box.computed_pos.y);
    };

    relative_file_path, _ := filepath.rel(state.directory, buffer.file_path, context.temp_allocator)
    ui.push_parent(ctx, ui.push_box(ctx, relative_file_path, {}, .Vertical, semantic_size = {ui.make_semantic_size(.PercentOfParent, 100), ui.make_semantic_size(.Fill, 0)}));
    defer ui.pop_parent(ctx);

    interaction := ui.custom(ctx, "buffer1", draw_func, transmute(rawptr)buffer);

    {
        ui.push_parent(ctx, ui.push_box(ctx, "buffer info", {}, semantic_size = {ui.make_semantic_size(.Fill), ui.make_semantic_size(.Exact, state.source_font_height)}));
        defer ui.pop_parent(ctx);

        ui.label(ctx, relative_file_path);
    }

    return interaction;
}

init_plugin_vtable :: proc(ui_context: ^ui.Context) -> plugin.Plugin {
    return plugin.Plugin {
        state = cast(rawptr)&state,
        register_hook = proc "c" (hook: plugin.Hook, on_hook: plugin.OnHookProc) {
            context = state.ctx;

            core.add_hook(&state, hook, on_hook);
        },
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
        create_window = proc "c" (user_data: rawptr, register_group: plugin.InputGroupProc, draw_proc: plugin.WindowDrawProc, free_window_proc: plugin.WindowFreeProc, get_buffer_proc: plugin.WindowGetBufferProc) -> rawptr {
            context = state.ctx;
            window := new(core.Window);
            window^ = core.Window {
                input_map = core.new_input_map(),
                draw = draw_proc,
                get_buffer = get_buffer_proc,
                free_user_data = free_window_proc,

                user_data = user_data,
            };

            register_group(state.plugin_vtable, transmute(rawptr)&window.input_map);

            state.window = window;
            state.current_input_map = &window.input_map;

            return window;
        },
        get_window = proc "c" () -> rawptr {
            if state.window != nil {
                return state.window.user_data;
            }

            return nil;
        },
        request_window_close = proc "c" () {
            context = state.ctx;

            core.request_window_close(&state);
        },
        get_screen_width = proc "c" () -> int {
            return state.screen_width;
        },
        get_screen_height = proc "c" () -> int {
            return state.screen_height;
        },
        get_font_width = proc "c" () -> int {
            return state.source_font_width;
        },
        get_font_height = proc "c" () -> int {
            return state.source_font_height;
        },
        get_current_directory = proc "c" () -> cstring {
            context = state.ctx;

            return strings.clone_to_cstring(state.directory, context.temp_allocator);
        },
        enter_insert_mode = proc "c" () {
            state.mode = .Insert;
            sdl2.StartTextInput();
        },
        draw_rect = proc "c" (x: i32, y: i32, width: i32, height: i32, color: theme.PaletteColor) {
            context = state.ctx;

            core.draw_rect(&state, int(x), int(y), int(width), int(height), color);
            //raylib.DrawRectangle(x, y, width, height, theme.get_palette_raylib_color(color));
        },
        draw_text = proc "c" (text: cstring, x: f32, y: f32, color: theme.PaletteColor) {
            context = state.ctx;

            core.draw_text(&state, string(text), int(x), int(y), color);
            // for codepoint, index in text {
            //     raylib.DrawTextCodepoint(
            //         state.font,
            //         rune(codepoint),
            //         raylib.Vector2 { x + f32(index * state.source_font_width), y },
            //         f32(state.source_font_height),
            //         theme.get_palette_raylib_color(color)
            //     );
            // }
        },
        draw_buffer_from_index = proc "c" (buffer_index: int, x: int, y: int, glyph_buffer_width: int, glyph_buffer_height: int, show_line_numbers: bool) {
            context = state.ctx;
            state.buffers[buffer_index].glyph_buffer_width = glyph_buffer_width;
            state.buffers[buffer_index].glyph_buffer_height = glyph_buffer_height;

            core.draw_file_buffer(
                &state,
                &state.buffers[buffer_index],
                x,
                y,
                show_line_numbers);
        },
        draw_buffer = proc "c" (buffer: rawptr, x: int, y: int, glyph_buffer_width: int, glyph_buffer_height: int, show_line_numbers: bool) {
            context = state.ctx;

            buffer := transmute(^core.FileBuffer)buffer;
            buffer.glyph_buffer_width = glyph_buffer_width;
            buffer.glyph_buffer_height = glyph_buffer_height;

            core.draw_file_buffer(
                &state,
                buffer,
                x,
                y,
                show_line_numbers);
        },
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
            get_buffer_list_iter = proc "c" (prev_buffer: ^int) -> int {
                context = state.ctx;

                return core.next_buffer(&state, prev_buffer);
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
                    should_continue = cond,
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
                    should_continue = cond,
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
                    should_continue = cond,
                };
            },
            until_line_break = transmute(rawptr)core.until_line_break,
            until_single_quote = transmute(rawptr)core.until_single_quote,
            until_double_quote = transmute(rawptr)core.until_double_quote,
            until_end_of_word = transmute(rawptr)core.until_end_of_word,
        },
        buffer = plugin.Buffer {
            get_num_buffers = proc "c" () -> int {
                context = state.ctx;

                return len(state.buffers);
            },
            get_buffer_info = proc "c" (buffer: rawptr) -> plugin.BufferInfo {
                context = state.ctx;
                buffer := cast(^core.FileBuffer)buffer;

                return core.into_buffer_info(&state, buffer);
            },
            get_buffer_info_from_index = proc "c" (buffer_index: int) -> plugin.BufferInfo {
                context = state.ctx;
                buffer := &state.buffers[buffer_index];

                return core.into_buffer_info(&state, buffer);
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
            },
            set_current_buffer = proc "c" (buffer_index: int) {
                state.current_buffer = buffer_index;
            },
            open_buffer = proc "c" (path: cstring, line: int, col: int) {
                context = state.ctx;

                path := string(path);
                should_create_buffer := true;
                for buffer, index in state.buffers {
                    if strings.compare(buffer.file_path, path) == 0 {
                        state.current_buffer = index;
                        should_create_buffer = false;
                        break;
                    }
                }

                buffer: ^core.FileBuffer = nil;
                err := core.no_error();

                if should_create_buffer {
                    new_buffer, err := core.new_file_buffer(context.allocator, strings.clone(path));
                    if err.type != .None {
                        fmt.println("Failed to open/create file buffer:", err);
                    } else {
                        runtime.append(&state.buffers, new_buffer);
                        state.current_buffer = len(state.buffers)-1;
                        buffer = &state.buffers[state.current_buffer];
                    }
                } else {
                    buffer = &state.buffers[state.current_buffer];
                }

                if buffer != nil {
                    buffer.cursor.line = line;
                    buffer.cursor.col = col;
                    buffer.glyph_buffer_height = math.min(256, int((state.screen_height - state.source_font_height*2) / state.source_font_height)) + 1;
                    buffer.glyph_buffer_width = math.min(256, int((state.screen_width - state.source_font_width) / state.source_font_width));
                    core.update_file_buffer_index_from_cursor(buffer);
                }
            },
            open_virtual_buffer = proc "c" () -> rawptr {
                context = state.ctx;

                buffer := new(FileBuffer);
                buffer^ = core.new_virtual_file_buffer(context.allocator);

                return buffer;
            },
            free_virtual_buffer = proc "c" (buffer: rawptr) {
                context = state.ctx;

                if buffer != nil {
                    buffer := cast(^core.FileBuffer)buffer;

                    core.free_file_buffer(buffer);
                    free(buffer);
                }
            },
        },
        ui = plugin.Ui {
            ui_context = ui_context,

            push_parent = proc "c" (ui_context: rawptr, box: plugin.UiBox) {
                context = state.ctx;
                ui_context := transmute(^ui.Context)ui_context;
                box := transmute(^ui.Box)box;

                ui.push_parent(ui_context, box);
            },

            pop_parent = proc "c" (ui_context: rawptr) {
                context = state.ctx;
                ui_context := transmute(^ui.Context)ui_context;

                ui.pop_parent(ui_context);
            },

            // TODO: allow this to have more flags sent to it
            floating = proc "c" (ui_context: rawptr, label: cstring, pos: [2]int) -> plugin.UiBox {
                context = state.ctx;
                ui_context := transmute(^ui.Context)ui_context;
                label := strings.clone(string(label), context.temp_allocator);

                return ui.push_floating(ui_context, label, pos);
            },
            rect = proc "c" (ui_context: rawptr, label: cstring, border: bool, axis: plugin.UiAxis, size: [2]plugin.UiSemanticSize) -> plugin.UiBox {
                context = state.ctx;
                ui_context := transmute(^ui.Context)ui_context;
                label := strings.clone(string(label), context.temp_allocator);

                size := [2]ui.SemanticSize {
                    ui.SemanticSize {
                        kind = ui.SemanticSizeKind(size.x.kind),
                        value = size.x.value,
                    },
                    ui.SemanticSize {
                        kind = ui.SemanticSizeKind(size.y.kind),
                        value = size.y.value,
                    },
                };

                return ui.push_rect(ui_context, label, border, ui.Axis(axis), size);
            },

            label = proc "c" (ui_context: rawptr, label: cstring) -> plugin.UiInteraction {
                context = state.ctx;
                ui_context := transmute(^ui.Context)ui_context;
                label := strings.clone(string(label), context.temp_allocator);

                interaction := ui.label(ui_context, label);

                return plugin.UiInteraction {
                    hovering = interaction.hovering,
                    clicked = interaction.clicked,
                };
            },
            button = proc "c" (ui_context: rawptr, label: cstring) -> plugin.UiInteraction {
                context = state.ctx;
                ui_context := transmute(^ui.Context)ui_context;
                label := strings.clone(string(label), context.temp_allocator);

                interaction := ui.button(ui_context, label);

                return plugin.UiInteraction {
                    hovering = interaction.hovering,
                    clicked = interaction.clicked,
                };
            },
            buffer = proc "c" (ui_context: rawptr, buffer: rawptr, show_line_numbers: bool) {
                context = state.ctx;
                ui_context := transmute(^ui.Context)ui_context;
                buffer := transmute(^FileBuffer)buffer;

                ui_file_buffer(ui_context, buffer);
            },

            buffer_from_index = proc "c" (ui_context: rawptr, buffer: int, show_line_numbers: bool) {
                context = state.ctx;
                ui_context := transmute(^ui.Context)ui_context;

                buffer := &state.buffers[buffer];

                ui_file_buffer(ui_context, buffer);
            },
        },
    };
}

main :: proc() {
    state = State {
        ctx = context,
        source_font_width = 8 + 2 * 3,
        source_font_height = 16 + 2 * 3,
        input_map = core.new_input_map(),
        window = nil,
        directory = os.get_current_directory(),
        plugins = make([dynamic]plugin.Interface),
        highlighters = make(map[string]plugin.OnColorBufferProc),
        hooks = make(map[plugin.Hook][dynamic]plugin.OnHookProc),
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

    if sdl2.Init({.VIDEO}) < 0 {
        fmt.eprintln("SDL failed to initialize:", sdl2.GetError());
        return;
    }

    if ttf.Init() < 0 {
        fmt.eprintln("SDL_TTF failed to initialize:", ttf.GetError());
        return;
    }
    defer ttf.Quit();

    sdl_window := sdl2.CreateWindow(
        "odin_editor - [now with more ui]",
        sdl2.WINDOWPOS_UNDEFINED,
        0,
        640,
        480,
        {.SHOWN, .RESIZABLE, .METAL, .ALLOW_HIGHDPI}
    );
    defer if sdl_window != nil {
        sdl2.DestroyWindow(sdl_window);
    }

    if sdl_window == nil {
        fmt.eprintln("Failed to create window:", sdl2.GetError());
        return;
    }

    state.sdl_renderer = sdl2.CreateRenderer(sdl_window, -1, {.ACCELERATED, .PRESENTVSYNC});
    defer if state.sdl_renderer != nil {
        sdl2.DestroyRenderer(state.sdl_renderer);
    }

    if state.sdl_renderer == nil {
        fmt.eprintln("Failed to create renderer:", sdl2.GetError());
        return;
    }
    state.font_atlas = core.gen_font_atlas(&state, "/System/Library/Fonts/Supplemental/Andale Mono.ttf");
    defer {
        if state.font_atlas.font != nil {
            ttf.CloseFont(state.font_atlas.font);
        }
        if state.font_atlas.texture != nil {
            sdl2.DestroyTexture(state.font_atlas.texture);
        }
    }

    sdl2.StartTextInput();
    sdl2.StopTextInput();

    ui_context := ui.init(state.sdl_renderer);
    sdl2.AddEventWatch(expose_event_watcher, &StateWithUi { &state, &ui_context });
    state.plugin_vtable = init_plugin_vtable(&ui_context);

    // Load plugins
    // TODO(pcleavelin): Get directory of binary instead of shells current working directory
    filepath.walk(filepath.join({ os.get_current_directory(), "bin" }), load_plugin, transmute(rawptr)&state);

    for plugin in state.plugins {
        if plugin.on_initialize != nil {
            plugin.on_initialize(state.plugin_vtable);
        }
    }


    control_key_pressed: bool;

    state.screen_width = 640; //int(raylib.GetScreenWidth());
    state.screen_height = 480; //int(raylib.GetScreenHeight());
    for !state.should_close {
        {
            buffer := &state.buffers[state.current_buffer];

            ui.push_parent(&ui_context, ui.push_box(&ui_context, "main", {}, .Vertical, semantic_size = {ui.make_semantic_size(.Fill, 100), ui.make_semantic_size(.Fill, 100)}));
            defer ui.pop_parent(&ui_context);

            {
                ui.push_parent(&ui_context, ui.push_box(&ui_context, "top_nav", {.DrawBackground}, semantic_size = {ui.make_semantic_size(.PercentOfParent, 100), ui.make_semantic_size(.Exact, state.source_font_height)}));
                defer ui.pop_parent(&ui_context);

                if ui.label(&ui_context, "Editor").clicked {
                    fmt.println("you clicked the button");
                }

                ui.push_box(
                    &ui_context,
                    "nav spacer",
                    {.DrawBackground},
                    semantic_size = {
                        ui.make_semantic_size(.Exact, 16),
                        ui.make_semantic_size(.Exact, state.source_font_height)
                    }
                );

                if ui.label(&ui_context, "Buffers").clicked {
                    fmt.println("you clicked the button");
                }
            }
            {
                ui.push_parent(&ui_context, ui.push_box(&ui_context, "deezbuffer", {}, .Horizontal, semantic_size = {ui.make_semantic_size(.PercentOfParent, 100), ui.make_semantic_size(.Fill, 0)}));
                defer ui.pop_parent(&ui_context);

                {
                    ui.push_parent(&ui_context, ui.push_box(&ui_context, "left side", {}, .Vertical, semantic_size = {ui.make_semantic_size(.Fill), ui.make_semantic_size(.Fill, 0)}));
                    defer ui.pop_parent(&ui_context);

                    {
                        if ui_file_buffer(&ui_context, &state.buffers[0]).clicked {
                            state.current_buffer = 0;
                        }
                    }
                    {
                        if ui_file_buffer(&ui_context, &state.buffers[0+1]).clicked {
                            state.current_buffer = 1;
                        }
                    }
                    {
                        if ui_file_buffer(&ui_context, &state.buffers[0+2]).clicked {
                            state.current_buffer = 2;
                        }
                    }
                }
                {
                    ui.push_parent(&ui_context, ui.push_box(&ui_context, "right side", {}, .Vertical, semantic_size = {ui.make_semantic_size(.Fill), ui.make_semantic_size(.Fill, 0)}));
                    defer ui.pop_parent(&ui_context);

                    {
                        if ui_file_buffer(&ui_context, &state.buffers[state.current_buffer]).clicked {
                            state.current_buffer = 3;
                        }
                    }
                }
            }
            {
                ui.push_parent(&ui_context, ui.push_box(&ui_context, "bottom stats", {.DrawBackground}, semantic_size = {ui.make_semantic_size(.PercentOfParent, 100), ui.make_semantic_size(.Exact, state.source_font_height)}));
                defer ui.pop_parent(&ui_context);

                label := "";
                if state.mode == .Insert {
                    label = "INSERT";
                } else if state.mode == .Normal {
                    label = "NORMAL";
                }

                if ui.label(&ui_context, label).clicked {
                    fmt.println("you clicked the button");
                }
                ui.spacer(&ui_context, "mode spacer", semantic_size = {ui.make_semantic_size(.Exact, 16), ui.make_semantic_size(.Fill)});

                relative_file_path, _ := filepath.rel(state.directory, buffer.file_path, context.temp_allocator)
                ui.label(&ui_context, relative_file_path);

                ui.spacer(&ui_context, "stats inbetween");

                {
                    ui.push_parent(&ui_context, ui.push_box(&ui_context, "center info", {}, semantic_size = ui.ChildrenSum));
                    defer ui.pop_parent(&ui_context);

                    line_info_text := fmt.tprintf(
                        //"Line: %d, Col: %d, Len: %d --- Slice Index: %d, Content Index: %d",
                        "Line: %d, Col: %d",
                        buffer.cursor.line + 1,
                        buffer.cursor.col + 1,
                        //core.file_buffer_line_length(buffer, buffer.cursor.index),
                        // buffer.cursor.index.slice_index,
                        // buffer.cursor.index.content_index,
                    );
                    ui.label(&ui_context, line_info_text);

                    mouse_pos_str := fmt.tprintf("x,y: [%d,%d]", ui_context.mouse_x, ui_context.mouse_y);
                    ui.label(&ui_context, mouse_pos_str);
                }

                //ui.spacer(&ui_context, "frame time spacer");
                //frame_time := (60.0/f32(raylib.GetFPS())) * 10;
                //frame_time_text := raylib.TextFormat("frame time: %fms", frame_time);
                //ui.label(&ui_context, "lol have to figure out how to get the frame time");
            }
        }

        if state.window != nil && state.window.draw != nil {
            state.window.draw(state.plugin_vtable, state.window.user_data);
        }

        {
            ui_context.last_mouse_left_down = ui_context.mouse_left_down;
            ui_context.last_mouse_right_down = ui_context.mouse_right_down;

            sdl_event: sdl2.Event;
            for(sdl2.PollEvent(&sdl_event)) {
                if sdl_event.type == .QUIT {
                    state.should_close = true;
                }

                if sdl_event.type == .MOUSEMOTION {
                    ui_context.mouse_x = int(sdl_event.motion.x);
                    ui_context.mouse_y = int(sdl_event.motion.y);
                }

                if sdl_event.type == .MOUSEBUTTONDOWN || sdl_event.type == .MOUSEBUTTONUP {
                    event := sdl_event.button;

                    if event.button == sdl2.BUTTON_LEFT {
                        ui_context.mouse_left_down = sdl_event.type == .MOUSEBUTTONDOWN;
                    }
                    if event.button == sdl2.BUTTON_RIGHT {
                        ui_context.mouse_left_down = sdl_event.type == .MOUSEBUTTONDOWN;
                    }
                }

                switch state.mode {
                    case .Normal: {
                        if sdl_event.type == .KEYDOWN {
                            key := plugin.Key(sdl_event.key.keysym.sym);
                            if key == .ESCAPE {
                                core.request_window_close(&state);
                            }

                            if key == .LCTRL {
                                control_key_pressed = true;
                            } else if state.current_input_map != nil {
                                if control_key_pressed {
                                    if action, exists := state.current_input_map.ctrl_key_actions[key]; exists {
                                        switch value in action.action {
                                            case core.PluginEditorAction:
                                            value(state.plugin_vtable);
                                            case core.EditorAction:
                                            value(&state);
                                            case core.InputMap:
                                            state.current_input_map = &(&state.current_input_map.ctrl_key_actions[key]).action.(core.InputMap)
                                        }
                                    }
                                } else {
                                    if action, exists := state.current_input_map.key_actions[key]; exists {
                                        switch value in action.action {
                                            case core.PluginEditorAction:
                                            value(state.plugin_vtable);
                                            case core.EditorAction:
                                            value(&state);
                                            case core.InputMap:
                                            state.current_input_map = &(&state.current_input_map.key_actions[key]).action.(core.InputMap)
                                        }
                                    }
                                }
                            }
                        }
                        if sdl_event.type == .KEYUP {
                            key := plugin.Key(sdl_event.key.keysym.sym);
                            if key == .LCTRL {
                                control_key_pressed = false;
                            }
                        }
                    }
                    case .Insert: {
                        buffer: ^FileBuffer;

                        if state.window != nil && state.window.get_buffer != nil {
                            buffer = transmute(^core.FileBuffer)(state.window.get_buffer(state.plugin_vtable, state.window.user_data));
                        } else {
                            buffer = &state.buffers[state.current_buffer];
                        }

                        if sdl_event.type == .KEYDOWN {
                            key := plugin.Key(sdl_event.key.keysym.sym);

                            #partial switch key {
                                case .ESCAPE: {
                                    state.mode = .Normal;

                                    core.insert_content(buffer, buffer.input_buffer[:]);
                                    runtime.clear(&buffer.input_buffer);

                                    sdl2.StopTextInput();
                                }
                                case .BACKSPACE: {
                                    core.delete_content(buffer, 1);

                                    for hook_proc in state.hooks[plugin.Hook.BufferInput] {
                                        hook_proc(state.plugin_vtable, buffer);
                                    }
                                }
                                case .ENTER: {
                                    append(&buffer.input_buffer, '\n');
                                }
                            }
                        }

                        if sdl_event.type == .TEXTINPUT {
                            for char in sdl_event.text.text {
                                if char < 1 {
                                    break;
                                }

                                if char >= 32 && char <= 125 && len(buffer.input_buffer) < 1024-1 {
                                    append(&buffer.input_buffer, u8(char));

                                    for hook_proc in state.hooks[plugin.Hook.BufferInput] {
                                        hook_proc(state.plugin_vtable, buffer);
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // ui.debug_print();

        draw(&StateWithUi { &state, &ui_context });

        ui.prune(&ui_context);

        switch state.mode {
            case .Normal:
                if state.window != nil && state.window.get_buffer != nil {
                    buffer := transmute(^core.FileBuffer)(state.window.get_buffer(state.plugin_vtable, state.window.user_data));
                    do_normal_mode(&state, buffer);
                } else {
                    buffer := &state.buffers[state.current_buffer];
                    do_normal_mode(&state, buffer);
                }
            case .Insert:
                if state.window != nil && state.window.get_buffer != nil {
                    buffer := transmute(^core.FileBuffer)(state.window.get_buffer(state.plugin_vtable, state.window.user_data));
                    do_insert_mode(&state, buffer);
                } else {
                    buffer := &state.buffers[state.current_buffer];
                    do_insert_mode(&state, buffer);
                }
        }

        if state.should_close_window {
            state.should_close_window = false;
            core.close_window_and_free(&state);
        }

        runtime.free_all(context.temp_allocator);
    }

    for plugin in state.plugins {
        if plugin.on_exit != nil {
            plugin.on_exit();
        }
    }

    sdl2.Quit();
}
