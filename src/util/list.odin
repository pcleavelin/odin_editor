package util

import "base:runtime"

StaticList :: struct($T: typeid) {
    data: []T,
    len: int,
}

append_static_list :: proc(list: ^StaticList($T), value: T) -> bool {
    if list.len >= len(list.data) {
        return false
    }

    list.data[list.len] = value
    list.len += 1

    return true
}
append :: proc{append_static_list}

make_static_list :: proc($T: typeid, len: int) -> StaticList(T) {
    list := StaticList(T) {
        data = runtime.make_slice([]T, len)
    }

    return list
}

make :: proc{make_static_list}

get_static_list_elem :: proc(list: ^StaticList($T), index: int) -> Maybe(^T) {
    if index >= list.len {
        return nil
    }

    return &list.data[index]
}

get :: proc{get_static_list_elem}