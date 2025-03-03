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
}

UI_Element :: struct {
    first: Maybe(int),
    last: Maybe(int),
    next: Maybe(int),
    prev: Maybe(int),
    parent: Maybe(int),

    kind: UI_Element_Kind,
    layout: UI_Layout,
}

UI_Element_Kind :: union {
    UI_Element_Kind_Text,
    UI_Element_Kind_Image,
}

UI_Element_Kind_Text :: distinct string
UI_Element_Kind_Image :: distinct u64

UI_Layout :: struct {
    dir: UI_Direction,

    kind: [2]UI_Size_Kind,
    size: [2]int,
    pos: [2]int,
}

UI_Size_Kind :: union {
    Exact,
    Fit,
    Grow,
}

Exact :: distinct i32
Grow :: struct {}
Fit :: struct {}

UI_Direction :: enum {
    LeftToRight,
    RightToLeft,
    TopToBottom,
    BottomToTop,
}

open_element :: proc(state: ^State, kind: UI_Element_Kind, layout: UI_Layout) {
    e := UI_Element {
        kind = kind,
        layout = layout,
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
}

close_element :: proc(state: ^State, loc := #caller_location) {
    if curr, ok := state.current_open_element.?; ok {
        e := &state.curr_elements[curr]

        e.layout.size = {0,0}

        switch v in e.layout.kind[0] {
            case nil: {
                switch v in e.kind {
                    case UI_Element_Kind_Text: {
                        // FIXME: properly use font size
                        e.layout.size[0] = len(v) * 9
                    }
                    case UI_Element_Kind_Image: {
                        // TODO
                    }
                }
            }

            case Exact: { e.layout.size[0] = int(v) }
            case Fit: {
                child_index := e.first
                for child_index != nil {
                    child := &state.curr_elements[child_index.?]

                    switch e.layout.dir {
                        case .RightToLeft: fallthrough
                        case .LeftToRight: {
                            e.layout.size[0] += child.layout.size[0]
                        }

                        case .BottomToTop: fallthrough
                        case .TopToBottom: {
                            e.layout.size[0] = math.max(e.layout.size[0], child.layout.size[0])
                        }
                    }

                    child_index = child.next
                }
            }
            case Grow: { /* Done in the Grow pass */ }
        }

        switch v in e.layout.kind[1] {
            case nil: {
                switch v in e.kind {
                    case UI_Element_Kind_Text: {
                        // TODO: wrap text
                        // FIXME: properly use font size
                        e.layout.size[1] = 16
                    }
                    case UI_Element_Kind_Image: {
                        // TODO
                    }
                }
            }

            case Exact: { e.layout.size[1] = int(v) }
            case Fit: {
                child_index := e.first
                for child_index != nil {
                    child := &state.curr_elements[child_index.?]

                    switch e.layout.dir {
                        case .RightToLeft: fallthrough
                        case .LeftToRight: {
                            e.layout.size[1] = math.max(e.layout.size[1], child.layout.size[1])
                        }

                        case .BottomToTop: fallthrough
                        case .TopToBottom: {
                            e.layout.size[1] += child.layout.size[1]
                        }
                    }

                    child_index = child.next
                }
            }
            case Grow: { /* Done in the Grow pass */ }
        }

        grow_children(state, curr)

        state.current_open_element = e.parent
    } else {
        log.error("'close_element' has unmatched 'open_element' at", loc)
    }
}

@(private)
grow_children :: proc(state: ^State, index: int) {
    e := &state.curr_elements[index]

    children_size: [2]int
    num_growing: [2]int

    child_index := e.first
    for child_index != nil {
        child := &state.curr_elements[child_index.?]

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
            }

            case .BottomToTop: fallthrough
            case .TopToBottom: {
                children_size.y += child.layout.size.y
            }
        }

        child_index = child.next
    }

    if num_growing.x > 0 || num_growing.y > 0 {
        remaining_size := e.layout.size - children_size
        to_grow: [2]int 
        to_grow.x = 0 if num_growing.x < 1 else remaining_size.x/num_growing.x
        to_grow.y = 0 if num_growing.y < 1 else remaining_size.y/num_growing.y

        child_index := e.first
        for child_index != nil {
            child := &state.curr_elements[child_index.?]

            switch e.layout.dir {
                case .RightToLeft: fallthrough
                case .LeftToRight: {
                    if _, ok := child.layout.kind.x.(Grow); ok {
                        child.layout.size.x = to_grow.x
                    }
                    if _, ok := child.layout.kind.y.(Grow); ok {
                        child.layout.size.y = remaining_size.y
                    }
                }
                case .BottomToTop: fallthrough
                case .TopToBottom: {
                    if _, ok := child.layout.kind.x.(Grow); ok {
                        child.layout.size.x = remaining_size.x
                    }
                    if _, ok := child.layout.kind.y.(Grow); ok {
                        child.layout.size.y = to_grow.y
                    }
                }
            }

            child_index = child.next
        }
    }
}

compute_layout_2 :: proc(state: ^State) {
    for i in 0..<state.num_curr {
        e := &state.curr_elements[i]

        if parent_index, ok := e.parent.?; ok {
            parent := &state.curr_elements[parent_index]

            if prev_index, ok := e.prev.?; ok {
                prev := &state.curr_elements[prev_index]

                switch parent.layout.dir {
                    case .LeftToRight: {
                        e.layout.pos[0] = prev.layout.pos[0]+prev.layout.size[0] /* TODO: + child_gap */
                    }
                    case .RightToLeft: {
                        // TODO:
                        // e.layout.pos[0] = prev.layout.pos[0]-prev.layout.size[0] /* TODO: - child_gap */
                    }

                    case .TopToBottom: {
                        e.layout.pos[1] = prev.layout.pos[1]+prev.layout.size[1] /* TODO: + child_gap */
                    }
                    case .BottomToTop: {
                        // TODO:
                        // e.layout.pos[1] = prev.layout.pos[1]-prev.layout.size[1] /* TODO: - child_gap */
                    }
                }
            }
        }
    }
}

new_draw :: proc(state: ^State, core_state: ^core.State) {
    for i in 0..<state.num_curr {
        e := &state.curr_elements[i]

        switch v in e.kind {
            case nil: {
                core.draw_rect(
                    core_state,
                    e.layout.pos.x,
                    e.layout.pos.y,
                    e.layout.size.x,
                    e.layout.size.y,
                    .Background1
                );
                core.draw_rect_outline(
                    core_state,
                    e.layout.pos.x,
                    e.layout.pos.y,
                    e.layout.size.x,
                    e.layout.size.y,
                    .Background4
                );
            }
            case UI_Element_Kind_Text: {
                core.draw_text(core_state, string(v), e.layout.pos.x, e.layout.pos.y);
            }
            case UI_Element_Kind_Image: {
                // TODO
            }
        }
    }

    state.num_curr = 0
}
