package main

import "core:os"
import "core:path/filepath"
import "core:math"
import "core:strings"
import "core:runtime"
import "core:fmt"
import "core:log"
import "core:mem"
import "core:slice"
import "vendor:sdl2"
import "vendor:sdl2/ttf"
import lua "vendor:lua/5.4"

import "core"
import "theme"
import "ui"
import "plugin"

State :: core.State;
FileBuffer :: core.FileBuffer;

// TODO: should probably go into state
scratch: mem.Scratch;
scratch_alloc: runtime.Allocator;
state := core.State {};

StateWithUi :: struct {
    state: ^State,
    ui_context: ^ui.Context,
}

// TODO: why do I have this here again?
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
    key := 0;

    for key > 0 {
        if key >= 32 && key <= 125 && len(buffer.input_buffer) < 1024-1 {
            append(&buffer.input_buffer, u8(key));

            for hook_proc in state.hooks[plugin.Hook.BufferInput] {
                hook_proc(state.plugin_vtable, buffer);
            }
        }

        key = 0;
    }
}

do_visual_mode :: proc(state: ^State, buffer: ^FileBuffer) {
}

register_default_leader_actions :: proc(input_map: ^core.InputActions) {
    core.register_key_action(input_map, .Q, proc(state: ^State) {
        state.current_input_map = &state.input_map.mode[state.mode];
    }, "close this help");
}

register_default_go_actions :: proc(input_map: ^core.InputActions) {
    core.register_key_action(input_map, .H, proc(state: ^State) {
        core.move_cursor_start_of_line(core.current_buffer(state));
        state.current_input_map = &state.input_map.mode[state.mode];
    }, "move to beginning of line");
    core.register_key_action(input_map, .L, proc(state: ^State) {
        core.move_cursor_end_of_line(core.current_buffer(state));
        state.current_input_map = &state.input_map.mode[state.mode];
    }, "move to end of line");
}

register_default_input_actions :: proc(input_map: ^core.InputActions) {
    // Cursor Movement
    {
        core.register_key_action(input_map, .W, proc(state: ^State) {
            core.move_cursor_forward_start_of_word(core.current_buffer(state));
        }, "move forward one word");
        core.register_key_action(input_map, .E, proc(state: ^State) {
            core.move_cursor_forward_end_of_word(core.current_buffer(state));
        }, "move forward to end of word");

        core.register_key_action(input_map, .B, proc(state: ^State) {
            core.move_cursor_backward_start_of_word(core.current_buffer(state));
        }, "move backward one word");

        core.register_key_action(input_map, .K, proc(state: ^State) {
            core.move_cursor_up(core.current_buffer(state));
        }, "move up one line");
        core.register_key_action(input_map, .J, proc(state: ^State) {
            core.move_cursor_down(core.current_buffer(state));
        }, "move down one line");
        core.register_key_action(input_map, .H, proc(state: ^State) {
            core.move_cursor_left(core.current_buffer(state));
        }, "move left one char");
        core.register_key_action(input_map, .L, proc(state: ^State) {
            core.move_cursor_right(core.current_buffer(state));
        }, "move right one char");

        core.register_ctrl_key_action(input_map, .U, proc(state: ^State) {
            core.scroll_file_buffer(core.current_buffer(state), .Up);
        }, "scroll buffer up");
        core.register_ctrl_key_action(input_map, .D, proc(state: ^State) {
            core.scroll_file_buffer(core.current_buffer(state), .Down);
        }, "scroll buffer up");
    }

    // Scale font size
    {
        core.register_ctrl_key_action(input_map, .MINUS, proc(state: ^State) {
            if state.source_font_height > 16 {
                state.source_font_height -= 2;
                state.source_font_width = state.source_font_height / 2;

                state.font_atlas = core.gen_font_atlas(state, "/System/Library/Fonts/Supplemental/Andale Mono.ttf");
            }
            log.debug(state.source_font_height);
        }, "increase font size");
        core.register_ctrl_key_action(input_map, .EQUAL, proc(state: ^State) {
            state.source_font_height += 2;
            state.source_font_width = state.source_font_height / 2;

            state.font_atlas = core.gen_font_atlas(state, "/System/Library/Fonts/Supplemental/Andale Mono.ttf");
        }, "decrease font size");
    }

    core.register_key_action(input_map, .SPACE, core.new_input_actions(), "leader commands");
    register_default_leader_actions(&(&input_map.key_actions[.SPACE]).action.(core.InputActions));

    core.register_key_action(input_map, .G, core.new_input_actions(), "Go commands");
    register_default_go_actions(&(&input_map.key_actions[.G]).action.(core.InputActions));

    core.register_key_action(&state.input_map.mode[.Normal], .V, proc(state: ^State) {
        state.mode = .Visual;
        state.current_input_map = &state.input_map.mode[.Visual];

        core.current_buffer(state).selection = core.new_selection(core.current_buffer(state).cursor);
    }, "enter visual mode");

}

register_default_visual_actions :: proc(input_map: ^core.InputActions) {
    core.register_key_action(input_map, .ESCAPE, proc(state: ^State) {
        state.mode = .Normal;
        state.current_input_map = &state.input_map.mode[.Normal];

        core.current_buffer(state).selection = nil;
    }, "exit visual mode");

    // Cursor Movement
    {
        core.register_key_action(input_map, .W, proc(state: ^State) {
            sel_cur := core.current_buffer(state).selection.?;

            core.move_cursor_forward_start_of_word(core.current_buffer(state), cursor = &sel_cur.end);
        }, "move forward one word");
        core.register_key_action(input_map, .E, proc(state: ^State) {
            sel_cur := &(core.current_buffer(state).selection.?);

            core.move_cursor_forward_end_of_word(core.current_buffer(state), cursor = &sel_cur.end);
        }, "move forward to end of word");

        core.register_key_action(input_map, .B, proc(state: ^State) {
            sel_cur := &(core.current_buffer(state).selection.?);

            core.move_cursor_backward_start_of_word(core.current_buffer(state), cursor = &sel_cur.end);
        }, "move backward one word");

        core.register_key_action(input_map, .K, proc(state: ^State) {
            sel_cur := &(core.current_buffer(state).selection.?);

            core.move_cursor_up(core.current_buffer(state), cursor = &sel_cur.end);
        }, "move up one line");
        core.register_key_action(input_map, .J, proc(state: ^State) {
            sel_cur := &(core.current_buffer(state).selection.?);

            core.move_cursor_down(core.current_buffer(state), cursor = &sel_cur.end);
        }, "move down one line");
        core.register_key_action(input_map, .H, proc(state: ^State) {
            sel_cur := &(core.current_buffer(state).selection.?);

            core.move_cursor_left(core.current_buffer(state), cursor = &sel_cur.end);
        }, "move left one char");
        core.register_key_action(input_map, .L, proc(state: ^State) {
            sel_cur := &(core.current_buffer(state).selection.?);

            core.move_cursor_right(core.current_buffer(state), cursor = &sel_cur.end);
        }, "move right one char");

        core.register_ctrl_key_action(input_map, .U, proc(state: ^State) {
            sel_cur := &(core.current_buffer(state).selection.?);

            core.scroll_file_buffer(core.current_buffer(state), .Up, cursor = &sel_cur.end);
        }, "scroll buffer up");
        core.register_ctrl_key_action(input_map, .D, proc(state: ^State) {
            sel_cur := &(core.current_buffer(state).selection.?);

            core.scroll_file_buffer(core.current_buffer(state), .Down, cursor = &sel_cur.end);
        }, "scroll buffer up");
    }
}

