package ui

import "core:fmt"
import "core:strings"
import "core:math"
import "vendor:raylib"

import "../theme"

Context :: struct {
    text_width: proc() -> i32,
    text_height: proc() -> i32,
}

root: ^Box = nil;
current_parent: ^Box = nil;
persistent: map[Key]^Box = nil;
current_interaction_index: int = 0;

clips: [dynamic]Rect = nil;

Rect :: struct {
    pos: [2]int,
    size: [2]int,
}

Key :: struct {
    label: string,
    value: int,
}

Interaction :: struct {
    clicked: bool,
}

Flag :: enum {
    Clickable,
    Hoverable,
    Scrollable,
    DrawText,
    DrawBorder,
    DrawBackground,
}

SemanticSizeKind :: enum {
    FitText,
    Exact,
    ChildrenSum,
    Fill,
    PercentOfParent,
}

SemanticSize :: struct {
    kind: SemanticSizeKind,
    value: int,
}

Axis :: enum {
    Horizontal = 0,
    Vertical = 1,
}

Box :: struct {
    first: ^Box,
    last: ^Box,
    next: ^Box,
    prev: ^Box,
    parent: ^Box,

    key: Key,
    last_interacted_index: int,

    flags: bit_set[Flag],

    label: string,

    axis: Axis,
    semantic_size: [2]SemanticSize,
    computed_size: [2]int,

    computed_pos: [2]int
}

init :: proc() {
    if persistent == nil {
        persistent = make(map[Key]^Box);
    }

    if clips == nil {
        clips = make([dynamic]Rect);
    }

    root = new(Box);
    root.key = gen_key("root", 69);
    current_parent = root;
}

gen_key :: proc(label: string, value: int) -> Key {
    key_label := ""
    if current_parent == nil || len(current_parent.key.label) < 1 {
        key_label = strings.clone(label);
    } else {
        key_label = fmt.aprintf("%s:%s", current_parent.key.label, label);
    }

    return Key {
        label = key_label,
        value = value,
    };
}

make_box :: proc(key: Key, label: string, flags: bit_set[Flag], axis: Axis, semantic_size: [2]SemanticSize) -> ^Box {
    box: ^Box = nil;

    if cached_box, exists := persistent[key]; exists {
        if cached_box.last_interacted_index < current_interaction_index {
            old_cached_box := persistent[key];
            free(old_cached_box);
            box = new(Box);

            persistent[key] = box;
        } else {
            box = cached_box;
        }
    } else {
        box = new(Box);
        persistent[key] = box;
    }

    box.key = key;
    box.label = label;

    box.first = nil;
    box.last = nil;
    box.next = nil;
    box.prev = current_parent.last;
    box.parent = current_parent;
    box.flags = flags;
    box.axis = axis;
    box.semantic_size = semantic_size;
    box.computed_pos = {};
    box.computed_size = {};

    if current_parent.last != nil {
        current_parent.last.next = box;
    }
    if current_parent.first == nil {
        current_parent.first = box;
    }

    current_parent.last = box;

    return box;
}

make_semantic_size :: proc(kind: SemanticSizeKind, value: int = 0) -> SemanticSize {
    return SemanticSize {
        kind = kind,
        value = value
    };
}

FitText :[2]SemanticSize: {
    SemanticSize {
        kind = .FitText,
    },
    SemanticSize {
        kind = .FitText,
    }
};

ChildrenSum :[2]SemanticSize: {
    SemanticSize {
        kind = .ChildrenSum,
    },
    SemanticSize {
        kind = .ChildrenSum,
    }
};

push_box :: proc(label: string, flags: bit_set[Flag], axis: Axis = .Horizontal, semantic_size: [2]SemanticSize = FitText, value: int = 0) -> ^Box {
    key := gen_key(label, value);
    box := make_box(key, label, flags, axis, semantic_size);

    return box;
}

push_parent :: proc(box: ^Box) {
    current_parent = box;
}

pop_parent :: proc() {
    if current_parent.parent != nil {
        current_parent = current_parent.parent;
    }
}

test_box :: proc(box: ^Box) -> Interaction {
    return Interaction {
        clicked = false,
    };
}

delete_box_children :: proc(box: ^Box, keep_persistent: bool = true) {
    iter := BoxIter { box.first, 0 };

    for box in iterate_box(&iter) {
        delete_box(box, keep_persistent);
    }
}

delete_box :: proc(box: ^Box, keep_persistent: bool = true) {
    delete_box_children(box, keep_persistent);

    if !(box.key in persistent) || !keep_persistent {
        delete(box.key.label);
        free(box);
    }
}

prune :: proc() {
    iter := BoxIter { root.first, 0 };

    for box in iterate_box(&iter) {
        delete_box_children(box);

        if !(box.key in persistent) {
            free(box);
        }
    }

    root_key := root.key;
    root^ = {
        key = root_key,
    };
    current_parent = root;
}

