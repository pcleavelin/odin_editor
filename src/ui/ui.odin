package ui

import "core:math"
import "core:mem"
import "core:log"

import "../core"
import "../theme"

State :: struct {
    current_open_element: Maybe(int),
    num_curr: int,
    num_prev: int,
    curr_elements: []UI_Element,
    prev_elements: []UI_Element,

    max_size: [2]int, 
}

UI_Element :: struct {
    first: Maybe(int),
    last: Maybe(int),
    next: Maybe(int),
    prev: Maybe(int),
    parent: Maybe(int),

    kind: UI_Element_Kind,
    layout: UI_Layout,
    style: UI_Style,
}

UI_Element_Kind :: union {
    UI_Element_Kind_Text,
    UI_Element_Kind_Image,
    UI_Element_Kind_Custom,
}

UI_Element_Kind_Text :: string
UI_Element_Kind_Image :: distinct u64
UI_Element_Kind_Custom :: struct {
    user_data: rawptr,
    fn: proc(state: ^core.State, element: UI_Element, user_data: rawptr),
}

UI_Layout :: struct {
    dir: UI_Direction,

    kind: [2]UI_Size_Kind,
    size: [2]int,
    pos: [2]int,

    floating: bool,
}

UI_Size_Kind :: union {
    Exact,
    Fit,
    Grow,
}

Exact :: distinct i32
Grow :: struct {}
Fit :: struct {}

UI_Style :: struct {
    border: UI_Border_Set,

    border_color: theme.PaletteColor,
    background_color: theme.PaletteColor,
}
UI_Border_Set :: bit_set[UI_Border]
UI_Border :: enum{Left, Right, Top, Bottom}

UI_Direction :: enum {
    LeftToRight,
    RightToLeft,
    TopToBottom,
    BottomToTop,
}

open_element :: proc(state: ^State, kind: UI_Element_Kind, layout: UI_Layout, style: UI_Style = {}) -> UI_Element {
    e := UI_Element {
        kind = kind,
        layout = layout,
        style = style,
    }
    
    if !e.layout.floating {
        e.layout.pos = state.curr_elements[state.num_curr].layout.pos
        e.layout.size = state.curr_elements[state.num_curr].layout.size
    }

    if parent, ok := state.current_open_element.?; ok {
        e.parent = parent

        if last, ok := state.curr_elements[parent].last.?; ok {
            e.prev = last

            state.curr_elements[e.prev.?].next = state.num_curr
        }

        state.curr_elements[parent].last = state.num_curr

        if state.curr_elements[parent].first == nil {
            state.curr_elements[parent].first = state.num_curr
        }
    }

    state.curr_elements[state.num_curr] = e
    state.current_open_element = state.num_curr
    state.num_curr += 1

    return e
}

close_element :: proc(state: ^State, loc := #caller_location) -> UI_Layout {
    if curr, ok := state.current_open_element.?; ok {
        e := &state.curr_elements[curr]

        e.layout.size = {0,0}

        switch v in e.layout.kind[0] {
            case nil: {
                switch v in e.kind {
                    case UI_Element_Kind_Text: {
                        // FIXME: properly use font size
                        e.layout.size.x = len(v) * 12
                    }
                    case UI_Element_Kind_Image: {
                        // TODO
                    }
                    case UI_Element_Kind_Custom: { }
                }
            }

            case Exact: { e.layout.size.x = int(v) }
            case Fit: {
                it := e.first
                for child in iterate_siblings(state, &it) {
                    if child.layout.floating { continue }

                    switch e.layout.dir {
                        case .RightToLeft: fallthrough
                        case .LeftToRight: {
                            e.layout.size.x += child.layout.size.x
                        }

                        case .BottomToTop: fallthrough
                        case .TopToBottom: {
                            e.layout.size.x = math.max(e.layout.size.x, child.layout.size.x)
                        }
                    }
                }
            }
            case Grow: {
                if _, ok := e.parent.?; !ok {
                    e.layout.size = state.max_size
                }
            }
        }

        switch v in e.layout.kind.y {
            case nil: {
                switch v in e.kind {
                    case UI_Element_Kind_Text: {
                        // TODO: wrap text
                        // FIXME: properly use font size
                        e.layout.size.y = 16
                    }
                    case UI_Element_Kind_Image: {
                        // TODO
                    }
                    case UI_Element_Kind_Custom: { }
                }
            }

            case Exact: { e.layout.size.y = int(v) }
            case Fit: {
                it := e.first
                for child in iterate_siblings(state, &it) {
                    if child.layout.floating { continue }

                    switch e.layout.dir {
                        case .RightToLeft: fallthrough
                        case .LeftToRight: {
                            e.layout.size.y = math.max(e.layout.size.y, child.layout.size.y)
                        }

                        case .BottomToTop: fallthrough
                        case .TopToBottom: {
                            e.layout.size.y += child.layout.size.y
                        }
                    }
                }
            }
            case Grow: { /* Done in the Grow pass */ }
        }

        state.current_open_element = e.parent

        return e.layout
    } else {
        log.error("'close_element' has unmatched 'open_element' at", loc)

        return UI_Layout{}
    }
}

