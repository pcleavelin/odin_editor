package panels

import "core:fmt"

import "../core"
import "../ui"

BookmarkPickerView :: enum { Lists, Entries }

BookmarkListPicker :: struct {
    view:           BookmarkPickerView,
    selected_list:  int,
    list_scroll:    int,
    selected_entry: int,
    entry_scroll:   int,
}

render_bookmark_list_picker :: proc(state: ^core.State, s: ^ui.State, picker: ^BookmarkListPicker, bookmarks: ^core.Bookmarks) {
    ListState :: struct {
        core_state: ^core.State,
        bookmarks:  ^core.Bookmarks,
        picker:     ^BookmarkListPicker,
    }
    list_state := ListState{
        core_state = state,
        bookmarks  = bookmarks,
        picker     = picker,
    }

    switch picker.view {
    case .Lists:
        active_lists := make([dynamic]^core.BookmarkList, context.temp_allocator)
        for i in 0..<len(bookmarks.lists.data) {
            if bookmarks.lists.data[i].active {
                append(&active_lists, &bookmarks.lists.data[i].data)
            }
        }

        ui.list(
            ^core.BookmarkList,
            s,
            active_lists[:],
            &list_state,
            &picker.selected_list,
            &picker.list_scroll,
            proc(s: ^ui.State, item: rawptr, state: rawptr) {
                list := (transmute(^^core.BookmarkList)item)^
                list_state := transmute(^ListState)state
                is_current := list.id == list_state.bookmarks.current_list_id
                marker := "*" if is_current else " "
                ui.open_element(s, fmt.tprintf("%v %v (%v)", marker, list.name, len(list.bookmarks)), {kind = {ui.Grow{}, ui.Fit{}}})
                ui.close_element(s)
            },
        )

    case .Entries:
        list, ok := bookmark_get_active_list(bookmarks, picker.selected_list)
        if !ok { return }

        ui.list(
            core.Bookmark,
            s,
            list.bookmarks[:],
            &list_state,
            &picker.selected_entry,
            &picker.entry_scroll,
            proc(s: ^ui.State, item: rawptr, state: rawptr) {
                bookmark := transmute(^core.Bookmark)item
                list_state := transmute(^ListState)state
                path := bookmark.file_path
                if len(path) > len(list_state.core_state.directory) {
                    path = path[len(list_state.core_state.directory):]
                }
                label := fmt.tprintf("%v:%v %v", bookmark.line+1, bookmark.col+1, path)
                if len(bookmark.label) > 0 {
                    label = fmt.tprintf("%v:%v %v - %v", bookmark.line+1, bookmark.col+1, path, bookmark.label)
                }
                ui.open_element(s, label, {kind = {ui.Grow{}, ui.Fit{}}})
                ui.close_element(s)
            },
        )
    }
}
