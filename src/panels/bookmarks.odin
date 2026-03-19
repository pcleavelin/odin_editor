package panels

import "core:strings"

import "vendor:sdl2"

import ts "../tree_sitter"
import "../core"
import "../ui"

BookmarksPanelMode :: enum { Browse, CreatingList, RenamingList }

BookmarksPanel :: struct {
    picker:           BookmarkListPicker,
    mode:             BookmarksPanelMode,
    name_buffer:      core.FileBuffer,
    preview_buffer:   core.FileBuffer,
    preview_file_path: string,
}

open_bookmarks_panel :: proc(state: ^core.State) {
    open(state, make_bookmarks_panel())
}

make_bookmarks_panel :: proc() -> core.Panel {
    return core.Panel {
        is_floating = false,
        name = proc(panel: ^core.Panel) -> string {
            return "BookmarksPanel"
        },
        drop = proc(panel: ^core.Panel, state: ^core.State) {
            panel_state := transmute(^BookmarksPanel)panel.state
            ts.delete_state(&panel_state.name_buffer.tree)
            ts.delete_state(&panel_state.preview_buffer.tree)
        },
        create = proc(panel: ^core.Panel, state: ^core.State, data: rawptr) {
            context.allocator = panel.allocator

            panel.state = transmute(core.PanelState)new(BookmarksPanel)
            panel_state := transmute(^BookmarksPanel)panel.state
            panel_state^ = BookmarksPanel{}

            panel_state.name_buffer    = core.new_virtual_file_buffer(panel.allocator)
            panel_state.preview_buffer = core.new_virtual_file_buffer(panel.allocator)

            panel.input_map = core.new_input_map(show_help = true)

            panel_actions := core.new_input_actions(show_help = true)
            register_default_panel_actions(&panel_actions)
            core.register_ctrl_key_action(&panel.input_map.mode[.Normal], .W, panel_actions, "Panel Navigation")

            core.register_key_action(&panel.input_map.mode[.Normal], .J, proc(state: ^core.State, user_data: rawptr) {
                panel := transmute(^core.Panel)user_data
                panel_state := transmute(^BookmarksPanel)panel.state
                picker := &panel_state.picker

                switch picker.view {
                case .Lists:
                    if picker.selected_list < bookmark_active_list_count(&state.bookmarks) - 1 {
                        picker.selected_list += 1
                    }
                case .Entries:
                    if list, ok := bookmark_get_active_list(&state.bookmarks, picker.selected_list); ok {
                        if picker.selected_entry < len(list.bookmarks) - 1 {
                            picker.selected_entry += 1
                            update_bookmark_preview(panel_state, state)
                        }
                    }
                }
            }, "move down")

            core.register_key_action(&panel.input_map.mode[.Normal], .K, proc(state: ^core.State, user_data: rawptr) {
                panel := transmute(^core.Panel)user_data
                panel_state := transmute(^BookmarksPanel)panel.state
                picker := &panel_state.picker

                switch picker.view {
                case .Lists:
                    if picker.selected_list > 0 {
                        picker.selected_list -= 1
                    }
                case .Entries:
                    if picker.selected_entry > 0 {
                        picker.selected_entry -= 1
                        update_bookmark_preview(panel_state, state)
                    }
                }
            }, "move up")

            core.register_key_action(&panel.input_map.mode[.Normal], .ENTER, proc(state: ^core.State, user_data: rawptr) {
                panel := transmute(^core.Panel)user_data
                panel_state := transmute(^BookmarksPanel)panel.state
                picker := &panel_state.picker

                switch picker.view {
                case .Lists:
                    if _, ok := bookmark_get_active_list(&state.bookmarks, picker.selected_list); ok {
                        picker.view = .Entries
                        picker.selected_entry = 0
                        update_bookmark_preview(panel_state, state)
                    }
                case .Entries:
                    if list, ok := bookmark_get_active_list(&state.bookmarks, picker.selected_list); ok {
                        if picker.selected_entry < len(list.bookmarks) {
                            bookmark := &list.bookmarks[picker.selected_entry]
                            core.open_buffer_file(state, bookmark.file_path, bookmark.line, bookmark.col)
                            close(state, panel.id)
                        }
                    }
                }
            }, "open / drill in")

            core.register_key_action(&panel.input_map.mode[.Normal], .U, proc(state: ^core.State, user_data: rawptr) {
                panel := transmute(^core.Panel)user_data
                panel_state := transmute(^BookmarksPanel)panel.state
                if panel_state.picker.view == .Entries {
                    panel_state.picker.view = .Lists
                }
            }, "back to lists")

            core.register_key_action(&panel.input_map.mode[.Normal], .N, proc(state: ^core.State, user_data: rawptr) {
                panel := transmute(^core.Panel)user_data
                panel_state := transmute(^BookmarksPanel)panel.state

                core.clear_file_buffer(&panel_state.name_buffer)
                panel_state.mode = .CreatingList
                state.mode = .Insert
                sdl2.StartTextInput()
                core.reset_input_map(state)
            }, "new list")

            core.register_key_action(&panel.input_map.mode[.Normal], .R, proc(state: ^core.State, user_data: rawptr) {
                panel := transmute(^core.Panel)user_data
                panel_state := transmute(^BookmarksPanel)panel.state

                if list, ok := bookmark_get_active_list(&state.bookmarks, panel_state.picker.selected_list); ok {
                    core.clear_file_buffer(&panel_state.name_buffer)
                    core.insert_content(&panel_state.name_buffer, transmute([]u8)list.name)
                    panel_state.mode = .RenamingList
                    state.mode = .Insert
                    sdl2.StartTextInput()
                    core.reset_input_map(state)
                }
            }, "rename list")

            core.register_key_action(&panel.input_map.mode[.Normal], .C, proc(state: ^core.State, user_data: rawptr) {
                panel := transmute(^core.Panel)user_data
                panel_state := transmute(^BookmarksPanel)panel.state
                if panel_state.picker.view == .Lists {
                    if list, ok := bookmark_get_active_list(&state.bookmarks, panel_state.picker.selected_list); ok {
                        state.bookmarks.current_list_id = list.id
                    }
                }
            }, "set as current list")

            core.register_key_action(&panel.input_map.mode[.Normal], .D, proc(state: ^core.State, user_data: rawptr) {
                panel := transmute(^core.Panel)user_data
                panel_state := transmute(^BookmarksPanel)panel.state
                picker := &panel_state.picker

                switch picker.view {
                case .Lists:
                    if list, ok := bookmark_get_active_list(&state.bookmarks, picker.selected_list); ok {
                        was_current := list.id == state.bookmarks.current_list_id
                        core.bookmark_delete_list(&state.bookmarks, list.id)
                        active_count := bookmark_active_list_count(&state.bookmarks)
                        if picker.selected_list >= active_count && picker.selected_list > 0 {
                            picker.selected_list -= 1
                        }
                        if was_current {
                            if next, ok := bookmark_get_active_list(&state.bookmarks, picker.selected_list); ok {
                                state.bookmarks.current_list_id = next.id
                            } else {
                                state.bookmarks.current_list_id = -1
                            }
                        }
                    }
                case .Entries:
                    if list, ok := bookmark_get_active_list(&state.bookmarks, picker.selected_list); ok {
                        core.bookmark_remove(&state.bookmarks, list.id, picker.selected_entry)
                        if picker.selected_entry >= len(list.bookmarks) && picker.selected_entry > 0 {
                            picker.selected_entry -= 1
                        }
                    }
                }
            }, "delete")

            core.register_key_action(&panel.input_map.mode[.Normal], .ESCAPE, proc(state: ^core.State, user_data: rawptr) {
                panel := transmute(^core.Panel)user_data
                panel_state := transmute(^BookmarksPanel)panel.state

                if panel_state.picker.view == .Entries {
                    panel_state.picker.view = .Lists
                } else {
                    close(state, panel.id)
                }
            }, "back / close")

            core.register_key_action(&panel.input_map.mode[.Insert], .ESCAPE, proc(state: ^core.State, user_data: rawptr) {
                panel := transmute(^core.Panel)user_data
                panel_state := transmute(^BookmarksPanel)panel.state

                panel_state.mode = .Browse
                state.mode = .Normal
                sdl2.StopTextInput()
                core.reset_input_map(state)
            }, "cancel")
        },
        buffer = proc(panel: ^core.Panel, state: ^core.State) -> (buffer: ^core.FileBuffer, ok: bool) {
            panel_state := transmute(^BookmarksPanel)panel.state
            if panel_state.mode == .CreatingList || panel_state.mode == .RenamingList {
                return &panel_state.name_buffer, true
            }
            return nil, false
        },
        on_buffer_input = proc(panel: ^core.Panel, state: ^core.State) {
            panel_state := transmute(^BookmarksPanel)panel.state

            name_str := core.buffer_to_string(&panel_state.name_buffer, allocator = context.temp_allocator)
            if len(name_str) > 0 && name_str[len(name_str)-1] == '\n' {
                name := strings.trim_right(name_str, "\n")

                switch panel_state.mode {
                case .CreatingList:
                    if len(name) > 0 {
                        core.bookmark_create_list(&state.bookmarks, name)
                        panel_state.picker.selected_list = bookmark_active_list_count(&state.bookmarks) - 1
                    }
                case .RenamingList:
                    if list, ok := bookmark_get_active_list(&state.bookmarks, panel_state.picker.selected_list); ok && len(name) > 0 {
                        core.bookmark_rename_list(&state.bookmarks, list.id, name)
                    }
                case .Browse:
                }

                panel_state.mode = .Browse
                state.mode = .Normal
                sdl2.StopTextInput()
                core.reset_input_map(state)
            }
        },
        render = proc(panel: ^core.Panel, state: ^core.State) -> (ok: bool) {
            panel_state := transmute(^BookmarksPanel)panel.state
            s := transmute(^ui.State)state.ui

            ui.open_element(s, nil,
                {
                    dir  = .TopToBottom,
                    kind = {ui.Grow{}, ui.Grow{}},
                },
                style = {background_color = .Background1},
            )
            {
                // Title
                ui.open_element(s, "Bookmarks",
                    {kind = {ui.Grow{}, ui.Fit{}}},
                    style = {border = {.Bottom}, border_color = .Background4},
                )
                ui.close_element(s)

                // Name input (when creating or renaming)
                if panel_state.mode == .CreatingList || panel_state.mode == .RenamingList {
                    label := "New list name:" if panel_state.mode == .CreatingList else "Rename list:"
                    ui.open_element(s, label, {})
                    ui.close_element(s)
                    render_raw_buffer(state, s, &panel_state.name_buffer)
                }

                ui.open_element(s, nil, {dir = .LeftToRight, kind = {ui.Grow{}, ui.Grow{}}})
                {
                    ui.open_element(s, nil,
                        {dir = .TopToBottom, kind = {ui.Grow{}, ui.Grow{}}},
                        style = {border = {.Right}, border_color = .Background4},
                    )
                    {
                        render_bookmark_list_picker(state, s, &panel_state.picker, &state.bookmarks)
                    }
                    ui.close_element(s)

                    if panel_state.picker.view == .Entries {
                        render_raw_buffer(state, s, &panel_state.preview_buffer)
                    }
                }
                ui.close_element(s)
            }
            ui.close_element(s)

            return true
        },
    }
}

