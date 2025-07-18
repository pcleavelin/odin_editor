package main

import "core:c"
import "core:os"
import "core:path/filepath"
import "core:math"
import "core:strings"
import "base:runtime"
import "core:fmt"
import "core:log"
import "core:mem"
import "core:slice"
import "vendor:sdl2"
import "vendor:sdl2/ttf"

import "util"
import "core"
import "panels"
import "theme"
import "ui"
import ts "tree_sitter"

State :: core.State;
FileBuffer :: core.FileBuffer;

// TODO: should probably go into state
scratch: mem.Scratch;
scratch_alloc: runtime.Allocator;
state := core.State {};

do_normal_mode :: proc(state: ^State, buffer: ^FileBuffer) {
}

do_insert_mode :: proc(state: ^State, buffer: ^FileBuffer) {
    key := 0;

    for key > 0 {
        if key >= 32 && key <= 125 && len(buffer.input_buffer) < 1024-1 {
            append(&buffer.input_buffer, u8(key));
        }

        key = 0;
    }
}

do_visual_mode :: proc(state: ^State, buffer: ^FileBuffer) {
}

ui_font_width :: proc() -> i32 {
    return i32(state.source_font_width);
}
ui_font_height :: proc() -> i32 {
    return i32(state.source_font_height);
}

draw :: proc(state: ^State) {
    render_color := theme.get_palette_color(.Background);
    sdl2.SetRenderDrawColor(state.sdl_renderer, render_color.r, render_color.g, render_color.b, render_color.a);
    sdl2.RenderClear(state.sdl_renderer);

    new_ui := transmute(^ui.State)state.ui
    new_ui.max_size.x = state.screen_width
    new_ui.max_size.y = state.screen_height

    ui.open_element(new_ui, nil, {
        dir = .LeftToRight,
        kind = {ui.Grow{}, ui.Grow{}},
    })
    { 
        for i in 0..<len(state.panels.data) {
            if panel, ok := util.get(&state.panels, i).?; ok {
                if panel.render_proc != nil {
                    panel.render_proc(state, &panel.panel_state)
                }
            }
        }
    }
    ui.close_element(new_ui)

    ui.compute_layout_2(new_ui)
    ui.draw(new_ui, state)

    // TODO: figure out when to not show the input help menu
    if false && state.mode != .Insert { // && state.current_input_map != &state.input_map.mode[state.mode] {
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

        core.draw_rect(
            state,
            state.screen_width - longest_description * state.source_font_width,
            state.screen_height - helper_height - offset_from_bottom,
            longest_description*state.source_font_width,
            helper_height,
            .Background2
        );

        index := 0;
        for key, action in state.current_input_map.key_actions {
            core.draw_text(
                state,
                fmt.tprintf("%s - %s", key, action.description),
                state.screen_width - longest_description * state.source_font_width,
                state.screen_height - helper_height + index * state.source_font_height - offset_from_bottom
            );

            index += 1;
        }
        for key, action in state.current_input_map.ctrl_key_actions {
            core.draw_text(
                state,
                fmt.tprintf("<C>-%s - %s", key, action.description),
                state.screen_width - longest_description * state.source_font_width,
                state.screen_height - helper_height + index * state.source_font_height - offset_from_bottom
            );

            index += 1;
        }
    }

    sdl2.RenderPresent(state.sdl_renderer);
}

expose_event_watcher :: proc "c" (state: rawptr, event: ^sdl2.Event) -> i32 {
    if event.type == .WINDOWEVENT {
        state := transmute(^State)state;
        context = state.ctx;

        if event.window.event == .EXPOSED {
            //draw(state);
        } else if event.window.event == .SIZE_CHANGED {
            w,h: i32;

            sdl2.GetRendererOutputSize(state.sdl_renderer, &w, &h);

            state.screen_width = int(w);
            state.screen_height = int(h);
            state.width_dpi_ratio = f32(w) / f32(event.window.data1);
            state.height_dpi_ratio = f32(h) / f32(event.window.data2);

            // KDE resizes very slowly on linux if you trigger a re-render
            when ODIN_OS != .Linux {
                draw(state);
            }
        }
    }

    return 0;
}

