package ui

import "core:fmt"
import "core:strings"
import "core:math"
import "vendor:sdl2"

import "../core"
import "../theme"

Context :: struct {
    root: ^Box,
    current_parent: ^Box,
    persistent: map[Key]^Box,
    current_interaction_index: int,

    clips: [dynamic]Rect,
    renderer: ^sdl2.Renderer,

    mouse_x: int,
    mouse_y: int,

    mouse_left_down: bool,
    last_mouse_left_down: bool,

    mouse_right_down: bool,
    last_mouse_right_down: bool,
}

Rect :: struct {
    pos: [2]int,
    size: [2]int,
}

Key :: struct {
    label: string,
    value: int,
}

Interaction :: struct {
    hovering: bool,
    clicked: bool,
}

Flag :: enum {
    Clickable,
    Hoverable,
    Scrollable,
    DrawText,
    DrawBorder,
    DrawBackground,
    Floating,
    CustomDrawFunc,
}

SemanticSizeKind :: enum {
    FitText = 0,
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

CustomDrawFunc :: proc(state: ^core.State, box: ^Box, user_data: rawptr);
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
    computed_pos: [2]int,

    hot: int,
    active: int,

    custom_draw_func: CustomDrawFunc,
    user_data: rawptr,
}

init :: proc(renderer: ^sdl2.Renderer) -> Context {
    root := new(Box);
    root.key = gen_key(nil, "root", 69);

    return Context {
        root = root,
        current_parent = root,
        persistent = make(map[Key]^Box),
        clips = make([dynamic]Rect),
        renderer = renderer,
    };
}

gen_key :: proc(ctx: ^Context, label: string, value: int) -> Key {
    key_label := ""
    if ctx != nil && (ctx.current_parent == nil || len(ctx.current_parent.key.label) < 1) {
        key_label = strings.clone(label);
    } else if ctx != nil {
        key_label = fmt.aprintf("%s:%s", ctx.current_parent.key.label, label);
    } else {
        key_label = fmt.aprintf("%s",label);
    }

    return Key {
        label = key_label,
        value = value,
    };
}