ancestor_size :: proc(box: ^Box, axis: Axis) -> int {
    if box == nil || box.parent == nil {
        return root.computed_size[axis];
    }

    switch box.parent.semantic_size[axis].kind {
        case .FitText: fallthrough
        case .Exact: fallthrough
        case .Fill: fallthrough
        case .PercentOfParent:
            return box.parent.computed_size[axis];

        case .ChildrenSum:
            return ancestor_size(box.parent, axis);
    }

    return 1337;
}

compute_layout :: proc(canvas_size: [2]int, font_width: int, font_height: int, box: ^Box = root) {
    if box == nil { return; }

    axis := Axis.Horizontal;
    if box.parent != nil {
        axis = box.parent.axis;
        box.computed_pos = box.parent.computed_pos;
    }

    if box.prev != nil {
        box.computed_pos[axis] = box.prev.computed_pos[axis] + box.prev.computed_size[axis];
    }

    compute_children := true;
    if box == root {
        box.computed_size = canvas_size;
    } else {
        switch box.semantic_size.x.kind {
            case .FitText: {
                // TODO: don't use hardcoded font size
                box.computed_size.x = len(box.label) * font_width;
            }
            case .Exact: {
                box.computed_size.x = box.semantic_size.x.value;
            }
            case .ChildrenSum: {
                compute_children = false;
                box.computed_size.x = 0;

                iter := BoxIter { box.first, 0 };
                for child in iterate_box(&iter) {
                    compute_layout(canvas_size, font_width, font_height, child);

                    switch box.axis {
                        case .Horizontal: {
                            box.computed_size.x += child.computed_size.x;
                        }
                        case .Vertical: {
                            if child.computed_size.x > box.computed_size.x {
                                box.computed_size.x = child.computed_size.x;
                            }
                        }
                    }
                }
            }
            case .Fill: {
            }
            case .PercentOfParent: {
                box.computed_size.x = int(f32(ancestor_size(box, .Horizontal))*(f32(box.semantic_size.x.value)/100.0));
            }
        }
        switch box.semantic_size.y.kind {
            case .FitText: {
                // TODO: don't use hardcoded font size
                box.computed_size.y = font_height;
            }
            case .Exact: {
                box.computed_size.y = box.semantic_size.y.value;
            }
            case .ChildrenSum: {
                compute_children = false;
                should_post_compute := false;
                number_of_fills := 0;
                box.computed_size.y = 0;
                parent_size := ancestor_size(box, .Vertical);

                iter := BoxIter { box.first, 0 };
                for child in iterate_box(&iter) {
                    compute_layout(canvas_size, font_width, font_height, child);

                    if child.semantic_size.y.kind == .Fill {
                        number_of_fills += 1;
                        should_post_compute := true;
                    }

                    switch box.axis {
                        case .Horizontal: {
                            if child.computed_size.y > box.computed_size.y {
                                box.computed_size.y = child.computed_size.y;
                            }
                        }
                        case .Vertical: {
                            box.computed_size.y += child.computed_size.y;
                        }
                    }
                }

                // if should_post_compute {
                //     iter := BoxIter { box.first, 0 };
                //     for child in iterate_box(&iter) {
                //         if compute_layout(canvas_size, font_width, font_height, child) {
                //             child.computed_size.y =  (parent_size - box.computed_size.y) / number_of_fills;
                //         }
                //     }
                // }
            }
            case .Fill: {
            }
            case .PercentOfParent: {
                box.computed_size.y = int(f32(ancestor_size(box, .Vertical))*(f32(box.semantic_size.y.value)/100.0));
            }
        }
    }

    if compute_children {
        iter := BoxIter { box.first, 0 };
        should_post_compute := false;
        child_size: [2]int = {0,0};

        // NOTE: the number of fills for the opposite axis of this box needs to be 1
        // because it will never get incremented in the loop below and cause a divide by zero
        // and the number of fills for the axis of the box needs to start at zero or else it will
        // be n+1 causing incorrect sizes
        number_of_fills: [2]int = {1,1};
        number_of_fills[box.axis] = 0;

        our_size := box.computed_size;

        for child in iterate_box(&iter) {
            compute_layout(canvas_size, font_width, font_height, child);
            if child.semantic_size[box.axis].kind == .Fill {
                number_of_fills[box.axis] += 1;
                should_post_compute = true;
            } else {
                child_size[box.axis] += child.computed_size[box.axis];
            }
        }

        if should_post_compute {
            iter := BoxIter { box.first, 0 };
            for child in iterate_box(&iter) {
                for axis in 0..<2 {
                    if child.semantic_size[axis].kind == .Fill {
                        if child_size[axis] >= our_size[axis] {
                            child.computed_size[axis] = our_size[axis] / number_of_fills[axis];
                        } else {
                            child.computed_size[axis] = (our_size[axis] - child_size[axis]) / number_of_fills[axis];
                        }
                    }
                }

                compute_layout(canvas_size, font_width, font_height, child);
            }
        }
    }
}