main :: proc() {
   ts.set_allocator() 

    _command_arena: mem.Arena
    mem.arena_init(&_command_arena, make([]u8, 1024*1024));

    state = State {
        ctx = context,
        screen_width = 640,
        screen_height = 480,
        source_font_width = 8,
        source_font_height = 16,
        commands = make(core.EditorCommandList),
        command_arena = mem.arena_allocator(&_command_arena),

        panels = util.make_static_list(core.Panel, 128),

        directory = os.get_current_directory(),
        log_buffer = core.new_virtual_file_buffer(context.allocator),
    };

    // context.logger = core.new_logger(&state.log_buffer);
    context.logger = log.create_console_logger();
    state.ctx = context;

    state.ui = &ui.State {
        curr_elements = make([]ui.UI_Element, 8192),
        prev_elements = make([]ui.UI_Element, 8192),
    }

    // TODO: don't use this
    mem.scratch_allocator_init(&scratch, 1024*1024);
    scratch_alloc = mem.scratch_allocator(&scratch);

    core.reset_input_map(&state)

    // core.register_editor_command(
    //     &state.commands,
    //     "nl.spacegirl.editor.core",
    //     "Open New Panel",
    //     "Opens a new panel",
    //     proc(state: ^State) {
    //         Args :: struct {
    //             panel_id: string
    //         }

    //         if args, ok := core.attempt_read_command_args(Args, state.command_args[:]); ok {
    //             log.info("maybe going to open panel with id", args.panel_id)

    //             for p in state.panel_catalog {
    //                 switch v in p {
    //                     case core.LuaPanelId:
    //                     {
    //                         if v.id == args.panel_id {
    //                             if index, ok := lua.add_panel(state, v); ok {
    //                                 for i in 0..<len(state.active_panels) {
    //                                     if state.active_panels[i] == nil {
    //                                         state.active_panels[i] = index
    //                                         break;
    //                                     }
    //                                 }
    //                             } else {
    //                                 log.error("failed to open panel")
    //                             }
    //                         }
    //                     }
    //                     case core.LibPanelId:
    //                     {
    //                         log.warn("lib panels not supported yet")
    //                     }
    //                 }
    //             }
    //         }
    //     }
    // )

    // core.register_editor_command(
    //     &state.commands,
    //     "nl.spacegirl.editor.core",
    //     "New Scratch Buffer",
    //     "Opens a new scratch buffer",
    //     proc(state: ^State) {
    //         buffer := core.new_virtual_file_buffer(context.allocator);
    //         util.append_static_list(&state.panels, panels.make_file_buffer_panel(len(state.buffers)))
    //         runtime.append(&state.buffers, buffer);
    //     }
    // )
    // core.register_editor_command(
    //     &state.commands,
    //     "nl.spacegirl.editor.core",
    //     "Open File",
    //     "Opens a file in a new buffer",
    //     proc(state: ^State) {
    //         log.info("open file args:");

    //         Args :: struct {
    //             file_path: string
    //         }

    //         if args, ok := core.attempt_read_command_args(Args, state.command_args[:]); ok {
    //             log.info("attempting to open file", args.file_path)

    //             panels.open_file_buffer_in_new_panel(state, args.file_path, 0, 0)
    //         }
    //     }
    // )
    // core.register_editor_command(
    //     &state.commands,
    //     "nl.spacegirl.editor.core",
    //     "Quit",
    //     "Quits the application",
    //     proc(state: ^State) {
    //         state.should_close = true
    //     }
    // )

    if len(os.args) > 1 {
        for arg in os.args[1:] {
            panels.open_file_buffer_in_new_panel(&state, arg, 0, 0)
        }
    } else {
        // buffer := core.new_virtual_file_buffer(context.allocator);

        // panels.open(&state, panels.make_file_buffer_panel(len(state.buffers)))
        // runtime.append(&state.buffers, buffer);
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
        "odin_editor - [less plugins more speed]",
        sdl2.WINDOWPOS_UNDEFINED,
        sdl2.WINDOWPOS_UNDEFINED,
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
    state.font_atlas = core.gen_font_atlas(&state, core.HardcodedFontPath);
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

    sdl2.AddEventWatch(expose_event_watcher, &state);

    core.push_new_snapshot(&core.current_buffer(&state).history)

    control_key_pressed: bool;
    for !state.should_close {
        {
            // ui_context.last_mouse_left_down = ui_context.mouse_left_down;
            // ui_context.last_mouse_right_down = ui_context.mouse_right_down;

            // ui_context.last_mouse_x = ui_context.mouse_x;
            // ui_context.last_mouse_y = ui_context.mouse_y;

            sdl_event: sdl2.Event;
            for(sdl2.PollEvent(&sdl_event)) {
                if sdl_event.type == .QUIT {
                    state.should_close = true;
                }

                if sdl_event.type == .MOUSEMOTION {
                    // ui_context.mouse_x = int(f32(sdl_event.motion.x) * state.width_dpi_ratio);
                    // ui_context.mouse_y = int(f32(sdl_event.motion.y) * state.height_dpi_ratio);
                }

                if sdl_event.type == .MOUSEBUTTONDOWN || sdl_event.type == .MOUSEBUTTONUP {
                    event := sdl_event.button;

                    if event.button == sdl2.BUTTON_LEFT {
                        // ui_context.mouse_left_down = sdl_event.type == .MOUSEBUTTONDOWN;
                    }
                    if event.button == sdl2.BUTTON_RIGHT {
                        // ui_context.mouse_left_down = sdl_event.type == .MOUSEBUTTONDOWN;
                    }
                }

                run_key_action := proc(state: ^core.State, control_key_pressed: bool, key: core.Key) -> bool {
                    if current_panel, ok := state.current_panel.?; ok {
                        panel := util.get(&state.panels, current_panel).?

                        if control_key_pressed {
                            if action, exists := state.current_input_map.ctrl_key_actions[key]; exists {
                                switch value in action.action {
                                    case core.EditorAction:
                                        value(state, &panel);
                                        return true;
                                    case core.InputActions:
                                        state.current_input_map = &(&state.current_input_map.ctrl_key_actions[key]).action.(core.InputActions)
                                        return true;
                                }
                            }
                        } else {
                            if action, exists := state.current_input_map.key_actions[key]; exists {
                                switch value in action.action {
                                    case core.EditorAction:
                                        value(state, &panel);
                                        return true;
                                    case core.InputActions:
                                        state.current_input_map = &(&state.current_input_map.key_actions[key]).action.(core.InputActions)
                                        return true;
                                }
                            }
                        }
                    }

                    return false
                }

                switch state.mode {
                    case .Visual: fallthrough
                    case .Normal: {
                        if sdl_event.type == .KEYDOWN {
                            key := core.Key(sdl_event.key.keysym.sym);

                            if key == .LCTRL {
                                control_key_pressed = true;
                            } else  {
                                run_key_action(&state, control_key_pressed, key)
                            }
                        }
                        if sdl_event.type == .KEYUP {
                            key := core.Key(sdl_event.key.keysym.sym);
                            if key == .LCTRL {
                                control_key_pressed = false;
                            }
                        }
                    }
                    case .Insert: {
                        buffer := core.current_buffer(&state);

                        if sdl_event.type == .KEYDOWN {
                            key := core.Key(sdl_event.key.keysym.sym);

                            // TODO: make this work properly
                            if true || !run_key_action(&state, control_key_pressed, key) {
                                #partial switch key {
                                    case .ESCAPE: {
                                        state.mode = .Normal;

                                        core.insert_content(buffer, buffer.input_buffer[:]);
                                        runtime.clear(&buffer.input_buffer);

                                        sdl2.StopTextInput();
                                    }
                                    case .TAB: {
                                        // TODO: change this to insert a tab character
                                        for _ in 0..<4 {
                                            append(&buffer.input_buffer, ' ');
                                        }
                                    }
                                    case .BACKSPACE: {
                                        core.delete_content(buffer, 1);
                                    }
                                    case .ENTER: {
                                        append(&buffer.input_buffer, '\n');
                                    }
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
                                }
                            }

                            if current_panel, ok := state.current_panel.?; ok {
                                if panel, ok := util.get(&state.panels, current_panel).?; ok && panel.on_buffer_input_proc != nil {
                                    panel.on_buffer_input_proc(&state, &panel.panel_state)
                                }
                            }
                        }
                    }
                }
            }
        }

        draw(&state);

        switch state.mode {
            case .Normal:
                buffer := core.current_buffer(&state);
                do_normal_mode(&state, buffer);
            case .Insert:
                buffer := core.current_buffer(&state);
                do_insert_mode(&state, buffer);
            case .Visual:
                buffer := core.current_buffer(&state);
                do_visual_mode(&state, buffer);
        }

        runtime.free_all(context.temp_allocator);
    }

    sdl2.Quit();
}
