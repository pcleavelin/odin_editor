package panels

import "base:runtime"
import "core:fmt"
import "core:strings"
import "core:slice"

import "vendor:sdl2"

import "../core"
import "../ui"

CommandPalettePanel :: struct {
    buffer: core.FileBuffer,
    items: []CommandPaletteItem,
    selected_item: int,
    items_start: int,
}

CommandPaletteItem :: struct {
    id: int,
    sort_id: int,
    group: string,
    name: string,
    description: string,
    action: core.EditorAction,
}

make_cmd_palette_panel :: proc() -> core.Panel {
    return core.Panel {
        is_floating = true,
        name = proc(panel: ^core.Panel) -> string {
            return "CommandPalettePanel"
        },
        drop = proc(panel: ^core.Panel, state: ^core.State) {
        },
        create = proc(panel: ^core.Panel, state: ^core.State, data: rawptr) {
            context.allocator = panel.allocator

            panel.state = transmute(core.PanelState)new(CommandPalettePanel)
            panel_state := transmute(^CommandPalettePanel)panel.state
            panel_state^ = CommandPalettePanel {}

            panel.input_map = core.new_input_map(show_help = true)
            panel_state.buffer = core.new_virtual_file_buffer()

            num_commands := 0
            for group, cmds in state.commands {
                num_commands += len(cmds)
            }

            num_items := 0
            panel_state.items = make([]CommandPaletteItem, num_commands)
            for group, cmds in state.commands {
                for cmd in cmds {
                    panel_state.items[num_items] = CommandPaletteItem {
                        id = num_items,
                        sort_id = num_items,
                        group = group,
                        name = cmd.name,
                        description = cmd.description, 
                        action = cmd.action,
                    }

                    num_items += 1
                }
            }

            core.register_key_action(&panel.input_map.mode[.Normal], .K, proc(state: ^core.State, user_data: rawptr) {
                this_panel := transmute(^core.Panel)user_data
                panel_state := transmute(^CommandPalettePanel)this_panel.state

                if panel_state.selected_item > 0 {
                    panel_state.selected_item -= 1
                }

            }, "move selection up");

            core.register_key_action(&panel.input_map.mode[.Normal], .J, proc(state: ^core.State, user_data: rawptr) {
                this_panel := transmute(^core.Panel)user_data
                panel_state := transmute(^CommandPalettePanel)this_panel.state

                // FIXME
                if panel_state.selected_item < 99999 {
                    panel_state.selected_item += 1
                }

            }, "move selection down");

            core.register_key_action(&panel.input_map.mode[.Normal], .ENTER, proc(state: ^core.State, user_data: rawptr) {
                this_panel := transmute(^core.Panel)user_data
                panel_state := transmute(^CommandPalettePanel)this_panel.state

                if panel_state.items != nil {
                    item := &panel_state.items[panel_state.selected_item]

                    close(state, this_panel.id)

                    if item.action != nil {
                        item.action(state, nil)
                    }
                }

            }, "Run Command");
            core.register_key_action(&panel.input_map.mode[.Insert], .ESCAPE, proc(state: ^core.State, user_data: rawptr) {
                state.mode = .Normal;
                sdl2.StopTextInput();
            }, "exit insert mode");
            core.register_key_action(&panel.input_map.mode[.Normal], .ESCAPE, proc(state: ^core.State, user_data: rawptr) {
                this_panel := transmute(^core.Panel)user_data
                close(state, this_panel.id)
            }, "close panel");
        },
        buffer = proc(panel: ^core.Panel, state: ^core.State) -> (buffer: ^core.FileBuffer, ok: bool) {
            panel_state := transmute(^CommandPalettePanel )panel.state

            return &panel_state.buffer, true
        },
        on_buffer_input = proc(panel: ^core.Panel, state: ^core.State) {
            panel_state := transmute(^CommandPalettePanel)panel.state

            input_str := core.buffer_to_string(&panel_state.buffer, allocator = context.temp_allocator)

            // really janky and barely working fuzzy search
            // it *attempts* to find the closest set of consecutive letters
            // with each letter in between them adding to the total distance
            //
            // one problem is that it is biased towards the first letter from the needle
            // it find in the haystack
            for &item in panel_state.items {
                haystack_index := 0
                dist := 0
                for needle in input_str {
                    for haystack, i in item.name[haystack_index:] {
                        if haystack == needle {
                            dist += i
                            haystack_index = haystack_index + i+1
                            break
                        }
                    }
                }

                item.sort_id = dist
            }

            slice.sort_by(panel_state.items, proc(a,b: CommandPaletteItem) -> bool {
                return a.sort_id < b.sort_id
            })
        },
        render = proc(panel: ^core.Panel, state: ^core.State) -> (ok: bool) {
            context.allocator = panel.allocator

            panel_state := transmute(^CommandPalettePanel )panel.state
            s := transmute(^ui.State)state.ui

            ui.open_element(s, nil,
                {
                    dir = .LeftToRight,
                    kind = {ui.Grow{}, ui.Grow{}},
                    floating = true,
                },
            )
            {
                ui.centered(s)
                {
                    ui.open_element(s, nil,
                        {
                            dir = .TopToBottom,
                            kind = {ui.Exact(state.screen_width - state.screen_width/4), ui.Grow{}},
                        },
                        style = {
                            border = {.Left, .Right, .Top, .Bottom},
                            border_color = .Background4,
                            background_color = .Background1,
                        }
                    )
                    {
                        render_palette_input(state, s, panel_state)
                        render_command_list(state, s, panel_state)
                    }
                    ui.close_element(s)
                }
                ui.close_centered(s)
            }
            ui.close_element(s)

            return true
        },
    }
}

