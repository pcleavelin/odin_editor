package core

import "base:runtime"
import "base:intrinsics"
import "core:mem"
import "core:reflect"
import "core:fmt"
import "core:log"
import "vendor:sdl2"

import "../util"

HardcodedFontPath :: "bin/JetBrainsMono-Regular.ttf";

Mode :: enum {
    Normal,
    Insert,
    Visual,
}

EditorCommandList :: map[string][dynamic]EditorCommand;
State :: struct {
    ctx: runtime.Context,
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

    // TODO: make more than one register to plop stuff into
    yank_register: Register,

    log_buffer: FileBuffer,

    current_input_map: ^InputActions,

    commands: EditorCommandList,
    command_arena: runtime.Allocator,
    command_args: [dynamic]EditorCommandArgument,

    current_panel: Maybe(int),
    panels: util.StaticList(Panel),
}

Register :: struct {
    whole_line: bool,
    data: []u8,
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

Panel :: struct {
    using vtable: Panel_VTable,
    arena: mem.Arena,
    allocator: mem.Allocator,

    id: int,
    type: PanelType,
    input_map: InputMap,
    is_floating: bool,
}

Panel_VTable :: struct {
    create:          proc(panel: ^Panel, state: ^State), 
    drop:            proc(panel: ^Panel, state: ^State),

    on_buffer_input: proc(panel: ^Panel, state: ^State),
    buffer:          proc(panel: ^Panel, state: ^State) -> (buffer: ^FileBuffer, ok: bool),
    render:          proc(panel: ^Panel, state: ^State) -> (ok: bool),
}

PanelType :: union {
    FileBufferPanel,
    GrepPanel,
}

FileBufferPanel :: struct {
    buffer: FileBuffer,
    viewed_symbol: Maybe(string),

    // only used for initialization
    file_path: string,
    line, col: int,
}

GrepPanel :: struct {
    query_arena: mem.Arena,
    query_region: mem.Arena_Temp_Memory,
    buffer: FileBuffer,
    selected_result: int,
    search_query: string,
    query_results: []GrepQueryResult,
    glyphs: GlyphBuffer,
}

GrepQueryResult :: struct {
    file_context: string,
    file_path: string,
    line: int,
    col: int,
}

current_buffer :: proc(state: ^State) -> ^FileBuffer {
    if current_panel, ok := state.current_panel.?; ok {
        if panel, ok := util.get(&state.panels, current_panel).?; ok {
            buffer, _ := panel->buffer(state)
            return buffer
        }
    }

    return nil
}

yank_whole_line :: proc(state: ^State, buffer: ^FileBuffer) {
    if state.yank_register.data != nil {
        delete(state.yank_register.data)
        state.yank_register.data = nil
    }

    selection := new_selection(buffer, buffer.history.cursor)
    length := selection_length(buffer, selection)

    state.yank_register.whole_line = true
    state.yank_register.data = make([]u8, length)

    it := new_file_buffer_iter_with_cursor(buffer, selection.start)

    index := 0
    for !it.hit_end && index < length {
        state.yank_register.data[index] = get_character_at_iter(it) 

        iterate_file_buffer(&it)
        index += 1
    }
}

yank_selection :: proc(state: ^State, buffer: ^FileBuffer) {
    if state.yank_register.data != nil {
        delete(state.yank_register.data)
        state.yank_register.data = nil
    }

    selection := swap_selections(buffer.selection.?)
    length := selection_length(buffer, selection)

    state.yank_register.whole_line = false

    err: runtime.Allocator_Error
    state.yank_register.data, err = make([]u8, length)
    if err != nil {
        log.error("failed to allocate memory for yank register")
    }

    it := new_file_buffer_iter_with_cursor(buffer, selection.start)

    index := 0
    for !it.hit_end && index < length {
        state.yank_register.data[index] = get_character_at_iter(it) 

        iterate_file_buffer(&it)
        index += 1
    }
}

paste_register :: proc(state: ^State, register: Register, buffer: ^FileBuffer) {
    insert_content(buffer, register.data, reparse_buffer = true)
    move_cursor_left(buffer)
}

reset_input_map_from_state_mode :: proc(state: ^State) {
    reset_input_map_from_mode(state, state.mode)
}
reset_input_map_from_mode :: proc(state: ^State, mode: Mode) {
    if current_panel, ok := util.get(&state.panels, state.current_panel.? or_else -1).?; ok {
        state.current_input_map = &current_panel.input_map.mode[mode]
    }
}
reset_input_map :: proc{reset_input_map_from_mode, reset_input_map_from_state_mode}

InputMap :: struct {
    mode: map[Mode]InputActions,
}

InputGroup :: union {EditorAction, InputActions}
EditorAction :: proc(state: ^State, user_data: rawptr);
InputActions :: struct {
    key_actions: map[Key]Action,
    ctrl_key_actions: map[Key]Action,
    show_help: bool,
}
Action :: struct {
    action: InputGroup,
    description: string,
}

new_input_map :: proc(show_help: bool = false, allocator := context.allocator) -> InputMap {
    context.allocator = allocator

    input_map := InputMap {
        mode = make(map[Mode]InputActions),
    }

    ti := runtime.type_info_base(type_info_of(Mode));
    if v, ok := ti.variant.(runtime.Type_Info_Enum); ok {
        for i in &v.values {
            input_map.mode[cast(Mode)i] = new_input_actions();
        }
    }

    normal_actions := &input_map.mode[.Normal]
    normal_actions.show_help = show_help

    return input_map;
}

new_input_actions :: proc(show_help: bool = false, allocator := context.allocator) -> InputActions {
    context.allocator = allocator

    input_actions := InputActions {
        key_actions = make(map[Key]Action),
        ctrl_key_actions = make(map[Key]Action),
        show_help = show_help,
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

register_key_action_single :: proc(input_map: ^InputActions, key: Key, action: EditorAction, description: string = "") {
    if ok := key in input_map.key_actions; ok {
        // TODO: log that key is already registered
        log.error("key already registered with single action", key);
    }

    input_map.key_actions[key] = Action {
        action = action,
        description = description,
    };
}

register_key_action_group :: proc(input_map: ^InputActions, key: Key, input_group: InputGroup, description: string = "") {
    if ok := key in input_map.key_actions; ok {
        // TODO: log that key is already registered
        fmt.eprintln("key already registered with single action", key);
    }

    input_map.key_actions[key] = Action {
        action = input_group,
        description = description,
    };
}

register_ctrl_key_action_single :: proc(input_map: ^InputActions, key: Key, action: EditorAction, description: string = "") {
    if ok := key in input_map.ctrl_key_actions; ok {
        // TODO: log that key is already registered
        log.error("key already registered with ctrl + single action", key);
    }

    input_map.ctrl_key_actions[key] = Action {
        action = action,
        description = description,
    };
}

register_ctrl_key_action_group :: proc(input_map: ^InputActions, key: Key, input_group: InputGroup, description: string = "") {
    if ok := key in input_map.ctrl_key_actions; ok {
        // TODO: log that key is already registered
        log.error("key already registered with ctrl + single action", key);
    }

    input_map.ctrl_key_actions[key] = Action {
        action = input_group,
        description = description,
    };
}

register_key_action :: proc{register_key_action_single, register_key_action_group};
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
                // TODO: rework command system
                // cmd.action(state);
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

Key :: enum {
    UNKNOWN            = 0,
    ENTER              = 13,
    ESCAPE             = 27,
    BACKSPACE          = 8,
    TAB                = 9,
    SPACE              = 32,
    EXCLAIM            = 33,
    QUOTEDBL           = 34,
    HASH               = 35,
    PERCENT            = 37,
    DOLLAR             = 36,
    AMPERSAND          = 38,
    QUOTE              = 39,
    LEFTPAREN          = 40,
    RIGHTPAREN         = 41,
    ASTERISK           = 42,
    PLUS               = 43,
    COMMA              = 44,
    MINUS              = 45,
    PERIOD             = 46,
    SLASH              = 47,
    NUM0               = 48,
    NUM1               = 49,
    NUM2               = 50,
    NUM3               = 51,
    NUM4               = 52,
    NUM5               = 53,
    NUM6               = 54,
    NUM7               = 55,
    NUM8               = 56,
    NUM9               = 57,
    COLON              = 58,
    SEMICOLON          = 59,
    LESS               = 60,
    EQUAL              = 61,
    GREATER            = 62,
    QUESTION           = 63,
    AT                 = 64,
    LEFTBRACKET        = 91,
    BACKSLASH          = 92,
    RIGHTBRACKET       = 93,
    CARET              = 94,
    UNDERSCORE         = 95,
    BACKQUOTE          = 96,
    A                  = 97,
    B                  = 98,
    C                  = 99,
    D                  = 100,
    E                  = 101,
    F                  = 102,
    G                  = 103,
    H                  = 104,
    I                  = 105,
    J                  = 106,
    K                  = 107,
    L                  = 108,
    M                  = 109,
    N                  = 110,
    O                  = 111,
    P                  = 112,
    Q                  = 113,
    R                  = 114,
    S                  = 115,
    T                  = 116,
    U                  = 117,
    V                  = 118,
    W                  = 119,
    X                  = 120,
    Y                  = 121,
    Z                  = 122,
    CAPSLOCK           = 1073741881,
    F1                 = 1073741882,
    F2                 = 1073741883,
    F3                 = 1073741884,
    F4                 = 1073741885,
    F5                 = 1073741886,
    F6                 = 1073741887,
    F7                 = 1073741888,
    F8                 = 1073741889,
    F9                 = 1073741890,
    F10                = 1073741891,
    F11                = 1073741892,
    F12                = 1073741893,
    PRINTSCREEN        = 1073741894,
    SCROLLLOCK         = 1073741895,
    PAUSE              = 1073741896,
    INSERT             = 1073741897,
    HOME               = 1073741898,
    PAGEUP             = 1073741899,
    DELETE             = 127,
    END                = 1073741901,
    PAGEDOWN           = 1073741902,
    RIGHT              = 1073741903,
    LEFT               = 1073741904,
    DOWN               = 1073741905,
    UP                 = 1073741906,
    NUMLOCKCLEAR       = 1073741907,
    KP_DIVIDE          = 1073741908,
    KP_MULTIPLY        = 1073741909,
    KP_MINUS           = 1073741910,
    KP_PLUS            = 1073741911,
    KP_ENTER           = 1073741912,
    KP_1               = 1073741913,
    KP_2               = 1073741914,
    KP_3               = 1073741915,
    KP_4               = 1073741916,
    KP_5               = 1073741917,
    KP_6               = 1073741918,
    KP_7               = 1073741919,
    KP_8               = 1073741920,
    KP_9               = 1073741921,
    KP_0               = 1073741922,
    KP_PERIOD          = 1073741923,
    APPLICATION        = 1073741925,
    POWER              = 1073741926,
    KP_EQUALS          = 1073741927,
    F13                = 1073741928,
    F14                = 1073741929,
    F15                = 1073741930,
    F16                = 1073741931,
    F17                = 1073741932,
    F18                = 1073741933,
    F19                = 1073741934,
    F20                = 1073741935,
    F21                = 1073741936,
    F22                = 1073741937,
    F23                = 1073741938,
    F24                = 1073741939,
    EXECUTE            = 1073741940,
    HELP               = 1073741941,
    MENU               = 1073741942,
    SELECT             = 1073741943,
    STOP               = 1073741944,
    AGAIN              = 1073741945,
    UNDO               = 1073741946,
    CUT                = 1073741947,
    COPY               = 1073741948,
    PASTE              = 1073741949,
    FIND               = 1073741950,
    MUTE               = 1073741951,
    VOLUMEUP           = 1073741952,
    VOLUMEDOWN         = 1073741953,
    KP_COMMA           = 1073741957,
    KP_EQUALSAS400     = 1073741958,
    ALTERASE           = 1073741977,
    SYSREQ             = 1073741978,
    CANCEL             = 1073741979,
    CLEAR              = 1073741980,
    PRIOR              = 1073741981,
    RETURN2            = 1073741982,
    SEPARATOR          = 1073741983,
    OUT                = 1073741984,
    OPER               = 1073741985,
    CLEARAGAIN         = 1073741986,
    CRSEL              = 1073741987,
    EXSEL              = 1073741988,
    KP_00              = 1073742000,
    KP_000             = 1073742001,
    THOUSANDSSEPARATOR = 1073742002,
    DECIMALSEPARATOR   = 1073742003,
    CURRENCYUNIT       = 1073742004,
    CURRENCYSUBUNIT    = 1073742005,
    KP_LEFTPAREN       = 1073742006,
    KP_RIGHTPAREN      = 1073742007,
    KP_LEFTBRACE       = 1073742008,
    KP_RIGHTBRACE      = 1073742009,
    KP_TAB             = 1073742010,
    KP_BACKSPACE       = 1073742011,
    KP_A               = 1073742012,
    KP_B               = 1073742013,
    KP_C               = 1073742014,
    KP_D               = 1073742015,
    KP_E               = 1073742016,
    KP_F               = 1073742017,
    KP_XOR             = 1073742018,
    KP_POWER           = 1073742019,
    KP_PERCENT         = 1073742020,
    KP_LESS            = 1073742021,
    KP_GREATER         = 1073742022,
    KP_AMPERSAND       = 1073742023,
    KP_DBLAMPERSAND    = 1073742024,
    KP_VERTICALBAR     = 1073742025,
    KP_DBLVERTICALBAR  = 1073742026,
    KP_COLON           = 1073742027,
    KP_HASH            = 1073742028,
    KP_SPACE           = 1073742029,
    KP_AT              = 1073742030,
    KP_EXCLAM          = 1073742031,
    KP_MEMSTORE        = 1073742032,
    KP_MEMRECALL       = 1073742033,
    KP_MEMCLEAR        = 1073742034,
    KP_MEMADD          = 1073742035,
    KP_MEMSUBTRACT     = 1073742036,
    KP_MEMMULTIPLY     = 1073742037,
    KP_MEMDIVIDE       = 1073742038,
    KP_PLUSMINUS       = 1073742039,
    KP_CLEAR           = 1073742040,
    KP_CLEARENTRY      = 1073742041,
    KP_BINARY          = 1073742042,
    KP_OCTAL           = 1073742043,
    KP_DECIMAL         = 1073742044,
    KP_HEXADECIMAL     = 1073742045,
    LCTRL              = 1073742048,
    LSHIFT             = 1073742049,
    LALT               = 1073742050,
    LGUI               = 1073742051,
    RCTRL              = 1073742052,
    RSHIFT             = 1073742053,
    RALT               = 1073742054,
    RGUI               = 1073742055,
    MODE               = 1073742081,
    AUDIONEXT          = 1073742082,
    AUDIOPREV          = 1073742083,
    AUDIOSTOP          = 1073742084,
    AUDIOPLAY          = 1073742085,
    AUDIOMUTE          = 1073742086,
    MEDIASELECT        = 1073742087,
    WWW                = 1073742088,
    MAIL               = 1073742089,
    CALCULATOR         = 1073742090,
    COMPUTER           = 1073742091,
    AC_SEARCH          = 1073742092,
    AC_HOME            = 1073742093,
    AC_BACK            = 1073742094,
    AC_FORWARD         = 1073742095,
    AC_STOP            = 1073742096,
    AC_REFRESH         = 1073742097,
    AC_BOOKMARKS       = 1073742098,
    BRIGHTNESSDOWN     = 1073742099,
    BRIGHTNESSUP       = 1073742100,
    DISPLAYSWITCH      = 1073742101,
    KBDILLUMTOGGLE     = 1073742102,
    KBDILLUMDOWN       = 1073742103,
    KBDILLUMUP         = 1073742104,
    EJECT              = 1073742105,
    SLEEP              = 1073742106,
    APP1               = 1073742107,
    APP2               = 1073742108,
    AUDIOREWIND        = 1073742109,
    AUDIOFASTFORWARD   = 1073742110,
}
