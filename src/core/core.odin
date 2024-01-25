package core

import "core:runtime"
import "core:fmt"
import "vendor:sdl2"

import "../plugin"

Mode :: enum {
    Normal,
    Insert,
}

Window :: struct {
    input_map: InputMap,
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

        delete_input_map(&state.window.input_map);
        free(state.window);

        state.window = nil;
        state.current_input_map = &state.input_map;
    }
}

State :: struct {
    ctx: runtime.Context,
    sdl_renderer: ^sdl2.Renderer,
    font_atlas: FontAtlas,

    mode: Mode,
    should_close: bool,
    screen_height: int,
    screen_width: int,

    directory: string,

    source_font_width: int,
    source_font_height: int,
    line_number_padding: int,

    current_buffer: int,
    buffers: [dynamic]FileBuffer,

    window: ^Window,
    should_close_window: bool,

    input_map: InputMap,
    current_input_map: ^InputMap,

    plugins: [dynamic]plugin.Interface,
    plugin_vtable: plugin.Plugin,
    highlighters: map[string]plugin.OnColorBufferProc,
    hooks: map[plugin.Hook][dynamic]plugin.OnHookProc,
}

add_hook :: proc(state: ^State, hook: plugin.Hook, hook_proc: plugin.OnHookProc) {
    if _, exists := state.hooks[hook]; !exists {
        state.hooks[hook] = make([dynamic]plugin.OnHookProc);
    }

    runtime.append(&state.hooks[hook], hook_proc);
}

PluginEditorAction :: proc "c" (plugin: plugin.Plugin);
EditorAction :: proc(state: ^State);
InputGroup :: union {PluginEditorAction, EditorAction, InputMap}
Action :: struct {
    action: InputGroup,
    description: string,
}
InputMap :: struct {
    key_actions: map[plugin.Key]Action,
    ctrl_key_actions: map[plugin.Key]Action,
}

new_input_map :: proc() -> InputMap {
    input_map := InputMap {
        key_actions = make(map[plugin.Key]Action),
        ctrl_key_actions = make(map[plugin.Key]Action),
    }

    return input_map;
}
delete_input_map :: proc(input_map: ^InputMap) {
    delete(input_map.key_actions);
    delete(input_map.ctrl_key_actions);
}

// NOTE(pcleavelin): might be a bug in the compiler where it can't coerce
// `EditorAction` to `InputGroup` when given as a proc parameter, that is why there
// are two functions
register_plugin_key_action_single :: proc(input_map: ^InputMap, key: plugin.Key, action: PluginEditorAction, description: string = "") {
    if ok := key in input_map.key_actions; ok {
        // TODO: log that key is already registered
        fmt.eprintln("plugin key already registered with single action", key);
    }

    input_map.key_actions[key] = Action {
        action = action,
        description = description,
    };
}

register_key_action_single :: proc(input_map: ^InputMap, key: plugin.Key, action: EditorAction, description: string = "") {
    if ok := key in input_map.key_actions; ok {
        // TODO: log that key is already registered
        fmt.eprintln("key already registered with single action", key);
    }

    input_map.key_actions[key] = Action {
        action = action,
        description = description,
    };
}

register_key_action_group :: proc(input_map: ^InputMap, key: plugin.Key, input_group: InputGroup, description: string = "") {
    if ok := key in input_map.key_actions; ok {
        // TODO: log that key is already registered
        fmt.eprintln("key already registered with single action", key);
    }

    input_map.key_actions[key] = Action {
        action = input_group,
        description = description,
    };
}

register_ctrl_key_action_single :: proc(input_map: ^InputMap, key: plugin.Key, action: EditorAction, description: string = "") {
    if ok := key in input_map.key_actions; ok {
        // TODO: log that key is already registered
        fmt.eprintln("key already registered with single action", key);
    }

    input_map.ctrl_key_actions[key] = Action {
        action = action,
        description = description,
    };
}

register_ctrl_key_action_group :: proc(input_map: ^InputMap, key: plugin.Key, input_group: InputGroup, description: string = "") {
    if ok := key in input_map.key_actions; ok {
        // TODO: log that key is already registered
        fmt.eprintln("key already registered with single action", key);
    }

    input_map.ctrl_key_actions[key] = Action {
        action = input_group,
        description = description,
    };
}

register_key_action :: proc{register_plugin_key_action_single, register_key_action_single, register_key_action_group};
register_ctrl_key_action :: proc{register_ctrl_key_action_single, register_ctrl_key_action_group};
