package core

import "core:mem"
import "core:strings"

import "../util"

init_bookmarks :: proc(bookmarks: ^Bookmarks, allocator := context.allocator) {
    bookmarks.allocator       = allocator
    bookmarks.lists           = util.make_static_list(BookmarkList, 64)
    bookmarks.current_list_id = -1
}

bookmark_create_list :: proc(bookmarks: ^Bookmarks, name: string) -> BookmarkListId {
    id, item, ok := util.append(&bookmarks.lists, BookmarkList {})
    if !ok {
        return -1
    }

    arena_bytes := make([]u8, 1024*1024, bookmarks.allocator)
    mem.arena_init(&item.arena, arena_bytes)

    item.allocator = mem.arena_allocator(&item.arena)

    item.name      = strings.clone(name, item.allocator)
    item.bookmarks = make([dynamic]Bookmark, item.allocator)

    item.id = BookmarkListId(id)
    if bookmarks.current_list_id == -1 {
        bookmarks.current_list_id = item.id
    }
    return item.id
}

bookmark_rename_list :: proc(bookmarks: ^Bookmarks, id: BookmarkListId, new_name: string) {
    list, ok := bookmark_get_list(bookmarks, id)
    if !ok { return }
    list.name = strings.clone(new_name, list.allocator)
}

bookmark_delete_list :: proc(bookmarks: ^Bookmarks, id: BookmarkListId) {
    list, ok := bookmark_get_list(bookmarks, id)
    if !ok { return }

    // FIXME: as this is an arena allocator the `free` is a no-op, maybe
    // change this to clearing the arena and keeping all the arenas of each
    // bookmark list around
    mem.free(raw_data(list.arena.data), bookmarks.allocator)
    util.delete(&bookmarks.lists, int(id))
}

bookmark_add :: proc(bookmarks: ^Bookmarks, list_id: BookmarkListId, file_path: string, line, col: int, label: string = "") -> bool {
    list, ok := bookmark_get_list(bookmarks, list_id)
    if !ok { return false }

    append(&list.bookmarks, Bookmark {
        file_path = strings.clone(file_path, list.allocator),
        line      = line,
        col       = col,
        label     = strings.clone(label, list.allocator),
    })

    return true
}

bookmark_remove :: proc(bookmarks: ^Bookmarks, list_id: BookmarkListId, index: int) {
    list, ok := bookmark_get_list(bookmarks, list_id)
    if !ok { return }
    if index >= 0 && index < len(list.bookmarks) {
        ordered_remove(&list.bookmarks, index)
    }
}

bookmark_get_list :: proc(bookmarks: ^Bookmarks, id: BookmarkListId) -> (list: ^BookmarkList, ok: bool) {
    result, got := util.get(&bookmarks.lists, int(id)).?
    if !got { return nil, false }
    return result, true
}
