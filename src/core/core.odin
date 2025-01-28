package core

import "core:runtime"
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

    state.current_input_map = &state.input_map.mode[.Normal];
}

LuaHookRef :: i32;
State :: struct {
    ctx: runtime.Context,
    L: ^lua.State,
    sdl_renderer: ^sdl2.Renderer,
    font_atlas: FontAtlas,

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
    should_close_window: bool,

    input_map: InputMap,
    current_input_map: ^InputActions,

    plugins: [dynamic]plugin.Interface,
    plugin_vtable: plugin.Plugin,
    highlighters: map[string]plugin.OnColorBufferProc,
    hooks: map[plugin.Hook][dynamic]plugin.OnHookProc,
    lua_hooks: map[plugin.Hook][dynamic]LuaHookRef,
}

current_buffer :: proc(state: ^State) -> ^FileBuffer {
    if state.current_buffer == -2 {
        return &state.log_buffer;
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
            input_map.mode[(cast(^Mode)(&i))^] = new_input_actions();
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
    for _, actions in &input_map.mode {
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