update_bookmark_preview :: proc(panel_state: ^BookmarksPanel, state: ^core.State) {
    if panel_state.picker.view != .Entries { return }
    list, ok := bookmark_get_active_list(&state.bookmarks, panel_state.picker.selected_list)
    if !ok || len(list.bookmarks) == 0 { return }
    bookmark := &list.bookmarks[panel_state.picker.selected_entry]
    if bookmark.file_path != panel_state.preview_file_path {
        core.reload_file_into_buffer(&panel_state.preview_buffer, bookmark.file_path, state.directory)
        panel_state.preview_file_path = bookmark.file_path
    }
    core.move_cursor_to_location(&panel_state.preview_buffer, bookmark.line, bookmark.col)
}

bookmark_get_active_list :: proc(bookmarks: ^core.Bookmarks, visual_index: int) -> (list: ^core.BookmarkList, ok: bool) {
    count := 0
    for i in 0..<len(bookmarks.lists.data) {
        if bookmarks.lists.data[i].active {
            if count == visual_index {
                return &bookmarks.lists.data[i].data, true
            }
            count += 1
        }
    }
    return nil, false
}

bookmark_active_list_count :: proc(bookmarks: ^core.Bookmarks) -> int {
    count := 0
    for i in 0..<len(bookmarks.lists.data) {
        if bookmarks.lists.data[i].active {
            count += 1
        }
    }
    return count
}
