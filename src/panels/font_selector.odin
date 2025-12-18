package panels

import "base:runtime"
import "core:fmt"
import "core:strings"
import "core:slice"

import "../core"
import "../ui"

FontSelectorPanel :: struct {
    selected_item: int,
    items_start: int,
    items: []core.SystemFont,
}

make_font_selector_panel :: proc() -> core.Panel {
    return core.Panel {
        is_floating = true,
        name = proc(panel: ^core.Panel) -> string {
            return "FontSelectorPanel"
        },
        drop = proc(panel: ^core.Panel, state: ^core.State) {
        },
        create = proc(panel: ^core.Panel, state: ^core.State, data: rawptr) {
            context.allocator = panel.allocator

            panel.state = transmute(core.PanelState)new(FontSelectorPanel)
            panel_state := transmute(^FontSelectorPanel)panel.state
            panel_state^ = FontSelectorPanel {}

            panel.input_map = core.new_input_map(show_help = true)

            panel_state.items = core.load_system_font_list(allocator = panel.allocator)

            core.register_key_action(&panel.input_map.mode[.Normal], .K, proc(state: ^core.State, user_data: rawptr) {
                this_panel := transmute(^core.Panel)user_data
                panel_state := transmute(^FontSelectorPanel)this_panel.state

                if panel_state.selected_item > 0 {
                    panel_state.selected_item -= 1
                }

            }, "move selection up");

            core.register_key_action(&panel.input_map.mode[.Normal], .J, proc(state: ^core.State, user_data: rawptr) {
                this_panel := transmute(^core.Panel)user_data
                panel_state := transmute(^FontSelectorPanel)this_panel.state

                // FIXME
                if panel_state.selected_item < 99999 {
                    panel_state.selected_item += 1
                }

            }, "move selection down");

            core.register_key_action(&panel.input_map.mode[.Normal], .ENTER, proc(state: ^core.State, user_data: rawptr) {
                this_panel := transmute(^core.Panel)user_data
                panel_state := transmute(^FontSelectorPanel)this_panel.state

                file_path := panel_state.items[panel_state.selected_item].file_path
                fmt.println(file_path)

                state.font_atlas = core.gen_font_atlas(state, file_path)

                close(state, this_panel.id)
            }, "set font");
            core.register_key_action(&panel.input_map.mode[.Normal], .ESCAPE, proc(state: ^core.State, user_data: rawptr) {
                this_panel := transmute(^core.Panel)user_data
                close(state, this_panel.id)
            }, "close panel");
        },
        render = proc(panel: ^core.Panel, state: ^core.State) -> (ok: bool) {
            context.allocator = panel.allocator

            panel_state := transmute(^FontSelectorPanel )panel.state
            s := transmute(^ui.State)state.ui

            ListState :: struct {
                core_state: ^core.State,
                panel_state: ^FontSelectorPanel,
            }
            list_state := ListState {
                core_state = state,
                panel_state = panel_state
            }

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
                        ui.list(core.SystemFont, s, panel_state.items, &list_state, &panel_state.selected_item, &panel_state.items_start, proc(s: ^ui.State, item: rawptr, state: rawptr) {
                            item := transmute(^core.SystemFont)item
                            list_state := transmute(^ListState)state
                            state := list_state.core_state

                            ui.left_to_right(s)
                            {
                                ui.spacer(s, state.source_font_width)
                                ui.top_to_bottom(s)
                                {
                                    ui.open_element(s, item.display_name, {})
                                    ui.close_element(s)
                                }
                                ui.close_element(s)
                                ui.spacer(s, state.source_font_width)
                            }
                            ui.close_element(s)
                        })
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
