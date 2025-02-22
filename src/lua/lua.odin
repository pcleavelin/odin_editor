package lua

import "core:os"
import "core:fmt"
import "core:strings"
import "core:log"
import "core:path/filepath"

import core "../core"
import plugin "../plugin"
import ui "../ui"

import lua "vendor:lua/5.4"

state: ^core.State = nil

new_state :: proc(_state: ^core.State) {
    state = _state 

    state.L = lua.L_newstate();
    lua.L_openlibs(state.L);

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

                core.add_lua_hook(state, plugin.Hook(hook), fn_ref);

                return i32(lua.OK);
            }
        },
        lua.L_Reg {
            "register_key_group",
            register_key_group,
        },
        lua.L_Reg {
            "spawn_floating_window",
            proc "c" (L: ^lua.State) -> i32 {
                context = state.ctx;

                core.close_window_and_free(state);

                window_input_map := core.new_input_actions();
                lua.L_checktype(L, 1, i32(lua.TTABLE));
                table_to_action(L, 1, &window_input_map);

                lua.L_checktype(L, 2, i32(lua.TFUNCTION));
                lua.pushvalue(L, 2);
                fn_ref := lua.L_ref(L, i32(lua.REGISTRYINDEX));

                state.new_window = core.NewWindow {
                    input_map = window_input_map,
                    lua_draw_proc = fn_ref
                }
                state.current_input_map = &(&state.new_window.?).input_map

                return i32(lua.OK);
            }
        },
        lua.L_Reg {
            "request_window_close",
            proc "c" (L: ^lua.State) -> i32 {
                context = state.ctx;

                core.request_window_close(state);

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
                    push_lua_buffer_info :: proc(L: ^lua.State, buffer: ^core.FileBuffer) {
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

                    push_lua_buffer_info(L, core.buffer_from_index(state, buffer_index));
                }

                return 1;
            }
        },
        lua.L_Reg {
            "query_command_group",
            proc "c" (L: ^lua.State) -> i32 {
                context = state.ctx;

                group := lua.L_checkstring(L, 1);
                cmds := core.query_editor_commands_by_group(&state.commands, string(group), context.temp_allocator);

                lua.newtable(L);
                {
                    for cmd, i in cmds {
                        lua.newtable(L);
                        {
                            lua.pushstring(L, strings.clone_to_cstring(cmd.name, context.temp_allocator));
                            lua.setfield(L, -2, "name");

                            lua.pushstring(L, strings.clone_to_cstring(cmd.description, context.temp_allocator));
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
                core.run_command(state, string(group), string(name));

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
                    flags, err := ui_flags(L, 3);
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
                    flags, err := ui_flags(L, 3);
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
                    flags, err := ui_flags(L, 3);

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

                    ui_file_buffer(ui_ctx, core.buffer_from_index(state, buffer_index));

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
    lua.newtable(state.L);
    {
        lua.newtable(state.L);
        lua.pushinteger(state.L, lua.Integer(plugin.Key.B));
        lua.setfield(state.L, -2, "B");

        lua.pushinteger(state.L, lua.Integer(plugin.Key.F));
        lua.setfield(state.L, -2, "F");

        lua.pushinteger(state.L, lua.Integer(plugin.Key.T));
        lua.setfield(state.L, -2, "T");

        lua.pushinteger(state.L, lua.Integer(plugin.Key.Y));
        lua.setfield(state.L, -2, "Y");

        lua.pushinteger(state.L, lua.Integer(plugin.Key.P));
        lua.setfield(state.L, -2, "P");

        lua.pushinteger(state.L, lua.Integer(plugin.Key.M));
        lua.setfield(state.L, -2, "M");

        lua.pushinteger(state.L, lua.Integer(plugin.Key.K));
        lua.setfield(state.L, -2, "K");

        lua.pushinteger(state.L, lua.Integer(plugin.Key.J));
        lua.setfield(state.L, -2, "J");

        lua.pushinteger(state.L, lua.Integer(plugin.Key.Q));
        lua.setfield(state.L, -2, "Q");

        lua.pushinteger(state.L, lua.Integer(plugin.Key.BACKQUOTE));
        lua.setfield(state.L, -2, "Backtick");

        lua.pushinteger(state.L, lua.Integer(plugin.Key.ESCAPE));
        lua.setfield(state.L, -2, "Escape");

        lua.pushinteger(state.L, lua.Integer(plugin.Key.ENTER));
        lua.setfield(state.L, -2, "Enter");

        lua.pushinteger(state.L, lua.Integer(plugin.Key.SPACE));
        lua.setfield(state.L, -2, "Space");
    }
    lua.setfield(state.L, -2, "Key");

    {
        lua.newtable(state.L);
        lua.pushinteger(state.L, lua.Integer(plugin.Hook.BufferInput));
        lua.setfield(state.L, -2, "OnBufferInput");
        lua.pushinteger(state.L, lua.Integer(plugin.Hook.Draw));
        lua.setfield(state.L, -2, "OnDraw");
    }
    lua.setfield(state.L, -2, "Hook");

    lua.L_setfuncs(state.L, bbb, 0);
    lua.setglobal(state.L, "Editor");

    lua.newtable(state.L);
    {
        lua.pushinteger(state.L, lua.Integer(ui.Axis.Horizontal));
        lua.setfield(state.L, -2, "Horizontal");
        lua.pushinteger(state.L, lua.Integer(ui.Axis.Vertical));
        lua.setfield(state.L, -2, "Vertical");
        push_lua_semantic_size_table(state.L, { ui.SemanticSizeKind.Fill, 0 });
        lua.setfield(state.L, -2, "Fill");
        push_lua_semantic_size_table(state.L, { ui.SemanticSizeKind.ChildrenSum, 0 });
        lua.setfield(state.L, -2, "ChildrenSum");
        push_lua_semantic_size_table(state.L, { ui.SemanticSizeKind.FitText, 0 });
        lua.setfield(state.L, -2, "FitText");

        lua.L_setfuncs(state.L, raw_data(&ui_lib), 0);
        lua.setglobal(state.L, "UI");
    }
}

close :: proc(L: ^lua.State) {
    lua.close(L)
}


@(private)
register_key_group ::proc "c" (L: ^lua.State) -> i32 {
    context = state.ctx;

    lua.L_checktype(L, 1, i32(lua.TTABLE));
    table_to_action(L, 1, state.current_input_map);

    return i32(lua.OK);
}

@(private)
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

load_plugins :: proc(state: ^core.State, dir: string) {
    filepath.walk(filepath.join({ os.get_current_directory(), dir }), walk_plugins, transmute(rawptr)state);
    log.info("done walking")

    for plugin in state.new_plugins {
        // FIXME: check if the global actually exists
        lua.getglobal(state.L, fmt.ctprintf("%s_%s", plugin.namespace, plugin.name));

        lua.getfield(state.L, -1, "OnLoad");
        if (lua.isnil(state.L, -1)) {
            lua.pop(state.L, 2)
            log.warn("plugin", plugin.name, "doesn't have an 'OnLoad' function")

            continue
        }

        if lua.pcall(state.L, 0, 0, 0) == i32(lua.OK) {
            lua.pop(state.L, lua.gettop(state.L));
        } else {
            err := lua.tostring(state.L, lua.gettop(state.L));
            lua.pop(state.L, lua.gettop(state.L));
            lua.pop(state.L, 1);

            log.error("failed to initialize plugin (OnLoad):", err);
        }

    }
}

walk_plugins :: proc(info: os.File_Info, in_err: os.Errno, state: rawptr) -> (err: os.Errno, skip_dir: bool) {
    state := cast(^core.State)state;

    relative_file_path, rel_error := filepath.rel(state.directory, info.fullpath);
    extension := filepath.ext(info.fullpath);

    if extension == ".lua" {
        log.info("attempting to load", relative_file_path)

        if plugin, ok := load_plugin(state, info.fullpath); ok {
            append(&state.new_plugins, plugin);

            if rel_error == .None {
                log.info("Loaded", relative_file_path);
            } else {
                log.info("Loaded", info.fullpath);
            }
        } else {
            log.error("failed to load")
        }
    }

    return in_err, skip_dir;
}

load_plugin :: proc(state: ^core.State, path: string) -> (lua_plugin: plugin.NewInterface, ok: bool) {
    if lua.L_dofile(state.L, strings.clone_to_cstring(path, allocator = context.temp_allocator)) != i32(lua.OK) {
        err := lua.tostring(state.L, lua.gettop(state.L))
        lua.pop(state.L, lua.gettop(state.L))

        log.error("failed to load lua plugin:", err)
        return
    }

    lua.getfield(state.L, -1, "name");
    if (lua.isnil(state.L, -1)) {
        lua.pop(state.L, 2)

        log.error("no name for lua plugin")
        return
    }
    name := strings.clone(string(lua.tostring(state.L, -1)))
    lua.pop(state.L, 1)

    lua.getfield(state.L, -1, "version");
    if (lua.isnil(state.L, -1)) {
        lua.pop(state.L, 2)
        return
    }
    version := strings.clone(string(lua.tostring(state.L, -1)))
    lua.pop(state.L, 1)

    lua.getfield(state.L, -1, "namespace");
    if (lua.isnil(state.L, -1)) {
        lua.pop(state.L, 2)
        return
    }
    namespace := strings.clone(string(lua.tostring(state.L, -1)))
    lua.pop(state.L, 1)

    // Add plugin to lua globals
    lua.setglobal(state.L, fmt.caprintf("%s_%s", namespace, name))

    return plugin.NewInterface {
        name = name,
        version = version,
        namespace = namespace,
    }, true
}

ui_flags :: proc(L: ^lua.State, index: i32) -> (bit_set[ui.Flag], bool) {
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

run_editor_action :: proc(state: ^core.State, key: plugin.Key, action: core.LuaEditorAction) {
    lua.rawgeti(state.L, lua.REGISTRYINDEX, lua.Integer(action.fn_ref));
    if lua.pcall(state.L, 0, 0, 0) != i32(lua.OK) {
        err := lua.tostring(state.L, lua.gettop(state.L));
        lua.pop(state.L, lua.gettop(state.L));

        log.error(err);
    } else {
        lua.pop(state.L, lua.gettop(state.L));
    }

    if action.maybe_input_map.key_actions != nil {
        ptr_action := &(&state.current_input_map.key_actions[key]).action.(core.LuaEditorAction)
        state.current_input_map = (&ptr_action.maybe_input_map)
    }
}

run_ui_function :: proc(state: ^core.State, ui_context: ^ui.Context, fn_ref: i32) {
    lua.rawgeti(state.L, lua.REGISTRYINDEX, lua.Integer(fn_ref));
    lua.pushlightuserdata(state.L, ui_context);
    if lua.pcall(state.L, 1, 0, 0) != i32(lua.OK) {
        err := lua.tostring(state.L, lua.gettop(state.L));
        lua.pop(state.L, lua.gettop(state.L));

        log.error(err);
    } else {
        lua.pop(state.L, lua.gettop(state.L));
    }
}

// TODO: don't duplicate this procedure
ui_file_buffer :: proc(ctx: ^ui.Context, buffer: ^core.FileBuffer) -> ui.Interaction {
    draw_func := proc(state: ^core.State, box: ^ui.Box, user_data: rawptr) {
        buffer := transmute(^core.FileBuffer)user_data;
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