@(private)
iterate_siblings :: proc(state: ^State, sibling: ^Maybe(int)) -> (e: ^UI_Element, index: int, cond: bool) {
    if sibling == nil || sibling^ == nil {
        cond = false
        return
    }

    e = &state.curr_elements[sibling.?]
    index = sibling.?
    cond = true

    sibling^ = e.next
    
    return
}

@(private)
iterate_siblings_reverse :: proc(state: ^State, sibling: ^Maybe(int)) -> (e: ^UI_Element, index: int, cond: bool) {
    if sibling == nil || sibling^ == nil {
        cond = false
        return
    }

    e = &state.curr_elements[sibling.?]
    index = sibling.?
    cond = true

    sibling^ = e.prev
    
    return
}

@(private)
non_fit_parent_size :: proc(state: ^State, index: int, axis: int) -> int {
    if _, ok := state.curr_elements[index].layout.kind[axis].(Fit); ok {
        if parent_index, ok := state.curr_elements[index].parent.?; ok && !state.curr_elements[index].layout.floating {
            return non_fit_parent_size(state, parent_index, axis)
        } else {
            return state.max_size[axis]
        }
    } else if state.curr_elements[index].layout.floating {
        return state.max_size[axis]
    } else {
        return state.curr_elements[index].layout.size[axis]
    }
}

@(private)
prev_non_floating :: proc(state: ^State, index: Maybe(int)) -> Maybe(int) {
    it := index
    for sibling, index in iterate_siblings_reverse(state, &it) {
        if sibling.layout.floating { continue }

        return index
    }

    return nil
}

@(private)
grow_children :: proc(state: ^State, index: int) {
    e := &state.curr_elements[index]

    x_e := non_fit_parent_size(state, index, 0);
    y_e := non_fit_parent_size(state, index, 1);

    children_size: [2]int
    num_growing: [2]int

    has_floating := false

    it := e.first
    for child in iterate_siblings(state, &it) {
        if child.layout.floating {
            has_floating = true
            continue
        }

        if _, ok := child.layout.kind.x.(Grow); ok {
            num_growing.x += 1
        }
        if _, ok := child.layout.kind.y.(Grow); ok {
            num_growing.y += 1
        }

        switch e.layout.dir {
            case .RightToLeft: fallthrough
            case .LeftToRight: {
                children_size.x += child.layout.size.x

                if children_size.y < child.layout.size.y {
                    children_size.y = child.layout.size.y
                }
            }

            case .BottomToTop: fallthrough
            case .TopToBottom: {
                children_size.y += child.layout.size.y

                if children_size.x < child.layout.size.x {
                    children_size.x = child.layout.size.x
                }
            }
        }
    }

    if num_growing.x > 0 || num_growing.y > 0 {
        remaining_size := [2]int{ x_e, y_e } - children_size
        to_grow: [2]int
        to_grow.x = 0 if num_growing.x < 1 else remaining_size.x/num_growing.x
        to_grow.y = 0 if num_growing.y < 1 else remaining_size.y/num_growing.y

        it := e.first
        for child, child_index in iterate_siblings(state, &it) {
            switch e.layout.dir {
                case .RightToLeft: fallthrough
                case .LeftToRight: {
                    if _, ok := child.layout.kind.x.(Grow); ok {
                        child.layout.size.x = state.max_size.x if child.layout.floating else to_grow.x
                    }
                    if _, ok := child.layout.kind.y.(Grow); ok {
                        child.layout.size.y = state.max_size.y if child.layout.floating else y_e
                    }
                }
                case .BottomToTop: fallthrough
                case .TopToBottom: {
                    if _, ok := child.layout.kind.x.(Grow); ok {
                        child.layout.size.x = state.max_size.x if child.layout.floating else x_e
                    }
                    if _, ok := child.layout.kind.y.(Grow); ok {
                        child.layout.size.y = state.max_size.y if child.layout.floating else to_grow.y
                    }
                }
            }

            _, x_growing := child.layout.kind.x.(Grow)
            _, y_growing := child.layout.kind.y.(Grow)

            if x_growing || y_growing || child.layout.floating {
                grow_children(state, child_index)
            }
        }
    }
}

