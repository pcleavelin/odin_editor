package panels

import "base:runtime"
import "core:mem"
import "core:fmt"
import "core:strings"
import "core:log"

import "vendor:sdl2"

import "../core"
import "../util"
import "../ui"

make_debug_panel :: proc() -> core.Panel {
    return core.Panel {
        type = core.DebugPanel {},
        create = proc(panel: ^core.Panel, state: ^core.State) {
            context.allocator = panel.allocator

            panel_state := &panel.type.(core.DebugPanel)
            panel.input_map = core.new_input_map(show_help = true)

            panel_actions := core.new_input_actions(show_help = true)
            register_default_panel_actions(&panel_actions)
            core.register_ctrl_key_action(&panel.input_map.mode[.Normal], .W, panel_actions, "Panel Navigation") 
        },
        render = proc(panel: ^core.Panel, state: ^core.State) -> (ok: bool) {
            if panel_state, ok := &panel.type.(core.DebugPanel); ok {
                s := transmute(^ui.State)state.ui

                ui.open_element(s, nil,
                    {
                        dir = .TopToBottom,
                        kind = {ui.Fit{}, ui.Grow{}},
                    },
                    style = {
                        background_color = .Background1,
                    },
                )
                {
                    render_buffer_list(state, s)

                    ui.open_element(s, nil, {
                        kind = {ui.Fit{}, ui.Exact(8)},
                    })
                    ui.close_element(s)

                    render_panel_list(state, s)
                }
                ui.close_element(s)
            }

            return true
        }
    }
}

render_buffer_list :: proc(state: ^core.State, s: ^ui.State) {
    ui.open_element(s, nil,
        {
            dir = .TopToBottom,
            kind = {ui.Fit{}, ui.Fit{}},
        },
        style = {
            background_color = .Background1,
        },
    )
    {
        ui.open_element(s, "Open Buffers", 
            {
                kind = {ui.Grow{}, ui.Fit{}},
            },
            style = {
                border = {.Bottom},
                border_color = .Background4,
            }
        )
        ui.close_element(s)

        ui.open_element(s, nil, {
            kind = {ui.Fit{}, ui.Exact(8)},
        })
        ui.close_element(s)

        for i in 0..<len(state.buffers.data) {
            if buffer, ok := util.get(&state.buffers, i).?; ok {
                buffer_label := fmt.tprintf("buf '%v' - %v", i, buffer.file_path[len(state.directory):])
                ui.open_element(s, buffer_label, {})
                ui.close_element(s)
            }
        }
    }
    ui.close_element(s)
}

render_panel_list :: proc(state: ^core.State, s: ^ui.State) {
    ui.open_element(s, nil,
        {
            dir = .TopToBottom,
            kind = {ui.Fit{}, ui.Fit{}},
        },
        style = {
            background_color = .Background1,
        },
    )
    {
        ui.open_element(s, "Open Panels", 
            {
                kind = {ui.Grow{}, ui.Fit{}},
            },
            style = {
                border = {.Bottom},
                border_color = .Background4,
            }
        )
        ui.close_element(s)

        ui.open_element(s, nil, {
            kind = {ui.Fit{}, ui.Exact(8)},
        })
        ui.close_element(s)

        for i in 0..<len(state.panels.data) {
            if panel, ok := util.get(&state.panels, i).?; ok {
                info: string
                switch v in &panel.type {
                    case core.DebugPanel:      info = "DebugPanel"
                    case core.FileBufferPanel: info = "FileBufferPanel"
                    case core.GrepPanel:       info = "GrepPanel"
                }

                panel_label := fmt.tprintf("panel id '%v' - %v", i, info)
                ui.open_element(s, panel_label, {})
                ui.close_element(s)
            }
        }
    }
    ui.close_element(s)
}