@(private)
render_palette_input :: proc(state: ^core.State, s: ^ui.State, panel_state: ^CommandPalettePanel) {
    input := core.buffer_to_string(&panel_state.buffer, context.temp_allocator)
    input_width := len(input) * state.source_font_width

    ui.open_element(s, nil,
        {
            dir = .LeftToRight,
            kind = {ui.Grow{}, ui.Exact(state.source_font_height*2)},
        },
        style = {
            border = {.Left, .Right, .Top, .Bottom},
            border_color = .Background4,
            background_color = .Background2, 
        },
    )
    {
        ui.centered_top_to_bottom(s)
        {
            ui.left_to_right(s)
            {
                ui.spacer(s, state.source_font_width)
                render_input_buffer(state, s, &panel_state.buffer, input_width)  
            }
            ui.close_element(s)
        }
        ui.close_centered_top_to_bottom(s)
    }
    ui.close_element(s)
}

@(private)
render_command_list :: proc(state: ^core.State, s: ^ui.State, panel_state: ^CommandPalettePanel) {

    ListState :: struct {
        core_state: ^core.State,
        panel_state: ^CommandPalettePanel,
    }
    list_state := ListState {
        core_state = state,
        panel_state = panel_state
    }

    render_item :: proc(s: ^ui.State, item: rawptr, state: rawptr) {
        item := transmute(^CommandPaletteItem)item
        list_state := transmute(^ListState)state
        state := list_state.core_state

        ui.left_to_right(s)
        {
            ui.spacer(s, state.source_font_width)
            ui.top_to_bottom(s)
            {
                ui.open_element(s, item.name, {})
                ui.close_element(s)

                if len(item.description) > 0 {
                    ui.open_element(s, fmt.tprintf("%v - dist: %v", item.description, item.sort_id), {})
                    ui.close_element(s)
                }
            }
            ui.close_element(s)
            ui.spacer(s, state.source_font_width)
        }
        ui.close_element(s)
    }

    ui.list(CommandPaletteItem, s, panel_state.items, &list_state, &panel_state.selected_item, &panel_state.items_start, render_item)
}

@(private)
render_input_buffer :: proc(state: ^core.State, s: ^ui.State, buffer: ^core.FileBuffer, width: int) {
    draw_func := proc(state: ^core.State, e: ui.UI_Element, user_data: rawptr) {
        buffer := transmute(^core.FileBuffer)user_data;
        if buffer != nil {
            core.draw_file_buffer(state, buffer, e.layout.pos.x, e.layout.pos.y, e.layout.size.x, e.layout.size.y, false);
        }
    };

    ui.open_element(s, ui.UI_Element_Kind_Custom{fn = draw_func, user_data = transmute(rawptr)buffer}, {
        kind = {ui.Exact(width), ui.Exact(state.source_font_height)}
    })
    ui.close_element(s)

}