@(private)
make_box :: proc(ctx: ^Context, key: Key, label: string, flags: bit_set[Flag], axis: Axis, semantic_size: [2]SemanticSize) -> ^Box {
    box: ^Box = nil;

    if cached_box, exists := ctx.persistent[key]; exists {
        if cached_box.last_interacted_index < ctx.current_interaction_index {
            old_cached_box := ctx.persistent[key];
            free(old_cached_box);
            box = new(Box);

            ctx.persistent[key] = box;
        } else {
            box = cached_box;
        }
    } else {
        box = new(Box);
        ctx.persistent[key] = box;
    }

    box.key = key;
    box.label = label;

    box.first = nil;
    box.last = nil;
    box.next = nil;
    box.prev = ctx.current_parent.last;
    box.parent = ctx.current_parent;
    box.flags = flags;
    box.axis = axis;
    box.semantic_size = semantic_size;

    if ctx.current_parent.last != nil {
        ctx.current_parent.last.next = box;
    }
    if ctx.current_parent.first == nil {
        ctx.current_parent.first = box;
    }

    ctx.current_parent.last = box;

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

Fill :[2]SemanticSize: {
    SemanticSize {
        kind = .Fill,
    },
    SemanticSize {
        kind = .Fill,
    }
};

push_box :: proc(ctx: ^Context, label: string, flags: bit_set[Flag], axis: Axis = .Horizontal, semantic_size: [2]SemanticSize = FitText, value: int = 0) -> ^Box {
    key := gen_key(ctx, label, value);
    box := make_box(ctx, key, label, flags, axis, semantic_size);

    return box;
}

push_parent :: proc(ctx: ^Context, box: ^Box) {
    ctx.current_parent = box;
}

pop_parent :: proc(ctx: ^Context) {
    if ctx.current_parent.parent != nil {
        ctx.current_parent = ctx.current_parent.parent;
    }
}

test_box :: proc(ctx: ^Context, box: ^Box) -> Interaction {
    hovering: bool;

    mouse_is_clicked := !ctx.last_mouse_left_down && ctx.mouse_left_down;

    if ctx.mouse_x >= box.computed_pos.x && ctx.mouse_x <= box.computed_pos.x + box.computed_size.x &&
        ctx.mouse_y >= box.computed_pos.y && ctx.mouse_y <= box.computed_pos.y + box.computed_size.y
    {
        hovering = true;
    }

    if hovering {
        box.hot += 1;
    } else {
        box.hot = 0;
    }

    return Interaction {
        hovering = hovering,
        clicked = hovering && mouse_is_clicked,
    };
}

delete_box_children :: proc(ctx: ^Context, box: ^Box, keep_persistent: bool = true) {
    iter := BoxIter { box.first, 0 };

    for box in iterate_box(&iter) {
        delete_box(ctx, box, keep_persistent);
    }
}

delete_box :: proc(ctx: ^Context, box: ^Box, keep_persistent: bool = true) {
    delete_box_children(ctx, box, keep_persistent);

    if !(box.key in ctx.persistent) || !keep_persistent {
        delete(box.key.label);
        free(box);
    }
}

prune :: proc(ctx: ^Context) {
    iter := BoxIter { ctx.root.first, 0 };

    for box in iterate_box(&iter) {
        delete_box_children(ctx, box);

        if !(box.key in ctx.persistent) {
            free(box);
        }
    }

    computed_pos := ctx.root.computed_pos;
    computed_size := ctx.root.computed_size;
    root_key := ctx.root.key;

    ctx.root.first = nil;
    ctx.root.last = nil;
    ctx.root.next = nil;
    ctx.root.prev = nil;
    ctx.root.parent = nil;
    ctx.current_parent = ctx.root;
}

// TODO: consider not using `ctx` here
ancestor_size :: proc(ctx: ^Context, box: ^Box, axis: Axis) -> int {
    if box == nil || box.parent == nil || .Floating in box.flags {
        return ctx.root.computed_size[axis];
    }

    switch box.parent.semantic_size[axis].kind {
        case .FitText: fallthrough
        case .Exact: fallthrough
        case .Fill: fallthrough
        case .PercentOfParent:
            return box.parent.computed_size[axis];

        case .ChildrenSum:
            return ancestor_size(ctx, box.parent, axis);
    }

    return 1337;
}

prev_non_floating_sibling :: proc(ctx: ^Context, box: ^Box) -> ^Box {
    if box == nil {
        return nil;
    } else if box.prev == nil {
        return nil;
    } else if !(.Floating in box.prev.flags) {
        return box.prev;
    } else {
        return prev_non_floating_sibling(ctx, box.prev);
    }
}

compute_layout :: proc(ctx: ^Context, canvas_size: [2]int, font_width: int, font_height: int, box: ^Box) {
    if box == nil { return; }

    axis := Axis.Horizontal;
    if box.parent != nil && !(.Floating in box.flags) {
        axis = box.parent.axis;
        box.computed_pos = box.parent.computed_pos;
    }

    if .Floating in box.flags {
        // box.computed_pos = {0,0};
    } else if box.prev != nil {
        prev := prev_non_floating_sibling(ctx, box);

        if prev != nil {
            box.computed_pos[axis] = prev.computed_pos[axis] + prev.computed_size[axis];
        }
    }

    post_compute_size := [2]bool { false, false };
    compute_children := true;
    if box == ctx.root {
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
                //compute_children = false;
                post_compute_size[int(Axis.Horizontal)] = true;
                // box.computed_size.x = 0;

                // iter := BoxIter { box.first, 0 };
                // for child in iterate_box(&iter) {
                //     compute_layout(canvas_size, font_width, font_height, child);

                //     switch box.axis {
                //         case .Horizontal: {
                //             box.computed_size.x += child.computed_size.x;
                //         }
                //         case .Vertical: {
                //             if child.computed_size.x > box.computed_size.x {
                //                 box.computed_size.x = child.computed_size.x;
                //             }
                //         }
                //     }
                // }
            }
            case .Fill: {
            }
            case .PercentOfParent: {
                box.computed_size.x = int(f32(ancestor_size(ctx, box, .Horizontal))*(f32(box.semantic_size.x.value)/100.0));
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
                //compute_children = false;
                post_compute_size[Axis.Vertical] = true;

                // should_post_compute := false;
                // number_of_fills := 0;
                // box.computed_size.y = 0;
                // parent_size := ancestor_size(box, .Vertical);

                // iter := BoxIter { box.first, 0 };
                // for child in iterate_box(&iter) {
                //     compute_layout(canvas_size, font_width, font_height, child);

                //     if child.semantic_size.y.kind == .Fill {
                //         number_of_fills += 1;
                //         should_post_compute := true;
                //     }

                //     switch box.axis {
                //         case .Horizontal: {
                //             if child.computed_size.y > box.computed_size.y {
                //                 box.computed_size.y = child.computed_size.y;
                //             }
                //         }
                //         case .Vertical: {
                //             box.computed_size.y += child.computed_size.y;
                //         }
                //     }
                // }

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
                box.computed_size.y = int(f32(ancestor_size(ctx, box, .Vertical))*(f32(box.semantic_size.y.value)/100.0));
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
            if .Floating in child.flags { continue; }

            compute_layout(ctx, canvas_size, font_width, font_height, child);
            if child.semantic_size[box.axis].kind == .Fill {
                number_of_fills[box.axis] += 1;
                should_post_compute = true;
            } else {
                child_size[box.axis] += child.computed_size[box.axis];
            }
        }

        if true || should_post_compute {
            iter := BoxIter { box.first, 0 };
            for child in iterate_box(&iter) {
                for axis in 0..<2 {
                    if child.semantic_size[axis].kind == .Fill {
                        if false && child_size[axis] >= our_size[axis] {
                            child.computed_size[axis] = our_size[axis] / number_of_fills[axis];
                        } else {
                            child.computed_size[axis] = (our_size[axis] - child_size[axis]) / number_of_fills[axis];
                        }
                    }
                }

                compute_layout(ctx, canvas_size, font_width, font_height, child);

                if child.label == "2" {
                    fmt.println(child.label, child.computed_size, box.label, our_size, child_size, number_of_fills);
                }
            }
        }
    }

    if post_compute_size[Axis.Horizontal] {
        box.computed_size[Axis.Horizontal] = 0;

        iter := BoxIter { box.first, 0 };
        for child in iterate_box(&iter) {
            switch box.axis {
                case .Horizontal: {
                    box.computed_size[Axis.Horizontal] += child.computed_size[Axis.Horizontal];
                }
                case .Vertical: {
                    if child.computed_size[Axis.Horizontal] > box.computed_size[Axis.Horizontal] {
                        box.computed_size[Axis.Horizontal] = child.computed_size[Axis.Horizontal];
                    }
                }
            }
        }
    }
    if post_compute_size[Axis.Vertical] {
        box.computed_size[Axis.Vertical] = 0;

        iter := BoxIter { box.first, 0 };
        for child in iterate_box(&iter) {
            switch box.axis {
                case .Horizontal: {
                    if child.computed_size[Axis.Vertical] > box.computed_size[Axis.Vertical] {
                        box.computed_size[Axis.Vertical] = child.computed_size[Axis.Vertical];
                    }
                }
                case .Vertical: {
                    box.computed_size[Axis.Vertical] += child.computed_size[Axis.Vertical];
                }
            }
        }
    }
}

