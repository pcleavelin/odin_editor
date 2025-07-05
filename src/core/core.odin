package core

import "base:runtime"
import "base:intrinsics"
import "core:reflect"
import "core:fmt"
import "core:log"
import "vendor:sdl2"
import lua "vendor:lua/5.4"

import "../plugin"

Mode :: enum {
    Normal,
    Insert,
    Visual,
}

Window :: struct {
    input_map: InputActions,
    draw: plugin.WindowDrawProc,
    free_user_data: plugin.WindowFreeProc,

    get_buffer: plugin.WindowGetBufferProc,

    // TODO: create hook for when mode changes happen

    user_data: rawptr,
}
NewWindow :: struct {
    input_map: InputActions,
    lua_draw_proc: i32,
}
request_window_close :: proc(state: ^State) {
    state.should_close_window = true;
}

close_window_and_free :: proc(state: ^State) {
    if state.window != nil {
        if state.window.free_user_data != nil {
            state.window.free_user_data(state.plugin_vtable, state.window.user_data);
        }

        delete_input_actions(&state.window.input_map);
        free(state.window);

        state.window = nil;
    }

    if window, ok := &state.new_window.(NewWindow); ok {
        delete_input_actions(&window.input_map);
        state.new_window = nil
    }

    state.current_input_map = &state.input_map.mode[.Normal];
}

LuaHookRef :: i32;
EditorCommandList :: map[string][dynamic]EditorCommand;
State :: struct {
    ctx: runtime.Context,
    L: ^lua.State,
    sdl_renderer: ^sdl2.Renderer,
    font_atlas: FontAtlas,
    ui: rawptr,

    mode: Mode,
    should_close: bool,
    screen_height: int,
    screen_width: int,
    width_dpi_ratio: f32,
    height_dpi_ratio: f32,

    directory: string,

    source_font_width: int,
    source_font_height: int,
    line_number_padding: int,

    current_buffer: int,
    buffers: [dynamic]FileBuffer,

    log_buffer: FileBuffer,

    window: ^Window,
    new_window: Maybe(NewWindow),
    should_close_window: bool,

    input_map: InputMap,
    current_input_map: ^InputActions,

    commands: EditorCommandList,
    command_arena: runtime.Allocator,
    command_args: [dynamic]EditorCommandArgument,

    active_panels: [128]Maybe(Panel),
    panel_catalog: [dynamic]PanelId,

    plugins: [dynamic]plugin.Interface,
    new_plugins: [dynamic]plugin.NewInterface,
    plugin_vtable: plugin.Plugin,
    highlighters: map[string]plugin.OnColorBufferProc,
    hooks: map[plugin.Hook][dynamic]plugin.OnHookProc,
    lua_hooks: map[plugin.Hook][dynamic]LuaHookRef,
}

EditorCommand :: struct {
    name: string,
    description: string,
    action: EditorAction,
}

EditorCommandExec :: struct {
    num_args: int,
    args: [dynamic]EditorCommandArgument,
}

EditorCommandArgument :: union #no_nil {
    string,
    i32
}

PanelId :: union #no_nil {
    LuaPanelId,
    LibPanelId,
}
Panel :: union #no_nil {
    LuaPanel,
    LibPanel,
}


LuaPanelId :: struct {
    id: string,
    name: string,
}
LuaPanel :: struct {
    panel_id: LuaPanelId,
    index: i32,
    render_ref: i32
}

// TODO
LibPanelId :: struct {}
LibPanel :: struct {}

current_buffer :: proc(state: ^State) -> ^FileBuffer {
    if state.current_buffer == -2 {
        return &state.log_buffer;
    }

    if len(state.buffers) < 1 {
        return nil
    }

    return &state.buffers[state.current_buffer];
}

buffer_from_index :: proc(state: ^State, buffer_index: int) -> ^FileBuffer {
    if buffer_index == -2 {
        return &state.log_buffer;
    }

    return &state.buffers[buffer_index];
}