push_clip :: proc(pos: [2]int, size: [2]int) {
    rect := Rect { pos, size };

    if len(clips) > 0 {
        parent_rect := clips[len(clips)-1];

        if rect.pos.x >= parent_rect.pos.x &&
            rect.pos.y >= parent_rect.pos.y &&
            rect.pos.x < parent_rect.pos.x + parent_rect.size.x &&
            rect.pos.y < parent_rect.pos.y + parent_rect.size.y
        {
            //rect.pos.x = math.max(rect.pos.x, parent_rect.pos.x);
            //rect.pos.y = math.max(rect.pos.y, parent_rect.pos.y);

            rect.size.x = math.min(rect.pos.x + rect.size.x, parent_rect.pos.x + parent_rect.size.x);
            rect.size.y = math.min(rect.pos.y + rect.size.y, parent_rect.pos.y + parent_rect.size.y);

            rect.size.x -= rect.pos.x;
            rect.size.y -= rect.pos.y;
        } else {
            rect = parent_rect;
        }
    }

    raylib.BeginScissorMode(
        i32(rect.pos.x),
        i32(rect.pos.y),
        i32(rect.size.x),
        i32(rect.size.y)
    );

    append(&clips, rect);
}

pop_clip :: proc() {
    raylib.EndScissorMode();

    if len(clips) > 0 {
        rect := pop(&clips);

        raylib.BeginScissorMode(
            i32(rect.pos.x),
            i32(rect.pos.y),
            i32(rect.size.x),
            i32(rect.size.y)
        );
    }
}

draw :: proc(font: raylib.Font, font_width: int, font_height: int, box: ^Box = root) {
    if box == nil { return; }

    // NOTE: for some reason if you place this right before the
    // for loop, the clipping only works for the first child. Compiler bug?
    push_clip(box.computed_pos, box.computed_size);
    defer pop_clip();

    if .DrawBackground in box.flags {
        raylib.DrawRectangle(
            i32(box.computed_pos.x),
            i32(box.computed_pos.y),
            i32(box.computed_size.x),
            i32(box.computed_size.y),
            theme.get_palette_raylib_color(.Background1)
        );
    }
    if .DrawBorder in box.flags {
        raylib.DrawRectangleLines(
            i32(box.computed_pos.x),
            i32(box.computed_pos.y),
            i32(box.computed_size.x),
            i32(box.computed_size.y),
            theme.get_palette_raylib_color(.Background4)
        );
    }
    if .DrawText in box.flags {
        for codepoint, index in box.label {
            raylib.DrawTextCodepoint(
                font,
                rune(codepoint),
                raylib.Vector2 { f32(box.computed_pos.x + index * font_width), f32(box.computed_pos.y) },
                f32(font_height),
                theme.get_palette_raylib_color(.Foreground1)
            );
        }
    }

    iter := BoxIter { box.first, 0 };
    for child in iterate_box(&iter) {
        draw(font, font_width, font_height, child);
    }
}

BoxIter :: struct {
    box: ^Box,
    index: int,
}

iterate_box :: proc(iter: ^BoxIter, print: bool = false) -> (box: ^Box, idx: int, cond: bool) {
    if iter.box == nil {
        return nil, iter.index, false;
    }

    box = iter.box;
    idx = iter.index;

    iter.box = iter.box.next;
    iter.index += 1;

    return box, iter.index, true;
}

debug_print :: proc(box: ^Box, depth: int = 0) {
    iter := BoxIter { box.first, 0 };

    for box, idx in iterate_box(&iter, true) {
        for _ in 0..<(depth*6) {
            fmt.print("-");
        }
        if depth > 0 {
            fmt.print(">");
        }
        fmt.println(idx, "Box", box.label, "#", box.key.label, "first", transmute(rawptr)box.first, "parent", transmute(rawptr)box.parent, box.computed_size);
        debug_print(box, depth+1);
    }

    if depth == 0 {
        fmt.println("persistent");
        for p in persistent {
            fmt.println(p);
        }
    }
}

spacer :: proc(label: string) -> ^Box {
    return push_box(label, {}, semantic_size = {make_semantic_size(.Fill, 0), make_semantic_size(.Fill, 0)});
}

label :: proc(label: string) -> Interaction {
    box := push_box(label, {.DrawText});

    return test_box(box);
}

button :: proc(label: string) -> Interaction {
    box := push_box(label, {.Clickable, .Hoverable, .DrawText, .DrawBorder, .DrawBackground});

    return test_box(box);
}

two_buttons_test :: proc(label1: string, label2: string) {
    push_parent(push_box("two_button_container", {.DrawBorder}, .Vertical, semantic_size = ChildrenSum));

    button("1");
    button("2");
    button(label1);
    button(label2);
    button("5");
    button("6");

    push_parent(push_box("two_button_container_inner", {.DrawBorder}, semantic_size = ChildrenSum));
    button("second first button");
    {
        push_parent(push_box("two_button_container_inner", {.DrawBorder}, .Vertical, semantic_size = {make_semantic_size(.PercentOfParent, 50), { .Exact, 256}}));
        defer pop_parent();

        button("first inner most button");
        button("inner_button2");
        button("inner_button3");
    }
    button("inner_button3");

    pop_parent();
    button("Help me I'm falling");
    pop_parent();
}