push_clip :: proc(ctx: ^Context, pos: [2]int, size: [2]int) {
    rect := Rect { pos, size };

    if len(ctx.clips) > 0 {
        parent_rect := ctx.clips[len(ctx.clips)-1];

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

    sdl2.RenderSetClipRect(ctx.renderer, &sdl2.Rect {
        i32(rect.pos.x),
        i32(rect.pos.y),
        i32(rect.size.x),
        i32(rect.size.y)
    });

    // raylib.BeginScissorMode(
    //     i32(rect.pos.x),
    //     i32(rect.pos.y),
    //     i32(rect.size.x),
    //     i32(rect.size.y)
    // );

    append(&ctx.clips, rect);
}

pop_clip :: proc(ctx: ^Context) {
    //raylib.EndScissorMode();

    if len(ctx.clips) > 0 {
        rect := pop(&ctx.clips);

        sdl2.RenderSetClipRect(ctx.renderer, &sdl2.Rect {
            i32(rect.pos.x),
            i32(rect.pos.y),
            i32(rect.size.x),
            i32(rect.size.y)
        });
        // raylib.BeginScissorMode(
        //     i32(rect.pos.x),
        //     i32(rect.pos.y),
        //     i32(rect.size.x),
        //     i32(rect.size.y)
        // );
    } else {
        sdl2.RenderSetClipRect(ctx.renderer, nil);
    }
}

draw :: proc(ctx: ^Context, state: ^core.State, font_width: int, font_height: int, box: ^Box) {
    if box == nil { return; }

    // NOTE: for some reason if you place this right before the
    // for loop, the clipping only works for the first child. Compiler bug?
    push_clip(ctx, box.computed_pos, box.computed_size);
    defer pop_clip(ctx);

    if .Hoverable in box.flags && box.hot > 0 {
        core.draw_rect(
            state,
            box.computed_pos.x,
            box.computed_pos.y,
            box.computed_size.x,
            box.computed_size.y,
            .Background2
        );
    }
    else if .DrawBackground in box.flags {
        core.draw_rect(
            state,
            box.computed_pos.x,
            box.computed_pos.y,
            box.computed_size.x,
            box.computed_size.y,
            .Background1
        );
    }

    if .DrawBorder in box.flags {
        core.draw_rect_outline(
            state,
            box.computed_pos.x,
            box.computed_pos.y,
            box.computed_size.x,
            box.computed_size.y,
            .Background4
        );
    }
    if .DrawText in box.flags {
        core.draw_text(state, box.label, box.computed_pos.x, box.computed_pos.y);
    }

    if .CustomDrawFunc in box.flags && box.custom_draw_func != nil {
        box.custom_draw_func(state, box, box.user_data);
    }

    iter := BoxIter { box.first, 0 };
    for child in iterate_box(&iter) {
        draw(ctx, state, font_width, font_height, child);
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

debug_print :: proc(ctx: ^Context, box: ^Box, depth: int = 0) {
    iter := BoxIter { box.first, 0 };

    for box, idx in iterate_box(&iter, true) {
        for _ in 0..<(depth*6) {
            fmt.print("-");
        }
        if depth > 0 {
            fmt.print(">");
        }
        fmt.println(idx, "Box", box.label, "#", box.key.label, "first", transmute(rawptr)box.first, "parent", transmute(rawptr)box.parent, box.computed_size);
        debug_print(ctx, box, depth+1);
    }

    if depth == 0 {
        fmt.println("persistent");
        for p in ctx.persistent {
            fmt.println(p);
        }
    }
}

spacer :: proc(ctx: ^Context, label: string, flags: bit_set[Flag] = {}, semantic_size: [2]SemanticSize = {{.Fill, 0}, {.Fill,0}}) -> ^Box {
    return push_box(ctx, label, flags, semantic_size = semantic_size);
}

push_floating :: proc(ctx: ^Context, label: string, pos: [2]int, flags: bit_set[Flag] = {.Floating}, axis: Axis = .Vertical, semantic_size: [2]SemanticSize = Fill) -> ^Box {
    box := push_box(ctx, label, flags, semantic_size = semantic_size);
    box.computed_pos = pos;

    return box;
}

push_rect :: proc(ctx: ^Context, label: string, border: bool = true, axis: Axis = .Vertical, semantic_size: [2]SemanticSize = Fill) -> ^Box {
    return push_box(ctx, label, {.DrawBackground, .DrawBorder if border else nil}, axis, semantic_size = semantic_size);
}

label :: proc(ctx: ^Context, label: string) -> Interaction {
    box := push_box(ctx, label, {.DrawText});

    return test_box(ctx, box);
}

button :: proc(ctx: ^Context, label: string) -> Interaction {
    box := push_box(ctx, label, {.Clickable, .Hoverable, .DrawText, .DrawBorder, .DrawBackground});

    return test_box(ctx, box);
}

custom :: proc(ctx: ^Context, label: string, draw_func: CustomDrawFunc, user_data: rawptr) -> Interaction {
    box := push_box(ctx, label, {.DrawBorder, .CustomDrawFunc}, semantic_size = { make_semantic_size(.Fill), make_semantic_size(.Fill) });
    box.custom_draw_func = draw_func;
    box.user_data = user_data;

    return test_box(ctx, box);
}

two_buttons_test :: proc(ctx: ^Context, label1: string, label2: string) {
    push_parent(ctx, push_box(ctx, "TWO BUTTONS TEST", {.DrawBorder}, .Vertical, semantic_size = {make_semantic_size(.PercentOfParent, 100), { .Fill, 256}}));

    button(ctx, "Row 1");
    button(ctx, "Row 2");
    button(ctx, label1);
    button(ctx, label2);
    button(ctx, "Row 5");
    button(ctx, "Row 6");

    {
        push_parent(ctx, push_box(ctx, "two_button_container_inner", {.DrawBorder}, semantic_size = {make_semantic_size(.Fill, 0), { .Fill, 64}}));
        defer pop_parent(ctx);

        push_box(ctx, "1", {.DrawText, .DrawBackground, .DrawBorder}, semantic_size = {make_semantic_size(.Fill, 100), { .FitText, 256}})
        push_box(ctx, "2", {.DrawText, .DrawBackground, .DrawBorder}, semantic_size = {make_semantic_size(.Fill, 100), { .FitText, 256}})

        {
            push_parent(ctx, push_box(ctx, "two_button_container_inner_inner", {.DrawBorder}, .Vertical, semantic_size = {make_semantic_size(.Fill, 50), { .ChildrenSum, 256}}));
            defer pop_parent(ctx);

            button(ctx, "this is a test button");
            button(ctx, "me in the middle");
            button(ctx, "look at me, I'm a test button too");
        }

        push_box(ctx, "End", {.DrawBorder, .DrawBackground, .DrawText}, .Horizontal, semantic_size = {make_semantic_size(.Fill, 0), { .FitText, 0}})
    }
    button(ctx, "Help me I'm falling");
    pop_parent(ctx);
}