add_hook :: proc(state: ^State, hook: plugin.Hook, hook_proc: plugin.OnHookProc) {
    if _, exists := state.hooks[hook]; !exists {
        state.hooks[hook] = make([dynamic]plugin.OnHookProc);
    }

    runtime.append(&state.hooks[hook], hook_proc);
}

add_lua_hook :: proc(state: ^State, hook: plugin.Hook, hook_ref: LuaHookRef) {
    if _, exists := state.lua_hooks[hook]; !exists {
        state.lua_hooks[hook] = make([dynamic]LuaHookRef);
        log.info("added lua hook", hook)
    }

    runtime.append(&state.lua_hooks[hook], hook_ref);
}

LuaEditorAction :: struct {
    fn_ref: i32,
    maybe_input_map: InputActions,
};
PluginEditorAction :: proc "c" (plugin: plugin.Plugin);
EditorAction :: proc(state: ^State);
InputGroup :: union {LuaEditorAction, PluginEditorAction, EditorAction, InputActions}
Action :: struct {
    action: InputGroup,
    description: string,
}
InputMap :: struct {
    mode: map[Mode]InputActions,
}
InputActions :: struct {
    key_actions: map[plugin.Key]Action,
    ctrl_key_actions: map[plugin.Key]Action,
}

new_input_map :: proc() -> InputMap {
    input_map := InputMap {
        mode = make(map[Mode]InputActions),
    }

    ti := runtime.type_info_base(type_info_of(Mode));
    if v, ok := ti.variant.(runtime.Type_Info_Enum); ok {
        for i in &v.values {
            input_map.mode[cast(Mode)i] = new_input_actions();
        }
    }

    return input_map;
}

new_input_actions :: proc() -> InputActions {
    input_actions := InputActions {
        key_actions = make(map[plugin.Key]Action),
        ctrl_key_actions = make(map[plugin.Key]Action),
    }

    return input_actions;
}
delete_input_map :: proc(input_map: ^InputMap) {
    for _, &actions in input_map.mode {
        delete_input_actions(&actions);
    }
    delete(input_map.mode);
}
delete_input_actions :: proc(input_map: ^InputActions) {
    delete(input_map.key_actions);
    delete(input_map.ctrl_key_actions);
}

// NOTE(pcleavelin): might be a bug in the compiler where it can't coerce
// `EditorAction` to `InputGroup` when given as a proc parameter, that is why there
// are two functions
register_plugin_key_action_single :: proc(input_map: ^InputActions, key: plugin.Key, action: PluginEditorAction, description: string = "") {
    if ok := key in input_map.key_actions; ok {
        // TODO: log that key is already registered
        log.error("plugin key already registered with single action", key);
    }

    input_map.key_actions[key] = Action {
        action = action,
        description = description,
    };
}

register_key_action_single :: proc(input_map: ^InputActions, key: plugin.Key, action: EditorAction, description: string = "") {
    if ok := key in input_map.key_actions; ok {
        // TODO: log that key is already registered
        log.error("key already registered with single action", key);
    }

    input_map.key_actions[key] = Action {
        action = action,
        description = description,
    };
}

register_key_action_group :: proc(input_map: ^InputActions, key: plugin.Key, input_group: InputGroup, description: string = "") {
    if ok := key in input_map.key_actions; ok {
        // TODO: log that key is already registered
        fmt.eprintln("key already registered with single action", key);
    }

    input_map.key_actions[key] = Action {
        action = input_group,
        description = description,
    };
}

register_ctrl_key_action_single :: proc(input_map: ^InputActions, key: plugin.Key, action: EditorAction, description: string = "") {
    if ok := key in input_map.key_actions; ok {
        // TODO: log that key is already registered
        log.error("key already registered with single action", key);
    }

    input_map.ctrl_key_actions[key] = Action {
        action = action,
        description = description,
    };
}

