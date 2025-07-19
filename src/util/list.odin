package util

import "base:runtime"

StaticList :: struct($T: typeid) {
    data: []StaticListSlot(T),
}

StaticListSlot :: struct($T: typeid) {
    active: bool,
    data: T,
}

append_static_list :: proc(list: ^StaticList($T), value: T) -> (id: int, item: ^T, ok: bool) {
    for i in 0..<len(list.data) {
        if !list.data[i].active {
            list.data[i].active = true 
            list.data[i].data = value

            return i, &list.data[i].data, true
        }
    }

    return
}
append :: proc{append_static_list}

make_static_list :: proc($T: typeid, len: int) -> StaticList(T) {
    list := StaticList(T) {
        data = runtime.make_slice([]StaticListSlot(T), len)
    }

    return list
}

make :: proc{make_static_list}

get_static_list_elem :: proc(list: ^StaticList($T), index: int) -> Maybe(^T) {
    if index < 0 || index >= len(list.data) {
        return nil
    }

    if list.data[index].active {
        return &list.data[index].data
    }

    return nil
}

get_first_active_index :: proc(list: ^StaticList($T)) -> Maybe(int) {
    for i in 0..<len(list.data) {
        if list.data[i].active {
            return i
        }
    }

    return nil
}

get_prev :: proc(list: ^StaticList($T), index: int) -> Maybe(int) {
    if get(list, index) != nil {
        for i := index-1; i >= 0; i -= 1 {
            if list.data[i].active {
                return i
            }
        }
    }

    return nil
}

get_next :: proc(list: ^StaticList($T), index: int) -> Maybe(int) {
    if get(list, index) != nil {
        for i in index+1..<len(list.data) {
            if list.data[i].active {
                return i
            }
        }
    }

    return nil
}

get :: proc{get_static_list_elem}

delete_static_list_elem :: proc(list: ^StaticList($T), index: int) {
    if index >= 0 && index < len(list.data) {
        list.data[index].active = false
    }
}

delete_static_list :: proc(list: ^StaticList($T)) {
    runtime.delete(list.data)
}

delete :: proc{delete_static_list_elem, delete_static_list}