register_default_text_input_actions :: proc(input_map: ^core.InputActions) {
    core.register_key_action(input_map, .I, proc(state: ^State) {
        state.mode = .Insert;
        sdl2.StartTextInput();
    }, "enter insert mode");
    core.register_key_action(input_map, .A, proc(state: ^State) {
        core.move_cursor_right(core.current_buffer(state), false);
        state.mode = .Insert;
        sdl2.StartTextInput();
    }, "enter insert mode after character (append)");

    // TODO: add shift+o to insert newline above current one

    core.register_key_action(input_map, .O, proc(state: ^State) {
        core.move_cursor_end_of_line(core.current_buffer(state), false);
        core.insert_content(core.current_buffer(state), []u8{'\n'});
        core.move_cursor_down(core.current_buffer(state));
        state.mode = .Insert;

        sdl2.StartTextInput();
    }, "insert mode on newline");
}

load_plugin :: proc(info: os.File_Info, in_err: os.Errno, state: rawptr) -> (err: os.Errno, skip_dir: bool) {
    state := cast(^State)state;

    relative_file_path, rel_error := filepath.rel(state.directory, info.fullpath);
    extension := filepath.ext(info.fullpath);

    if extension == ".dylib" || extension == ".dll" || extension == ".so" {
        if loaded_plugin, succ := plugin.try_load_plugin(info.fullpath); succ {
            append(&state.plugins, loaded_plugin);

            if rel_error == .None {
                log.info("Loaded", relative_file_path);
            } else {
                log.info("Loaded", info.fullpath);
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
    buffer := core.current_buffer(state_with_ui.state);

    buffer.glyph_buffer_height = math.min(256, int((state_with_ui.state.screen_height - state_with_ui.state.source_font_height*2) / state_with_ui.state.source_font_height)) + 1;
    buffer.glyph_buffer_width = math.min(256, int((state_with_ui.state.screen_width - state_with_ui.state.source_font_width) / state_with_ui.state.source_font_width));

    render_color := theme.get_palette_color(.Background);
    sdl2.SetRenderDrawColor(state_with_ui.state.sdl_renderer, render_color.r, render_color.g, render_color.b, render_color.a);
    sdl2.RenderClear(state_with_ui.state.sdl_renderer);

    // if state_with_ui.state.window != nil && state_with_ui.state.window.draw != nil {
    //     state_with_ui.state.window.draw(state_with_ui.state.plugin_vtable, state_with_ui.state.window.user_data);
    // }

    ui.compute_layout(state_with_ui.ui_context, { state_with_ui.state.screen_width, state_with_ui.state.screen_height }, state_with_ui.state.source_font_width, state_with_ui.state.source_font_height, state_with_ui.ui_context.root);
    ui.draw(state_with_ui.ui_context, state_with_ui.state, state_with_ui.state.source_font_width, state_with_ui.state.source_font_height, state_with_ui.ui_context.root);

    if state_with_ui.state.mode != .Insert && state_with_ui.state.current_input_map != &state_with_ui.state.input_map.mode[state_with_ui.state.mode] {
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

        index := 0;
        for key, action in state_with_ui.state.current_input_map.key_actions {
            core.draw_text(
                state_with_ui.state,
                fmt.tprintf("%s - %s", key, action.description),
                state_with_ui.state.screen_width - longest_description * state_with_ui.state.source_font_width,
                state_with_ui.state.screen_height - helper_height + index * state_with_ui.state.source_font_height - offset_from_bottom
            );

            index += 1;
        }
        for key, action in state_with_ui.state.current_input_map.ctrl_key_actions {
            core.draw_text(
                state_with_ui.state,
                fmt.tprintf("<C>-%s - %s", key, action.description),
                state_with_ui.state.screen_width - longest_description * state_with_ui.state.source_font_width,
                state_with_ui.state.screen_height - helper_height + index * state_with_ui.state.source_font_height - offset_from_bottom
            );

            index += 1;
        }
    }

    sdl2.RenderPresent(state_with_ui.state.sdl_renderer);
}

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
            state.state.width_dpi_ratio = f32(w) / f32(event.window.data1);
            state.state.height_dpi_ratio = f32(h) / f32(event.window.data2);

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

    buffer_container, _ := ui.push_box(ctx, relative_file_path, {}, .Vertical, semantic_size = {ui.make_semantic_size(.Fill), ui.make_semantic_size(.Fill)});
    ui.push_parent(ctx, buffer_container);
    defer ui.pop_parent(ctx);

    interaction := ui.custom(ctx, "buffer1", draw_func, transmute(rawptr)buffer);

    {
        info_box, _ := ui.push_box(ctx, "buffer info", {}, semantic_size = {ui.make_semantic_size(.Fill), ui.make_semantic_size(.Exact, state.source_font_height)});
        ui.push_parent(ctx, info_box);
        defer ui.pop_parent(ctx);

        ui.label(ctx, fmt.tprintf("%s", state.mode))
        if selection, exists := buffer.selection.?; exists {
            ui.label(ctx, fmt.tprintf("sel: %d:%d", selection.end.line, selection.end.col));
        }
        ui.spacer(ctx, "spacer");
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
                log.error("Highlighter already registered for", extension, "files");
            } else {
                state.highlighters[extension] = on_color_buffer;
            }
        },
        register_input_group = proc "c" (input_map: rawptr, key: plugin.Key, register_group: plugin.InputGroupProc) {
            context = state.ctx;

            to_be_edited_map: ^core.InputActions = nil;

            if input_map != nil {
                to_be_edited_map = transmute(^core.InputActions)input_map;
            } else {
                to_be_edited_map = state.current_input_map;
            }

            // TODO: change this to use the given mode
            if action, exists := to_be_edited_map.key_actions[key]; exists {
                switch value in action.action {
                    case core.LuaEditorAction:
                        log.warn("Plugin attempted to register input group on existing key action (added from Lua)");
                    case core.PluginEditorAction:
                        log.warn("Plugin attempted to register input group on existing key action (added from Plugin)");
                    case core.EditorAction:
                        log.warn("Plugin attempted to register input group on existing key action");
                    case core.InputActions:
                        input_map := &(&to_be_edited_map.key_actions[key]).action.(core.InputActions);
                        register_group(state.plugin_vtable, transmute(rawptr)input_map);
                }
            } else {
                core.register_key_action(to_be_edited_map, key, core.new_input_actions(), "PLUGIN INPUT GROUP");
                register_group(state.plugin_vtable, &(&to_be_edited_map.key_actions[key]).action.(core.InputActions));
            }
        },
        register_input = proc "c" (input_map: rawptr, key: plugin.Key, input_action: plugin.InputActionProc, description: cstring) {
            context = state.ctx;

            to_be_edited_map: ^core.InputActions = nil;
            description := strings.clone(string(description));

            if input_map != nil {
                to_be_edited_map = transmute(^core.InputActions)input_map;
            } else {
                to_be_edited_map = state.current_input_map;
            }

            if action, exists := to_be_edited_map.key_actions[key]; exists {
                switch value in action.action {
                    case core.LuaEditorAction:
                        log.warn("Plugin attempted to register key action on existing key action (added from Lua)");
                    case core.PluginEditorAction:
                        log.warn("Plugin attempted to register key action on existing key action (added from Plugin)");
                    case core.EditorAction:
                        log.warn("Plugin attempted to register input key action on existing key action");
                    case core.InputActions:
                        log.warn("Plugin attempted to register input key action on existing input group");
                }
            } else {
                core.register_key_action(to_be_edited_map, key, input_action, description);
            }
        },
        create_window = proc "c" (user_data: rawptr, register_group: plugin.InputGroupProc, draw_proc: plugin.WindowDrawProc, free_window_proc: plugin.WindowFreeProc, get_buffer_proc: plugin.WindowGetBufferProc) -> rawptr {
            context = state.ctx;
            window := new(core.Window);
            window^ = core.Window {
                input_map = core.new_input_actions(),
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
        },
        draw_text = proc "c" (text: cstring, x: f32, y: f32, color: theme.PaletteColor) {
            context = state.ctx;

            core.draw_text(&state, string(text), int(x), int(y), color);
        },
        draw_buffer_from_index = proc "c" (buffer_index: int, x: int, y: int, glyph_buffer_width: int, glyph_buffer_height: int, show_line_numbers: bool) {
            context = state.ctx;
            core.buffer_from_index(&state, buffer_index).glyph_buffer_width = glyph_buffer_width;
            core.buffer_from_index(&state, buffer_index).glyph_buffer_height = glyph_buffer_height;

            core.draw_file_buffer(
                &state,
                core.buffer_from_index(&state, buffer_index),
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

                it := core.new_file_buffer_iter(core.current_buffer(&state));

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
                buffer := core.buffer_from_index(&state, buffer_index);

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
                        log.error("Failed to open/create file buffer:", err);
                    } else {
                        runtime.append(&state.buffers, new_buffer);
                        state.current_buffer = len(state.buffers)-1;
                        buffer = core.current_buffer(&state);
                    }
                } else {
                    buffer = core.current_buffer(&state);
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

            spacer = proc "c" (ui_context: rawptr, label: cstring) -> plugin.UiInteraction {
                context = state.ctx;
                ui_context := transmute(^ui.Context)ui_context;
                label := strings.clone(string(label), context.temp_allocator);

                interaction := ui.spacer(ui_context, label);

                return plugin.UiInteraction {
                    hovering = interaction.hovering,
                    clicked = interaction.clicked,
                };
            },
            // TODO: allow this to have more flags sent to it
            floating = proc "c" (ui_context: rawptr, label: cstring, pos: [2]int) -> plugin.UiBox {
                context = state.ctx;
                ui_context := transmute(^ui.Context)ui_context;
                label := strings.clone(string(label), context.temp_allocator);

                floating, _ := ui.push_floating(ui_context, label, pos);
                return floating;
            },
            rect = proc "c" (ui_context: rawptr, label: cstring, background: bool, border: bool, axis: plugin.UiAxis, size: [2]plugin.UiSemanticSize) -> plugin.UiBox {
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

                rect, _ := ui.push_rect(ui_context, label, background, border, ui.Axis(axis), size);
                return rect;
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

            buffer_from_index = proc "c" (ui_context: rawptr, buffer_index: int, show_line_numbers: bool) {
                context = state.ctx;
                ui_context := transmute(^ui.Context)ui_context;

                buffer := core.buffer_from_index(&state, buffer_index);

                ui_file_buffer(ui_context, buffer);
            },
        },
    };
}

lua_ui_flags :: proc(L: ^lua.State, index: i32) -> (bit_set[ui.Flag], bool) {
    lua.L_checktype(L, index, i32(lua.TTABLE));
    lua.len(L, index);
    array_len := lua.tointeger(L, -1);
    lua.pop(L, 1);

    flags: bit_set[ui.Flag]

    for i in 1..=array_len {
        lua.rawgeti(L, index, i);
        defer lua.pop(L, 1);

        flag := lua.tostring(L, -1);
        switch flag {
            case "Clickable": flags |= {.Clickable}
            case "Hoverable": flags |= {.Hoverable}
            case "Scrollable": flags |= {.Scrollable}
            case "DrawText": flags |= {.DrawText}
            case "DrawBorder": flags |= {.DrawBorder}
            case "DrawBackground": flags |= {.DrawBackground}
            case "RoundedBorder": flags |= {.RoundedBorder}
            case "Floating": flags |= {.Floating}
            case "CustomDrawFunc": flags |= {.CustomDrawFunc}
        }
    }

    return flags, true
}

main :: proc() {
    state = State {
        ctx = context,
        screen_width = 640,
        screen_height = 480,
        source_font_width = 8,
        source_font_height = 16,
        input_map = core.new_input_map(),
        commands = make(core.EditorCommandList),

        window = nil,
        directory = os.get_current_directory(),
        plugins = make([dynamic]plugin.Interface),
        highlighters = make(map[string]plugin.OnColorBufferProc),
        hooks = make(map[plugin.Hook][dynamic]plugin.OnHookProc),
        lua_hooks = make(map[plugin.Hook][dynamic]core.LuaHookRef),

        log_buffer = core.new_virtual_file_buffer(context.allocator),
    };

    context.logger = core.new_logger(&state.log_buffer);
    state.ctx = context;

    mem.scratch_allocator_init(&scratch, 1024*1024);
    scratch_alloc = mem.scratch_allocator(&scratch);

    state.current_input_map = &state.input_map.mode[.Normal];
    register_default_input_actions(&state.input_map.mode[.Normal]);
    register_default_visual_actions(&state.input_map.mode[.Visual]);

    register_default_text_input_actions(&state.input_map.mode[.Normal]);

    core.register_editor_command(
        &state.commands,
        "nl.spacegirl.editor.core",
        "New Scratch Buffer",
        "Opens a new scratch buffer",
        proc(state: ^State) {
            buffer := core.new_virtual_file_buffer(context.allocator);
            runtime.append(&state.buffers, buffer);
        }
    )
    core.register_editor_command(
        &state.commands,
        "nl.spacegirl.editor.core",
        "Quit",
        "Quits the application",
        proc(state: ^State) {
            state.should_close = true
        }
    )

    {
        cmds := core.query_editor_commands_by_group(&state.commands, "nl.spacegirl.editor.core", scratch_alloc);
        log.info("List of commands:");
        for cmd in cmds {
            log.info(cmd.name, ":", cmd.description);
        }
    }

    if len(os.args) > 1 {
        for arg in os.args[1:] {
            buffer, err := core.new_file_buffer(context.allocator, arg, state.directory);
            if err.type != .None {
                log.error("Failed to create file buffer:", err);
                continue;
            }

            runtime.append(&state.buffers, buffer);
        }
    } else {
        buffer := core.new_virtual_file_buffer(context.allocator);
        runtime.append(&state.buffers, buffer);
    }

    if sdl2.Init({.VIDEO}) < 0 {
        log.error("SDL failed to initialize:", sdl2.GetError());
        return;
    }

    if ttf.Init() < 0 {
        log.error("SDL_TTF failed to initialize:", ttf.GetError());
        return;
    }
    defer ttf.Quit();

    sdl_window := sdl2.CreateWindow(
        "odin_editor - [now with more ui]",
        sdl2.WINDOWPOS_UNDEFINED,
        0,
        640,
        480,
        {.SHOWN, .RESIZABLE, .ALLOW_HIGHDPI}
    );
    defer if sdl_window != nil {
        sdl2.DestroyWindow(sdl_window);
    }

    if sdl_window == nil {
        log.error("Failed to create window:", sdl2.GetError());
        return;
    }

    state.sdl_renderer = sdl2.CreateRenderer(sdl_window, -1, {.ACCELERATED, .PRESENTVSYNC});
    defer if state.sdl_renderer != nil {
        sdl2.DestroyRenderer(state.sdl_renderer);
    }

    if state.sdl_renderer == nil {
        log.error("Failed to create renderer:", sdl2.GetError());
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

    {
        w,h: i32;
        sdl2.GetRendererOutputSize(state.sdl_renderer, &w, &h);

        state.width_dpi_ratio = f32(w) / f32(state.screen_width);
        state.height_dpi_ratio = f32(h) / f32(state.screen_height);
        state.screen_width = int(w);
        state.screen_height = int(h);
    }

    sdl2.SetRenderDrawBlendMode(state.sdl_renderer, .BLEND);

    // Done to clear the buffer
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

    // **********************************************************************
    L := lua.L_newstate();
    state.L = L;
    lua.L_openlibs(L);

    bbb: [^]lua.L_Reg;
    editor_lib := [?]lua.L_Reg {
        lua.L_Reg {
            "quit",
            proc "c" (L: ^lua.State) -> i32 {
                context = state.ctx;


                state.should_close = true;
                return i32(lua.OK);
            }
        },
        lua.L_Reg {
            "log",
            proc "c" (L: ^lua.State) -> i32 {
                context = state.ctx;

                text := string(lua.L_checkstring(L, 1));
                log.info("[LUA]:", text);

                return i32(lua.OK);
            }
        },
        lua.L_Reg {
            "register_hook",
            proc "c" (L: ^lua.State) -> i32 {
                context = state.ctx;

                hook := lua.L_checkinteger(L, 1);

                lua.L_checktype(L, 2, i32(lua.TFUNCTION));
                lua.pushvalue(L, 2);
                fn_ref := lua.L_ref(L, i32(lua.REGISTRYINDEX));

                core.add_lua_hook(&state, plugin.Hook(hook), fn_ref);

                return i32(lua.OK);
            }
        },
        lua.L_Reg {
            "register_key_group",
            proc "c" (L: ^lua.State) -> i32 {
                context = state.ctx;

                lua.L_checktype(L, 1, i32(lua.TTABLE));

                table_to_action :: proc(L: ^lua.State, index: i32, input_map: ^core.InputActions) {
                    lua.len(L, index);
                    key_group_len := lua.tointeger(L, -1);
                    lua.pop(L, 1);

                    for i in 1..=key_group_len {
                        lua.rawgeti(L, index, i);
                        defer lua.pop(L, 1);

                        lua.rawgeti(L, -1, 1);
                        key:= plugin.Key(lua.tointeger(L, -1));
                        lua.pop(L, 1);

                        lua.rawgeti(L, -1, 2);
                        desc := strings.clone(string(lua.tostring(L, -1)));
                        lua.pop(L, 1);

                        switch lua.rawgeti(L, -1, 3) {
                            case i32(lua.TTABLE):
                                if action, exists := input_map.key_actions[key]; exists {
                                    switch value in action.action {
                                        case core.LuaEditorAction:
                                            log.warn("Plugin attempted to register input group on existing key action (added from Lua)");
                                        case core.PluginEditorAction:
                                            log.warn("Plugin attempted to register input group on existing key action (added from Plugin)");
                                        case core.EditorAction:
                                            log.warn("Plugin attempted to register input group on existing key action");
                                        case core.InputActions:
                                            input_map := &(&input_map.key_actions[key]).action.(core.InputActions);
                                            table_to_action(L, lua.gettop(L), input_map);
                                    }
                                } else {
                                    core.register_key_action(input_map, key, core.new_input_actions(), desc);
                                    table_to_action(L, lua.gettop(L), &((&input_map.key_actions[key]).action.(core.InputActions)));
                                }
                                lua.pop(L, 1);

                            case i32(lua.TFUNCTION):
                                fn_ref := lua.L_ref(L, i32(lua.REGISTRYINDEX));

                                if lua.rawgeti(L, -1, 4) == i32(lua.TTABLE) {
                                    maybe_input_map := core.new_input_actions();
                                    table_to_action(L, lua.gettop(L), &maybe_input_map);

                                    core.register_key_action_group(input_map, key, core.LuaEditorAction { fn_ref, maybe_input_map }, desc);
                                } else {
                                    core.register_key_action_group(input_map, key, core.LuaEditorAction { fn_ref, core.InputActions {} }, desc);
                                }

                            case:
                                lua.pop(L, 1);
                        }
                    }
                }

                table_to_action(L, 1, state.current_input_map);

                return i32(lua.OK);
            }
        },
        lua.L_Reg {
            "request_window_close",
            proc "c" (L: ^lua.State) -> i32 {
                context = state.ctx;

                core.request_window_close(&state);

                return i32(lua.OK);
            }
        },
        lua.L_Reg {
            "get_current_buffer_index",
            proc "c" (L: ^lua.State) -> i32 {
                context = state.ctx;

                lua.pushinteger(L, lua.Integer(state.current_buffer));

                return 1;
            }
        },
        lua.L_Reg {
            "set_current_buffer_from_index",
            proc "c" (L: ^lua.State) -> i32 {
                context = state.ctx;

                buffer_index := int(lua.L_checkinteger(L, 1));
                if buffer_index != -2 && (buffer_index < 0 || buffer_index >= len(state.buffers)) {
                    return i32(lua.ERRRUN);
                } else {
                    state.current_buffer = buffer_index;
                }

                return i32(lua.OK);
            }
        },
        lua.L_Reg {
            "buffer_info_from_index",
            proc "c" (L: ^lua.State) -> i32 {
                context = state.ctx;

                buffer_index := int(lua.L_checkinteger(L, 1));
                if buffer_index < 0 || buffer_index >= len(state.buffers) {
                    lua.pushnil(L);
                } else {
                    push_lua_buffer_info :: proc(L: ^lua.State, buffer: ^FileBuffer) {
                        lua.newtable(L);
                        {
                            lua.pushlightuserdata(L, buffer);
                            lua.setfield(L, -2, "buffer");

                            lua.newtable(L);
                            {
                                lua.pushinteger(L, lua.Integer(buffer.cursor.col));
                                lua.setfield(L, -2, "col");

                                lua.pushinteger(L, lua.Integer(buffer.cursor.line));
                                lua.setfield(L, -2, "line");
                            }
                            lua.setfield(L, -2, "cursor");

                            lua.pushstring(L, strings.clone_to_cstring(buffer.file_path, context.temp_allocator));
                            lua.setfield(L, -2, "full_file_path");

                            relative_file_path, _ := filepath.rel(state.directory, buffer.file_path, context.temp_allocator)
                            lua.pushstring(L, strings.clone_to_cstring(relative_file_path, context.temp_allocator));
                            lua.setfield(L, -2, "file_path");
                        }
                    }

                    push_lua_buffer_info(L, core.buffer_from_index(&state, buffer_index));
                }

                return 1;
            }
        },
        lua.L_Reg {
            "query_command_group",
            proc "c" (L: ^lua.State) -> i32 {
                context = state.ctx;

                group := lua.L_checkstring(L, 1);
                cmds := core.query_editor_commands_by_group(&state.commands, string(group), scratch_alloc);

                lua.newtable(L);
                {
                    for cmd, i in cmds {
                        lua.newtable(L);
                        {
                            lua.pushstring(L, strings.clone_to_cstring(cmd.name, scratch_alloc));
                            lua.setfield(L, -2, "name");

                            lua.pushstring(L, strings.clone_to_cstring(cmd.description, scratch_alloc));
                            lua.setfield(L, -2, "description");
                        }
                        lua.rawseti(L, -2, lua.Integer(i+1));
                    }
                }

                return 1;
            }
        },
        lua.L_Reg {
            "run_command",
            proc "c" (L: ^lua.State) -> i32 {
                context = state.ctx;

                group := lua.L_checkstring(L, 1);
                name := lua.L_checkstring(L, 2);
                core.run_command(&state, string(group), string(name));

                return 1;
            }
        }
    };
    bbb = raw_data(editor_lib[:]);

    get_lua_semantic_size :: proc(L: ^lua.State, index: i32) -> ui.SemanticSize {
        if lua.istable(L, index) {
            lua.rawgeti(L, index, 1);
            semantic_kind := ui.SemanticSizeKind(lua.tointeger(L, -1));
            lua.pop(L, 1);

            lua.rawgeti(L, index, 2);
            semantic_value := int(lua.tointeger(L, -1));
            lua.pop(L, 1);

            return {semantic_kind, semantic_value};
        } else {
            semantic_kind := ui.SemanticSizeKind(lua.L_checkinteger(L, index));
            return {semantic_kind, 0};
        }
    }

    push_lua_semantic_size_table :: proc(L: ^lua.State, size: ui.SemanticSize) {
        lua.newtable(L);
        {
            lua.pushinteger(L, lua.Integer(i32(size.kind)));
            lua.rawseti(L, -2, 1);

            lua.pushinteger(L, lua.Integer(size.value));
            lua.rawseti(L, -2, 2);
        }
    }

    push_lua_box_interaction :: proc(L: ^lua.State, interaction: ui.Interaction) {
        lua.newtable(L);
        {
            lua.pushboolean(L, b32(interaction.clicked));
            lua.setfield(L, -2, "clicked");

            lua.pushboolean(L, b32(interaction.hovering));
            lua.setfield(L, -2, "hovering");

            lua.pushboolean(L, b32(interaction.dragging));
            lua.setfield(L, -2, "dragging");

            lua.newtable(L);
            {
                lua.pushinteger(L, lua.Integer(interaction.box_pos.x));
                lua.setfield(L, -2, "x");

                lua.pushinteger(L, lua.Integer(interaction.box_pos.y));
                lua.setfield(L, -2, "y");
            }
            lua.setfield(L, -2, "box_pos");

            lua.newtable(L);
            {
                lua.pushinteger(L, lua.Integer(interaction.box_size.x));
                lua.setfield(L, -2, "x");

                lua.pushinteger(L, lua.Integer(interaction.box_size.y));
                lua.setfield(L, -2, "y");
            }
            lua.setfield(L, -2, "box_size");
        }
    }

    ui_lib := [?]lua.L_Reg {
        lua.L_Reg {
            "get_mouse_pos",
            proc "c" (L: ^lua.State) -> i32 {
                context = state.ctx;

                lua.L_checktype(L, 1, i32(lua.TLIGHTUSERDATA));
                lua.pushvalue(L, 1);
                ui_ctx := transmute(^ui.Context)lua.touserdata(L, -1);
                if ui_ctx == nil { return i32(lua.ERRRUN); }

                lua.pushinteger(L, lua.Integer(ui_ctx.mouse_x));
                lua.pushinteger(L, lua.Integer(ui_ctx.mouse_y));

                return 2;
            }
        },
        lua.L_Reg {
            "Exact",
            proc "c" (L: ^lua.State) -> i32 {
                context = state.ctx;

                value := lua.L_checknumber(L, 1);
                push_lua_semantic_size_table(L, { ui.SemanticSizeKind.Exact, int(value) });

                return 1;
            }
        },
        lua.L_Reg {
            "PercentOfParent",
            proc "c" (L: ^lua.State) -> i32 {
                context = state.ctx;

                value := lua.L_checknumber(L, 1);
                push_lua_semantic_size_table(L, { ui.SemanticSizeKind.PercentOfParent, int(value) });

                return 1;
            }
        },
        lua.L_Reg {
            "push_parent",
            proc "c" (L: ^lua.State) -> i32 {
                context = state.ctx;

                lua.L_checktype(L, 1, i32(lua.TLIGHTUSERDATA));
                lua.pushvalue(L, 1);
                ui_ctx := transmute(^ui.Context)lua.touserdata(L, -1);
                if ui_ctx == nil { return i32(lua.ERRRUN); }

                lua.L_checktype(L, 2, i32(lua.TLIGHTUSERDATA));
                lua.pushvalue(L, 2);
                box := transmute(^ui.Box)lua.touserdata(L, -1);
                if box == nil { return i32(lua.ERRRUN); }

                ui.push_parent(ui_ctx, box);
                return i32(lua.OK);
            }
        },
        lua.L_Reg {
            "pop_parent",
            proc "c" (L: ^lua.State) -> i32 {
                context = state.ctx;

                lua.L_checktype(L, 1, i32(lua.TLIGHTUSERDATA));
                lua.pushvalue(L, 1);
                ui_ctx := transmute(^ui.Context)lua.touserdata(L, -1);
                if ui_ctx == nil { return i32(lua.ERRRUN); }

                ui.pop_parent(ui_ctx);
                return i32(lua.OK);
            }
        },
        lua.L_Reg {
            "push_floating",
            proc "c" (L: ^lua.State) -> i32 {
                context = state.ctx;

                lua.L_checktype(L, 1, i32(lua.TLIGHTUSERDATA));
                lua.pushvalue(L, 1);
                ui_ctx := transmute(^ui.Context)lua.touserdata(L, -1);
                if ui_ctx != nil {
                    label := lua.L_checkstring(L, 2);
                    x := int(lua.L_checkinteger(L, 3));
                    y := int(lua.L_checkinteger(L, 4));

                    box, interaction := ui.push_floating(ui_ctx, strings.clone(string(label), context.temp_allocator), {x,y});
                    lua.pushlightuserdata(L, box);
                    push_lua_box_interaction(L, interaction);
                    return 2;
                }

                return i32(lua.ERRRUN);
            }
        },
        lua.L_Reg {
            "push_box",
            proc "c" (L: ^lua.State) -> i32 {
                context = state.ctx;

                lua.L_checktype(L, 1, i32(lua.TLIGHTUSERDATA));
                lua.pushvalue(L, 1);
                ui_ctx := transmute(^ui.Context)lua.touserdata(L, -1);
                if ui_ctx != nil {
                    label := lua.L_checkstring(L, 2);
                    flags, err := lua_ui_flags(L, 3);
                    axis := ui.Axis(lua.L_checkinteger(L, 4));

                    semantic_width := get_lua_semantic_size(L, 5);
                    semantic_height := get_lua_semantic_size(L, 6);

                    box, interaction := ui.push_box(ui_ctx, strings.clone(string(label), context.temp_allocator), flags, axis, { semantic_width, semantic_height });

                    lua.pushlightuserdata(L, box);
                    push_lua_box_interaction(L, interaction)
                    return 2;
                }

                return i32(lua.ERRRUN);
            }
        },
        lua.L_Reg {
            "_box_interaction",
            proc "c" (L: ^lua.State) -> i32 {
                context = state.ctx;

                lua.L_checktype(L, 1, i32(lua.TLIGHTUSERDATA));
                lua.pushvalue(L, 1);
                ui_ctx := transmute(^ui.Context)lua.touserdata(L, -1);
                if ui_ctx == nil { return i32(lua.ERRRUN); }

                lua.L_checktype(L, 2, i32(lua.TLIGHTUSERDATA));
                lua.pushvalue(L, 2);
                box := transmute(^ui.Box)lua.touserdata(L, -1);
                if box == nil { return i32(lua.ERRRUN); }

                interaction := ui.test_box(ui_ctx, box);
                push_lua_box_interaction(L, interaction)
                return 1;
            }
        },
        lua.L_Reg {
            "push_box",
            proc "c" (L: ^lua.State) -> i32 {
                context = state.ctx;

                lua.L_checktype(L, 1, i32(lua.TLIGHTUSERDATA));
                lua.pushvalue(L, 1);
                ui_ctx := transmute(^ui.Context)lua.touserdata(L, -1);
                if ui_ctx != nil {
                    label := lua.L_checkstring(L, 2);
                    flags, err := lua_ui_flags(L, 3);
                    axis := ui.Axis(lua.L_checkinteger(L, 4));

                    semantic_width := get_lua_semantic_size(L, 5);
                    semantic_height := get_lua_semantic_size(L, 6);

                    box, interaction := ui.push_box(ui_ctx, strings.clone(string(label), context.temp_allocator), flags, axis, { semantic_width, semantic_height });
                    lua.pushlightuserdata(L, box);
                    push_lua_box_interaction(L, interaction)
                    return 2;
                }

                return i32(lua.ERRRUN);
            }
        },
        lua.L_Reg {
            "push_rect",
            proc "c" (L: ^lua.State) -> i32 {
                context = state.ctx;

                lua.L_checktype(L, 1, i32(lua.TLIGHTUSERDATA));
                lua.pushvalue(L, 1);
                ui_ctx := transmute(^ui.Context)lua.touserdata(L, -1);
                if ui_ctx != nil {
                    label := lua.L_checkstring(L, 2);
                    background := bool(lua.toboolean(L, 3));
                    border := bool(lua.toboolean(L, 4));
                    axis := ui.Axis(lua.L_checkinteger(L, 5));

                    semantic_width := get_lua_semantic_size(L, 6);
                    semantic_height := get_lua_semantic_size(L, 7);

                    box, interaction := ui.push_rect(ui_ctx, strings.clone(string(label), context.temp_allocator), background, border, axis, { semantic_width, semantic_height });
                    lua.pushlightuserdata(L, box);
                    push_lua_box_interaction(L, interaction)
                    return 2;
                }

                return i32(lua.ERRRUN);
            }
        },
        lua.L_Reg {
            "spacer",
            proc "c" (L: ^lua.State) -> i32 {
                context = state.ctx;

                lua.L_checktype(L, 1, i32(lua.TLIGHTUSERDATA));
                lua.pushvalue(L, 1);
                ui_ctx := transmute(^ui.Context)lua.touserdata(L, -1);
                if ui_ctx != nil {
                    label := lua.L_checkstring(L, 2);

                    interaction := ui.spacer(ui_ctx, strings.clone(string(label), context.temp_allocator), semantic_size = {{.Fill, 0}, {.Fill, 0}});

                    push_lua_box_interaction(L, interaction)

                    return 1;
                }

                return i32(lua.ERRRUN);
            }
        },
        lua.L_Reg {
            "label",
            proc "c" (L: ^lua.State) -> i32 {
                context = state.ctx;

                lua.L_checktype(L, 1, i32(lua.TLIGHTUSERDATA));
                lua.pushvalue(L, 1);
                ui_ctx := transmute(^ui.Context)lua.touserdata(L, -1);
                if ui_ctx != nil {
                    label := lua.L_checkstring(L, 2);

                    interaction := ui.label(ui_ctx, strings.clone(string(label), context.temp_allocator));
                    push_lua_box_interaction(L, interaction)

                    return 1;
                }

                return i32(lua.ERRRUN);
            }
        },
        lua.L_Reg {
            "button",
            proc "c" (L: ^lua.State) -> i32 {
                context = state.ctx;

                lua.L_checktype(L, 1, i32(lua.TLIGHTUSERDATA));
                lua.pushvalue(L, 1);
                ui_ctx := transmute(^ui.Context)lua.touserdata(L, -1);
                if ui_ctx != nil {
                    label := lua.L_checkstring(L, 2);

                    interaction := ui.button(ui_ctx, strings.clone(string(label), context.temp_allocator));
                    push_lua_box_interaction(L, interaction)

                    return 1;
                }

                return i32(lua.ERRRUN);
            }
        },
        lua.L_Reg {
            "advanced_button",
            proc "c" (L: ^lua.State) -> i32 {
                context = state.ctx;

                lua.L_checktype(L, 1, i32(lua.TLIGHTUSERDATA));
                lua.pushvalue(L, 1);
                ui_ctx := transmute(^ui.Context)lua.touserdata(L, -1);

                if ui_ctx != nil {
                    label := lua.L_checkstring(L, 2);
                    flags, err := lua_ui_flags(L, 3);

                    semantic_width := get_lua_semantic_size(L, 4);
                    semantic_height := get_lua_semantic_size(L, 5);

                    interaction := ui.advanced_button(ui_ctx, strings.clone(string(label), context.temp_allocator), flags, { semantic_width, semantic_height });
                    push_lua_box_interaction(L, interaction)

                    return 1;
                }

                return i32(lua.ERRRUN);
            }
        },
        lua.L_Reg {
            "buffer",
            proc "c" (L: ^lua.State) -> i32 {
                context = state.ctx;

                lua.L_checktype(L, 1, i32(lua.TLIGHTUSERDATA));
                lua.pushvalue(L, 1);
                ui_ctx := transmute(^ui.Context)lua.touserdata(L, -1);

                if ui_ctx != nil {
                    buffer_index := int(lua.L_checkinteger(L, 2));

                    if buffer_index != -2 && (buffer_index < 0 || buffer_index >= len(state.buffers)) {
                        return i32(lua.ERRRUN);
                    }

                    ui_file_buffer(ui_ctx, core.buffer_from_index(&state, buffer_index));

                    return i32(lua.OK);
                }

                return i32(lua.ERRRUN);
            }
        },
        lua.L_Reg {
            "log_buffer",
            proc "c" (L: ^lua.State) -> i32 {
                context = state.ctx;

                lua.L_checktype(L, 1, i32(lua.TLIGHTUSERDATA));
                lua.pushvalue(L, 1);
                ui_ctx := transmute(^ui.Context)lua.touserdata(L, -1);

                if ui_ctx != nil {
                    ui_file_buffer(ui_ctx, &state.log_buffer);

                    return i32(lua.OK);
                }

                return i32(lua.ERRRUN);
            }
        }
    };

    // TODO: generate this from the plugin.Key enum
    lua.newtable(L);
    {
        lua.newtable(L);
        lua.pushinteger(L, lua.Integer(plugin.Key.B));
        lua.setfield(L, -2, "B");

        lua.pushinteger(L, lua.Integer(plugin.Key.T));
        lua.setfield(L, -2, "T");

        lua.pushinteger(L, lua.Integer(plugin.Key.Y));
        lua.setfield(L, -2, "Y");

        lua.pushinteger(L, lua.Integer(plugin.Key.P));
        lua.setfield(L, -2, "P");

        lua.pushinteger(L, lua.Integer(plugin.Key.M));
        lua.setfield(L, -2, "M");

        lua.pushinteger(L, lua.Integer(plugin.Key.K));
        lua.setfield(L, -2, "K");

        lua.pushinteger(L, lua.Integer(plugin.Key.J));
        lua.setfield(L, -2, "J");

        lua.pushinteger(L, lua.Integer(plugin.Key.Q));
        lua.setfield(L, -2, "Q");

        lua.pushinteger(L, lua.Integer(plugin.Key.BACKQUOTE));
        lua.setfield(L, -2, "Backtick");

        lua.pushinteger(L, lua.Integer(plugin.Key.ESCAPE));
        lua.setfield(L, -2, "Escape");

        lua.pushinteger(L, lua.Integer(plugin.Key.ENTER));
        lua.setfield(L, -2, "Enter");

        lua.pushinteger(L, lua.Integer(plugin.Key.SPACE));
        lua.setfield(L, -2, "Space");
    }
    lua.setfield(L, -2, "Key");

    {
        lua.newtable(L);
        lua.pushinteger(L, lua.Integer(plugin.Hook.BufferInput));
        lua.setfield(L, -2, "OnBufferInput");
        lua.pushinteger(L, lua.Integer(plugin.Hook.Draw));
        lua.setfield(L, -2, "OnDraw");
    }
    lua.setfield(L, -2, "Hook");

    lua.L_setfuncs(L, bbb, 0);
    lua.setglobal(L, "Editor");

    lua.newtable(L);
    {
        lua.pushinteger(L, lua.Integer(ui.Axis.Horizontal));
        lua.setfield(L, -2, "Horizontal");
        lua.pushinteger(L, lua.Integer(ui.Axis.Vertical));
        lua.setfield(L, -2, "Vertical");
        push_lua_semantic_size_table(L, { ui.SemanticSizeKind.Fill, 0 });
        lua.setfield(L, -2, "Fill");
        push_lua_semantic_size_table(L, { ui.SemanticSizeKind.ChildrenSum, 0 });
        lua.setfield(L, -2, "ChildrenSum");
        push_lua_semantic_size_table(L, { ui.SemanticSizeKind.FitText, 0 });
        lua.setfield(L, -2, "FitText");

        lua.L_setfuncs(L, raw_data(&ui_lib), 0);
        lua.setglobal(L, "UI");
    }

    if lua.L_dofile(L, "plugins/lua/view.lua") == i32(lua.OK) {
        lua.pop(L, lua.gettop(L));
    } else {
        err := lua.tostring(L, lua.gettop(L));
        lua.pop(L, lua.gettop(L));

        log.error(err);
    }

    // Initialize Lua Plugins
    {
        lua.getglobal(L, "OnInit");
        if lua.pcall(L, 0, 0, 0) == i32(lua.OK) {
            lua.pop(L, lua.gettop(L));
        } else {
            err := lua.tostring(L, lua.gettop(L));
            lua.pop(L, lua.gettop(L));

            log.error("failed to initialize plugin (OnInit):", err);
        }
    }
    // **********************************************************************

    control_key_pressed: bool;
    for !state.should_close {
        // if false {
        //     buffer := core.current_buffer(&state);

        //     ui.push_parent(&ui_context, ui.push_box(&ui_context, "main", {}, .Vertical, semantic_size = {ui.make_semantic_size(.Fill, 100), ui.make_semantic_size(.Fill, 100)}));
        //     defer ui.pop_parent(&ui_context);

        //     {
        //         ui.push_parent(&ui_context, ui.push_box(&ui_context, "top_nav", {.DrawBackground}, semantic_size = {ui.make_semantic_size(.PercentOfParent, 100), ui.make_semantic_size(.Exact, state.source_font_height)}));
        //         defer ui.pop_parent(&ui_context);

        //         if ui.label(&ui_context, "Editor").clicked {
        //             fmt.println("you clicked the button");
        //         }

        //         ui.push_box(
        //             &ui_context,
        //             "nav spacer",
        //             {.DrawBackground},
        //             semantic_size = {
        //                 ui.make_semantic_size(.Exact, 16),
        //                 ui.make_semantic_size(.Exact, state.source_font_height)
        //             }
        //         );

        //         if ui.label(&ui_context, "Buffers").clicked {
        //             fmt.println("you clicked the button");
        //         }
        //     }
        //     {
        //         ui.push_parent(&ui_context, ui.push_box(&ui_context, "deezbuffer", {}, .Horizontal, semantic_size = {ui.make_semantic_size(.PercentOfParent, 100), ui.make_semantic_size(.Fill, 0)}));
        //         defer ui.pop_parent(&ui_context);

        //         {
        //             ui.push_parent(&ui_context, ui.push_box(&ui_context, "left side", {}, .Vertical, semantic_size = {ui.make_semantic_size(.Fill), ui.make_semantic_size(.Fill, 0)}));
        //             defer ui.pop_parent(&ui_context);

        //             {
        //                 if ui_file_buffer(&ui_context, &state.buffers[0]).clicked {
        //                     state.current_buffer = 0;
        //                 }
        //             }
        //             {
        //                 if ui_file_buffer(&ui_context, &state.buffers[0+1]).clicked {
        //                     state.current_buffer = 1;
        //                 }
        //             }
        //             {
        //                 if ui_file_buffer(&ui_context, &state.buffers[0+2]).clicked {
        //                     state.current_buffer = 2;
        //                 }
        //             }
        //         }
        //         {
        //             ui.push_parent(&ui_context, ui.push_box(&ui_context, "right side", {}, .Vertical, semantic_size = {ui.make_semantic_size(.Fill), ui.make_semantic_size(.Fill, 0)}));
        //             defer ui.pop_parent(&ui_context);

        //             {
        //                 if ui_file_buffer(&ui_context, core.current_buffer(&state)).clicked {
        //                     state.current_buffer = 3;
        //                 }
        //             }
        //         }
        //     }
        //     {
        //         ui.push_parent(&ui_context, ui.push_box(&ui_context, "bottom stats", {.DrawBackground}, semantic_size = {ui.make_semantic_size(.PercentOfParent, 100), ui.make_semantic_size(.Exact, state.source_font_height)}));
        //         defer ui.pop_parent(&ui_context);

        //         label := "";
        //         if state.mode == .Insert {
        //             label = "INSERT";
        //         } else if state.mode == .Normal {
        //             label = "NORMAL";
        //         }

        //         if ui.label(&ui_context, label).clicked {
        //             fmt.println("you clicked the button");
        //         }
        //         ui.spacer(&ui_context, "mode spacer", semantic_size = {ui.make_semantic_size(.Exact, 16), ui.make_semantic_size(.Fill)});

        //         relative_file_path, _ := filepath.rel(state.directory, buffer.file_path, context.temp_allocator)
        //         ui.label(&ui_context, relative_file_path);

        //         ui.spacer(&ui_context, "stats inbetween");

        //         {
        //             ui.push_parent(&ui_context, ui.push_box(&ui_context, "center info", {}, semantic_size = ui.ChildrenSum));
        //             defer ui.pop_parent(&ui_context);

        //             line_info_text := fmt.tprintf(
        //                 //"Line: %d, Col: %d, Len: %d --- Slice Index: %d, Content Index: %d",
        //                 "Line: %d, Col: %d",
        //                 buffer.cursor.line + 1,
        //                 buffer.cursor.col + 1,
        //                 //core.file_buffer_line_length(buffer, buffer.cursor.index),
        //                 // buffer.cursor.index.slice_index,
        //                 // buffer.cursor.index.content_index,
        //             );
        //             ui.label(&ui_context, line_info_text);

        //             mouse_pos_str := fmt.tprintf("x,y: [%d,%d]", ui_context.mouse_x, ui_context.mouse_y);
        //             ui.label(&ui_context, mouse_pos_str);
        //         }
        //     }
        // }

        // TODO: move this to view.lua
        // log_window, _ := ui.push_floating(&ui_context, "log", {0,0}, flags = {.Floating, .DrawBackground}, semantic_size = {ui.make_semantic_size(.PercentOfParent, 75), ui.make_semantic_size(.PercentOfParent, 75)});
        // ui.push_parent(&ui_context, log_window);
        // {
        //     defer ui.pop_parent(&ui_context);
        //     ui_file_buffer(&ui_context, &state.log_buffer);
        // }


        for hook_ref in state.lua_hooks[plugin.Hook.Draw] {
            lua.rawgeti(state.L, lua.REGISTRYINDEX, lua.Integer(hook_ref));
            lua.pushlightuserdata(state.L, &ui_context);
            if lua.pcall(state.L, 1, 0, 0) != i32(lua.OK) {
                err := lua.tostring(L, lua.gettop(L));
                lua.pop(L, lua.gettop(L));

                log.error(err);
            } else {
                lua.pop(L, lua.gettop(L));
            }
        }

        if state.window != nil && state.window.draw != nil {
            state.window.draw(state.plugin_vtable, state.window.user_data);
        }

        {
            ui_context.last_mouse_left_down = ui_context.mouse_left_down;
            ui_context.last_mouse_right_down = ui_context.mouse_right_down;

            ui_context.last_mouse_x = ui_context.mouse_x;
            ui_context.last_mouse_y = ui_context.mouse_y;

            sdl_event: sdl2.Event;
            for(sdl2.PollEvent(&sdl_event)) {
                if sdl_event.type == .QUIT {
                    state.should_close = true;
                }

                if sdl_event.type == .MOUSEMOTION {
                    ui_context.mouse_x = int(f32(sdl_event.motion.x) * state.width_dpi_ratio);
                    ui_context.mouse_y = int(f32(sdl_event.motion.y) * state.height_dpi_ratio);
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
                    case .Visual: fallthrough
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
                                            case core.LuaEditorAction:
                                                lua.rawgeti(state.L, lua.REGISTRYINDEX, lua.Integer(value.fn_ref));
                                                if lua.pcall(state.L, 0, 0, 0) != i32(lua.OK) {
                                                    err := lua.tostring(L, lua.gettop(L));
                                                    lua.pop(L, lua.gettop(L));

                                                    log.error(err);
                                                } else {
                                                    lua.pop(L, lua.gettop(L));
                                                }

                                                if value.maybe_input_map.ctrl_key_actions != nil {

                                                }
                                            case core.PluginEditorAction:
                                                value(state.plugin_vtable);
                                            case core.EditorAction:
                                                value(&state);
                                            case core.InputActions:
                                                state.current_input_map = &(&state.current_input_map.ctrl_key_actions[key]).action.(core.InputActions)
                                        }
                                    }
                                } else {
                                    if action, exists := state.current_input_map.key_actions[key]; exists {
                                        switch value in action.action {
                                            case core.LuaEditorAction:
                                                lua.rawgeti(state.L, lua.REGISTRYINDEX, lua.Integer(value.fn_ref));
                                                if lua.pcall(state.L, 0, 0, 0) != i32(lua.OK) {
                                                    err := lua.tostring(L, lua.gettop(L));
                                                    lua.pop(L, lua.gettop(L));

                                                    log.error(err);
                                                } else {
                                                    lua.pop(L, lua.gettop(L));
                                                }

                                                if value.maybe_input_map.key_actions != nil {
                                                    ptr_action := &(&state.current_input_map.key_actions[key]).action.(core.LuaEditorAction)
                                                    state.current_input_map = (&ptr_action.maybe_input_map)
                                                }
                                            case core.PluginEditorAction:
                                                value(state.plugin_vtable);
                                            case core.EditorAction:
                                                value(&state);
                                            case core.InputActions:
                                                state.current_input_map = &(&state.current_input_map.key_actions[key]).action.(core.InputActions)
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
                            buffer = core.current_buffer(&state);
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
                                    for hook_ref in state.lua_hooks[plugin.Hook.BufferInput] {
                                        lua.rawgeti(state.L, lua.REGISTRYINDEX, lua.Integer(hook_ref));
                                        if lua.pcall(state.L, 0, 0, 0) != i32(lua.OK) {
                                            err := lua.tostring(L, lua.gettop(L));
                                            lua.pop(L, lua.gettop(L));

                                            log.error(err);
                                        } else {
                                            lua.pop(L, lua.gettop(L));
                                        }
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
                                    for hook_ref in state.lua_hooks[plugin.Hook.BufferInput] {
                                        lua.rawgeti(state.L, lua.REGISTRYINDEX, lua.Integer(hook_ref));
                                        if lua.pcall(state.L, 0, 0, 0) != i32(lua.OK) {
                                            err := lua.tostring(L, lua.gettop(L));
                                            lua.pop(L, lua.gettop(L));

                                            log.error(err);
                                        } else {
                                            lua.pop(L, lua.gettop(L));
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        draw(&StateWithUi { &state, &ui_context });

        ui.prune(&ui_context);

        switch state.mode {
            case .Normal:
                if state.window != nil && state.window.get_buffer != nil {
                    buffer := transmute(^core.FileBuffer)(state.window.get_buffer(state.plugin_vtable, state.window.user_data));
                    do_normal_mode(&state, buffer);
                } else {
                    buffer := core.current_buffer(&state);
                    do_normal_mode(&state, buffer);
                }
            case .Insert:
                if state.window != nil && state.window.get_buffer != nil {
                    buffer := transmute(^core.FileBuffer)(state.window.get_buffer(state.plugin_vtable, state.window.user_data));
                    do_insert_mode(&state, buffer);
                } else {
                    buffer := core.current_buffer(&state);
                    do_insert_mode(&state, buffer);
                }
            case .Visual:
                if state.window != nil && state.window.get_buffer != nil {
                    // TODO
                } else {
                    buffer := core.current_buffer(&state);
                    do_visual_mode(&state, buffer);
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
    lua.close(L);

    sdl2.Quit();
}