register_ctrl_key_action_group :: proc(input_map: ^InputActions, key: plugin.Key, input_group: InputGroup, description: string = "") {
    if ok := key in input_map.key_actions; ok {
        // TODO: log that key is already registered
        log.error("key already registered with single action", key);
    }

    input_map.ctrl_key_actions[key] = Action {
        action = input_group,
        description = description,
    };
}

register_key_action :: proc{register_plugin_key_action_single, register_key_action_single, register_key_action_group};
register_ctrl_key_action :: proc{register_ctrl_key_action_single, register_ctrl_key_action_group};

register_editor_command :: proc(command_list: ^EditorCommandList, command_group, name, description: string, action: EditorAction) {
    if _, ok := command_list[command_group]; !ok {
        command_list[command_group] = make([dynamic]EditorCommand);
    }

    runtime.append(&command_list[command_group], EditorCommand {
        name = name,
        description = description,
        action = action,
    });
}

query_editor_commands_by_name :: proc(command_list: ^EditorCommandList, name: string, allocator: runtime.Allocator) -> []EditorCommand {
    context.allocator = allocator;
    commands := make([dynamic]EditorCommand)

    for group, list in command_list {
        for cmd in list {
            if cmd.name == name {
                append(&commands, cmd);
            }
        }
    }

    return commands[:];
}

query_editor_commands_by_group :: proc(command_list: ^EditorCommandList, name: string, allocator: runtime.Allocator) -> []EditorCommand {
    context.allocator = allocator;
    commands := make([dynamic]EditorCommand)

    for group, list in command_list {
        if group == name {
            for cmd in list {
                append(&commands, cmd);
            }
        }
    }

    return commands[:];
}

push_command_arg :: proc(state: ^State, command_arg: EditorCommandArgument) {
    context.allocator = state.command_arena;

    if state.command_args == nil {
        state.command_args = make([dynamic]EditorCommandArgument);
    }

    append(&state.command_args, command_arg)
}

run_command :: proc(state: ^State, group: string, name: string) {
    if state.command_args == nil {
        state.command_args = make([dynamic]EditorCommandArgument);
    }

    defer {
        state.command_args = nil
        runtime.free_all(state.command_arena)
    }

    if cmds, ok := state.commands[group]; ok {
        for cmd in cmds {
            if cmd.name == name {
                log.info("Running command", group, name);
                cmd.action(state);
                return;
            }
        }
    }

    log.error("no command", group, name);
}

attempt_read_command_args :: proc($T: typeid, args: []EditorCommandArgument) -> (value: T, ok: bool)
where intrinsics.type_is_struct(T) {
    ti := runtime.type_info_base(type_info_of(T));

    #partial switch v in ti.variant {
        case runtime.Type_Info_Struct:
        {
            if int(v.field_count) != len(args) {
                ok = false
                log.error("invalid number of arguments", len(args), ", expected", v.field_count);
                return
            }

            for arg, i in args {
                switch varg in arg {
                    case string:
                    {
                        if _, is_string := v.types[i].variant.(runtime.Type_Info_String); !is_string {
                            ok = false
                            log.error("invalid argument #", i, "given to command, found string, expected", v.types[i].variant)
                            return
                        }

                        value_string: ^string = transmute(^string)(uintptr(&value) + v.offsets[i])
                        value_string^ = varg
                    }
                    case i32:
                    {

                        if _, is_integer := v.types[i].variant.(runtime.Type_Info_Integer); !is_integer {
                            ok = false
                            log.error("invalid argument #", i, "given to command, unexpected integer, expected", v.types[i].variant)
                            return
                        }

                        value_i32: ^i32 = transmute(^i32)(uintptr(&value) + v.offsets[i])
                        value_i32^ = varg
                    }
                }
            }
        }
        case:
        {
            return
        }
    }

    ok = true

    return
}

register_panel_lua :: proc(state: ^State, name: string, id: string) {
    append(&state.panel_catalog, LuaPanelId {
        id = id,
        name = name,
    })
}

