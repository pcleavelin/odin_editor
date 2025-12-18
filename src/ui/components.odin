package ui

import "core:fmt"

spacer :: proc{growing_spacer, exact_spacer}

growing_spacer :: proc(s: ^State) {
    open_element(s, nil, { kind = {Grow{}, Grow{}} })
    close_element(s)
}

close_growing_spacer :: proc(s: ^State) {
    open_element(s, nil, { kind = {Grow{}, Grow{}} })
    close_element(s)
}

exact_spacer :: proc(s: ^State, size: int) {
    open_element(s, nil, { kind = {Exact(size), Exact(size)} })
    close_element(s)
}

centered_top_to_bottom :: proc(s: ^State) {
    open_element(s, nil,
        {
            dir = .TopToBottom,
            kind = {Fit{}, Grow{}},
        },
    )

    growing_spacer(s)

    // user component after here
}

centered_left_to_right :: proc(s: ^State) {
    open_element(s, nil,
        {
            dir = .LeftToRight,
            kind = {Grow{}, Fit{}},
        },
    )

    growing_spacer(s)

    // user component after here
}

close_centered_top_to_bottom :: proc(s: ^State) {
    // user component before here

    close_growing_spacer(s)
    close_element(s)
}
close_centered_left_to_right :: close_centered_top_to_bottom

centered :: proc(s: ^State) {
    centered_left_to_right(s)
    centered_top_to_bottom(s)

    // user component after here
}

close_centered :: proc(s: ^State) {
    // user component before here
    close_centered_top_to_bottom(s)
    close_centered_left_to_right(s)
}

left_to_right :: proc(s: ^State) -> UI_Element {
    return open_element(s, nil,
        {
            dir = .LeftToRight,
            kind = {Fit{}, Fit{}},
        },
    )
}
top_to_bottom :: proc(s: ^State) -> UI_Element {
    return open_element(s, nil,
        {
            dir = .TopToBottom,
            kind = {Fit{}, Fit{}},
        },
    )
}
growing_top_to_bottom :: proc(s: ^State) -> UI_Element {
    return open_element(s, nil,
        {
            dir = .TopToBottom,
            kind = {Grow{}, Grow{}},
        },
    )
}

RenderItemProc :: proc(s: ^State, item: rawptr, state: rawptr)
list :: proc($T: typeid, s: ^State, items: []T, state: rawptr, selected_item: ^int, list_start: ^int, render_item: RenderItemProc) {
    assert(selected_item != nil)
    assert(list_start != nil)

    if len(items) < 1 {
        return
    }

    if selected_item^ >= len(items) {
        selected_item^ = len(items)-1
    }

    list_container := growing_top_to_bottom(s)
    list_total_height := list_container.layout.size.y
    max_items := list_total_height / (s.font_size.y * 2)
    list_end := max_items + list_start^
    selection_threshold := 3 if max_items > 6 else 0

    if list_start^ < list_end-1 && list_end < len(items) && selected_item^ >= list_end - selection_threshold {
        list_start^ = list_start^ + 1
    } else if list_start^ > 0 && selected_item^ < list_start^ + selection_threshold {
        list_start^ = list_start^ - 1
    }

    {
        for &item, i in items[list_start^:] {
            if i >= max_items {
                break
            }

            open_element(s, nil,
            {
                kind = {Grow{},Exact(s.font_size.y * 2)}
            },
            style = {
                border = {.Bottom, .Top},
                border_color = .Background4,
                background_color = .Background3 if i+list_start^ == selected_item^ else .None,
            }
        )
        {
            render_item(s, &item, state)
        }
        close_element(s)
    }
}
    close_element(s)
}