compute_layout :: proc(state: ^State) {
    grow_children(state, 0)

    for i in 0..<state.num_curr {
        e := &state.curr_elements[i]

        if parent_index, ok := e.parent.?; ok && !e.layout.floating {
            parent := &state.curr_elements[parent_index]

            if prev_index, ok := prev_non_floating(state, e.prev).?; ok {
                prev := &state.curr_elements[prev_index]

                switch parent.layout.dir {
                    case .LeftToRight: {
                        e.layout.pos.x = prev.layout.pos.x+prev.layout.size.x /* TODO: + child_gap */
                        e.layout.pos.y = parent.layout.pos.y
                    }
                    case .RightToLeft: {
                        // TODO:
                        // e.layout.pos[0] = prev.layout.pos[0]-prev.layout.size[0] /* TODO: - child_gap */
                    }

                    case .TopToBottom: {
                        e.layout.pos.x = parent.layout.pos.x
                        e.layout.pos.y = prev.layout.pos.y+prev.layout.size.y /* TODO: + child_gap */
                    }
                    case .BottomToTop: {
                        // TODO:
                        // e.layout.pos[1] = prev.layout.pos[1]-prev.layout.size[1] /* TODO: - child_gap */
                    }
                }
            } else {
                switch parent.layout.dir {
                    case .LeftToRight: {
                        e.layout.pos.x = parent.layout.pos.x /* TODO: + padding */
                        e.layout.pos.y = parent.layout.pos.y
                    }
                    case .RightToLeft: {
                        // TODO:
                        // e.layout.pos[0] = prev.layout.pos[0]-prev.layout.size[0] /* TODO: - padding */
                    }

                    case .TopToBottom: {
                        e.layout.pos.x = parent.layout.pos.x
                        e.layout.pos.y = parent.layout.pos.y /* TODO: + padding */
                    }
                    case .BottomToTop: {
                        // TODO:
                        // e.layout.pos[1] = prev.layout.pos[1]-prev.layout.size[1] /* TODO: - padding */
                    }
                }
            }
        }
    }
}

draw :: proc(state: ^State, core_state: ^core.State) {
    for i in 0..<state.num_curr {
        e := &state.curr_elements[i]

        core.draw_rect(
            core_state,
            e.layout.pos.x,
            e.layout.pos.y,
            e.layout.size.x,
            e.layout.size.y,
            e.style.background_color,
        );

        switch v in e.kind {
            case nil: {
                // core.draw_rect(
                //     core_state,
                //     e.layout.pos.x,
                //     e.layout.pos.y,
                //     e.layout.size.x,
                //     e.layout.size.y,
                //     e.style.background_color,
                // );
                // core.draw_rect_outline(
                //     core_state,
                //     e.layout.pos.x,
                //     e.layout.pos.y,
                //     e.layout.size.x,
                //     e.layout.size.y,
                //     .Background4
                // );
            }
            case UI_Element_Kind_Text: {
                core.draw_text(core_state, string(v), e.layout.pos.x, e.layout.pos.y);
            }
            case UI_Element_Kind_Image: {
                // TODO
            }
            case UI_Element_Kind_Custom: {
                v.fn(core_state, e^, v.user_data) 
            }
        }
    }

    // Separate loop done to draw border over elements
    for i in 0..<state.num_curr {
        e := &state.curr_elements[i]

        if .Left in e.style.border {
            core.draw_line(
                core_state,
                e.layout.pos.x,
                e.layout.pos.y,
                e.layout.pos.x,
                e.layout.pos.y + e.layout.size.y,
                e.style.border_color,
            )
        }
        if .Right in e.style.border {
            core.draw_line(
                core_state,
                e.layout.pos.x + e.layout.size.x,
                e.layout.pos.y,
                e.layout.pos.x + e.layout.size.x,
                e.layout.pos.y + e.layout.size.y,
                e.style.border_color,
            )
        }
        if .Top in e.style.border {
            core.draw_line(
                core_state,
                e.layout.pos.x,
                e.layout.pos.y,
                e.layout.pos.x + e.layout.size.x,
                e.layout.pos.y,
                e.style.border_color,
            )
        }
        if .Bottom in e.style.border {
            core.draw_line(
                core_state,
                e.layout.pos.x,
                e.layout.pos.y + e.layout.size.y,
                e.layout.pos.x + e.layout.size.x,
                e.layout.pos.y + e.layout.size.y,
                e.style.border_color,
            )
        }
    }

    state.num_curr = 0
}
