package core

import "core:fmt"
import "vendor:raylib"

Mode :: enum {
    Normal,
    Insert,
}

State :: struct {
    mode: Mode,
    should_close: bool,
    screen_height: i32,
    screen_width: i32,
    font: raylib.Font,

    current_buffer: int,
    buffers: [dynamic]FileBuffer,

    // TODO: replace this with generic pointer to floating window
    buffer_list_window_is_visible: bool,
    buffer_list_window_selected_buffer: int,
    buffer_list_window_input_map: InputMap, 

    input_map: InputMap,
    current_input_map: ^InputMap,
}

EditorAction :: proc(state: ^State);
InputGroup :: union {EditorAction, InputMap}
Action :: struct {
    action: InputGroup,
    description: string,
}
InputMap :: struct {
    key_actions: map[raylib.KeyboardKey]Action,
    ctrl_key_actions: map[raylib.KeyboardKey]Action,
}

new_input_map :: proc() -> InputMap {
    input_map := InputMap {
        key_actions = make(map[raylib.KeyboardKey]Action),
        ctrl_key_actions = make(map[raylib.KeyboardKey]Action),
    }

    return input_map;
}

// NOTE(pcleavelin): might be a bug in the compiler where it can't coerce
// `EditorAction` to `InputGroup` when given as a proc parameter, that is why there
// are two functions
register_key_action_single :: proc(input_map: ^InputMap, key: raylib.KeyboardKey, action: EditorAction, description: string = "") {
    if ok := key in input_map.key_actions; ok {
        // TODO: log that key is already registered
        fmt.eprintln("key already registered with single action", key);
    }

    input_map.key_actions[key] = Action {
        action = action,
        description = description,
    };
}

register_key_action_group :: proc(input_map: ^InputMap, key: raylib.KeyboardKey, input_group: InputGroup, description: string = "") {
    if ok := key in input_map.key_actions; ok {
        // TODO: log that key is already registered
        fmt.eprintln("key already registered with single action", key);
    }

    input_map.key_actions[key] = Action {
        action = input_group,
        description = description,
    };
}

register_ctrl_key_action_single :: proc(input_map: ^InputMap, key: raylib.KeyboardKey, action: EditorAction, description: string = "") {
    if ok := key in input_map.key_actions; ok {
        // TODO: log that key is already registered
        fmt.eprintln("key already registered with single action", key);
    }

    input_map.ctrl_key_actions[key] = Action {
        action = action,
        description = description,
    };
}

register_ctrl_key_action_group :: proc(input_map: ^InputMap, key: raylib.KeyboardKey, input_group: InputGroup, description: string = "") {
    if ok := key in input_map.key_actions; ok {
        // TODO: log that key is already registered
        fmt.eprintln("key already registered with single action", key);
    }

    input_map.ctrl_key_actions[key] = Action {
        action = input_group,
        description = description,
    };
}

register_key_action :: proc{register_key_action_single, register_key_action_group};
register_ctrl_key_action :: proc{register_ctrl_key_action_single, register_ctrl_key_action_group};
